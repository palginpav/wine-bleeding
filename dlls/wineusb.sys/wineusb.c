/*
 * USB root device enumerator using libusb
 *
 * Copyright 2020 Zebediah Figura
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA
 */

#include <assert.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#include "initguid.h"
#include "ntstatus.h"
#define WIN32_NO_STATUS
#include "windef.h"
#include "winioctl.h"
#include "winternl.h"
#include "ddk/wdm.h"
#include "ddk/usb.h"
#include "ddk/usb100.h"
#include "ddk/usbioctl.h"
#include "winusbioctl.h"
#include "wine/asm.h"
#include "wine/debug.h"
#include "wine/list.h"

#include "unixlib.h"

WINE_DEFAULT_DEBUG_CHANNEL(wineusb);

#ifdef __ASM_USE_FASTCALL_WRAPPER

extern void * WINAPI wrap_fastcall_func1( void *func, const void *a );
__ASM_STDCALL_FUNC( wrap_fastcall_func1, 8,
                   "popl %ecx\n\t"
                   "popl %eax\n\t"
                   "xchgl (%esp),%ecx\n\t"
                   "jmp *%eax" );

#define call_fastcall_func1(func,a) wrap_fastcall_func1(func,a)

#else

#define call_fastcall_func1(func,a) func(a)

#endif

#define DECLARE_CRITICAL_SECTION(cs) \
    static CRITICAL_SECTION cs; \
    static CRITICAL_SECTION_DEBUG cs##_debug = \
    { 0, 0, &cs, { &cs##_debug.ProcessLocksList, &cs##_debug.ProcessLocksList }, \
      0, 0, { (DWORD_PTR)(__FILE__ ": " # cs) }}; \
    static CRITICAL_SECTION cs = { &cs##_debug, -1, 0, 0, 0, 0 };

DECLARE_CRITICAL_SECTION(wineusb_cs);

static struct list device_list = LIST_INIT(device_list);

struct usb_device
{
    struct list entry;
    BOOL removed;

    DEVICE_OBJECT *device_obj;

    bool interface;
    int16_t interface_index;

    uint8_t class, subclass, protocol, busnum, portnum;

    uint16_t vendor, product, revision, usbver;

    struct unix_device *unix_device;

    LIST_ENTRY irp_list;

    /* Device interface for user-mode access (SetupAPI / CreateFile) */
    UNICODE_STRING link_name;
};

static DRIVER_OBJECT *driver_obj;
static DEVICE_OBJECT *bus_fdo, *bus_pdo;

static void destroy_unix_device(struct unix_device *unix_device)
{
    struct usb_destroy_device_params params =
    {
        .device = unix_device,
    };

    WINE_UNIX_CALL(unix_usb_destroy_device, &params);
}

static void add_unix_device(const struct usb_add_device_event *event)
{
    static unsigned int name_index;
    struct usb_device *device;
    DEVICE_OBJECT *device_obj;
    UNICODE_STRING string;
    NTSTATUS status;
    WCHAR name[26];

    TRACE("Adding new device %p, vendor %04x, product %04x.\n", event->device,
            event->vendor, event->product);

    swprintf(name, ARRAY_SIZE(name), L"\\Device\\USBPDO-%u", name_index++);
    RtlInitUnicodeString(&string, name);
    if ((status = IoCreateDevice(driver_obj, sizeof(*device), &string,
            FILE_DEVICE_USB, 0, FALSE, &device_obj)))
    {
        ERR("Failed to create device, status %#lx.\n", status);
        return;
    }

    device = device_obj->DeviceExtension;
    device->device_obj = device_obj;
    device->unix_device = event->device;
    InitializeListHead(&device->irp_list);
    device->removed = FALSE;

    device->interface = event->interface;
    device->interface_index = event->interface_index;

    device->class = event->class;
    device->subclass = event->subclass;
    device->protocol = event->protocol;
    device->busnum = event->busnum;
    device->portnum = event->portnum;

    device->vendor = event->vendor;
    device->product = event->product;
    device->revision = event->revision;
    device->usbver = event->usbver;

    EnterCriticalSection(&wineusb_cs);
    list_add_tail(&device_list, &device->entry);
    LeaveCriticalSection(&wineusb_cs);

    IoInvalidateDeviceRelations(bus_pdo, BusRelations);
}

static void remove_unix_device(struct unix_device *unix_device)
{
    struct usb_device *device;

    TRACE("Removing device %p.\n", unix_device);

    EnterCriticalSection(&wineusb_cs);
    LIST_FOR_EACH_ENTRY(device, &device_list, struct usb_device, entry)
    {
        if (device->unix_device == unix_device)
        {
            if (!device->removed)
            {
                device->removed = TRUE;
                /* Keep device in list so FDO REMOVE_DEVICE (e.g. at shutdown) can
                 * still find and destroy it if PDO REMOVE_DEVICE never arrives. */
            }
            break;
        }
    }
    LeaveCriticalSection(&wineusb_cs);

    IoInvalidateDeviceRelations(bus_pdo, BusRelations);
}

static HANDLE event_thread;

static void complete_irp(IRP *irp)
{
    EnterCriticalSection(&wineusb_cs);
    RemoveEntryList(&irp->Tail.Overlay.ListEntry);
    LeaveCriticalSection(&wineusb_cs);

    irp->IoStatus.Status = STATUS_SUCCESS;
    IoCompleteRequest(irp, IO_NO_INCREMENT);
}

static void complete_ioctl_irp(IRP *irp, NTSTATUS status, ULONG_PTR information)
{
    irp->IoStatus.Status = status;
    irp->IoStatus.Information = information;
    IoCompleteRequest(irp, IO_NO_INCREMENT);
}

static DWORD CALLBACK event_thread_proc(void *arg)
{
    struct usb_event event;
    struct usb_main_loop_params params =
    {
        .event = &event,
    };

    TRACE("Starting event thread.\n");

    if (WINE_UNIX_CALL(unix_usb_init, NULL) != STATUS_SUCCESS)
        return 0;

    while (WINE_UNIX_CALL(unix_usb_main_loop, &params) == STATUS_PENDING)
    {
        switch (event.type)
        {
            case USB_EVENT_ADD_DEVICE:
                add_unix_device(&event.u.added_device);
                break;

            case USB_EVENT_REMOVE_DEVICE:
                remove_unix_device(event.u.removed_device);
                break;

            case USB_EVENT_TRANSFER_COMPLETE:
                complete_irp(event.u.completed_irp);
                break;

            case USB_EVENT_IOCTL_COMPLETE:
                complete_ioctl_irp(event.u.ioctl_complete.irp,
                        event.u.ioctl_complete.status,
                        event.u.ioctl_complete.actual_length);
                break;
        }
    }

    TRACE("Shutting down event thread.\n");
    return 0;
}

static NTSTATUS fdo_pnp(IRP *irp)
{
    IO_STACK_LOCATION *stack = IoGetCurrentIrpStackLocation(irp);
    NTSTATUS ret;

    TRACE("irp %p, minor function %#x.\n", irp, stack->MinorFunction);

    switch (stack->MinorFunction)
    {
        case IRP_MN_QUERY_DEVICE_RELATIONS:
        {
            struct usb_device *device;
            DEVICE_RELATIONS *devices;
            unsigned int count = 0, i = 0;

            if (stack->Parameters.QueryDeviceRelations.Type == BusRelations)
            {
                EnterCriticalSection(&wineusb_cs);

            LIST_FOR_EACH_ENTRY(device, &device_list, struct usb_device, entry)
            {
                if (!device->removed)
                    count++;
            }
            if (!(devices = ExAllocatePool(PagedPool,
                    offsetof(DEVICE_RELATIONS, Objects[count]))))
            {
                LeaveCriticalSection(&wineusb_cs);
                irp->IoStatus.Status = STATUS_NO_MEMORY;
                break;
            }
            LIST_FOR_EACH_ENTRY(device, &device_list, struct usb_device, entry)
            {
                if (!device->removed)
                {
                    devices->Objects[i++] = device->device_obj;
                    call_fastcall_func1(ObfReferenceObject, device->device_obj);
                }
            }

            LeaveCriticalSection(&wineusb_cs);

            devices->Count = i;
            irp->IoStatus.Information = (ULONG_PTR)devices;
            irp->IoStatus.Status = STATUS_SUCCESS;
            break;
            }
            else if (stack->Parameters.QueryDeviceRelations.Type == RemovalRelations)
            {
                if (!(devices = ExAllocatePool(PagedPool, offsetof(DEVICE_RELATIONS, Objects[0]))))
                {
                    irp->IoStatus.Status = STATUS_NO_MEMORY;
                    break;
                }
                devices->Count = 0;
                irp->IoStatus.Information = (ULONG_PTR)devices;
                irp->IoStatus.Status = STATUS_SUCCESS;
                break;
            }
            else if (stack->Parameters.QueryDeviceRelations.Type == TargetDeviceRelation)
            {
                irp->IoStatus.Information = (ULONG_PTR)bus_fdo;
                call_fastcall_func1(ObfReferenceObject, bus_fdo);
                irp->IoStatus.Status = STATUS_SUCCESS;
                break;
            }
            else if (stack->Parameters.QueryDeviceRelations.Type == EjectionRelations ||
                     stack->Parameters.QueryDeviceRelations.Type == PowerRelations ||
                     stack->Parameters.QueryDeviceRelations.Type == SingleBusRelations)
            {
                if (!(devices = ExAllocatePool(PagedPool, offsetof(DEVICE_RELATIONS, Objects[0]))))
                {
                    irp->IoStatus.Status = STATUS_NO_MEMORY;
                    break;
                }
                devices->Count = 0;
                irp->IoStatus.Information = (ULONG_PTR)devices;
                irp->IoStatus.Status = STATUS_SUCCESS;
                break;
            }
            else
            {
                /* Unknown relation type: return empty list for compatibility. */
                TRACE("Unknown device relations type %#x, returning empty list.\n",
                        stack->Parameters.QueryDeviceRelations.Type);
                if (!(devices = ExAllocatePool(PagedPool, offsetof(DEVICE_RELATIONS, Objects[0]))))
                {
                    irp->IoStatus.Status = STATUS_NO_MEMORY;
                    break;
                }
                devices->Count = 0;
                irp->IoStatus.Information = (ULONG_PTR)devices;
                irp->IoStatus.Status = STATUS_SUCCESS;
                break;
            }
        }

        case IRP_MN_START_DEVICE:
            event_thread = CreateThread(NULL, 0, event_thread_proc, NULL, 0, NULL);

            irp->IoStatus.Status = STATUS_SUCCESS;
            break;

        case IRP_MN_SURPRISE_REMOVAL:
            irp->IoStatus.Status = STATUS_SUCCESS;
            break;

        case IRP_MN_REMOVE_DEVICE:
        {
            struct usb_device *device, *cursor;

            WINE_UNIX_CALL(unix_usb_exit, NULL);
            WaitForSingleObject(event_thread, INFINITE);
            CloseHandle(event_thread);

            EnterCriticalSection(&wineusb_cs);
            /* Destroy all devices still in the list (including those marked removed
             * by hot-unplug that may not have received PDO REMOVE_DEVICE yet). */
            LIST_FOR_EACH_ENTRY_SAFE(device, cursor, &device_list, struct usb_device, entry)
            {
                destroy_unix_device(device->unix_device);
                list_remove(&device->entry);
                IoDeleteDevice(device->device_obj);
            }
            LeaveCriticalSection(&wineusb_cs);

            irp->IoStatus.Status = STATUS_SUCCESS;
            IoSkipCurrentIrpStackLocation(irp);
            ret = IoCallDriver(bus_pdo, irp);
            IoDetachDevice(bus_pdo);
            IoDeleteDevice(bus_fdo);
            return ret;
        }

        case IRP_MN_QUERY_ID:
            break;

        case IRP_MN_QUERY_REMOVE_DEVICE:
        case IRP_MN_QUERY_STOP_DEVICE:
            /* Forward to parent; bus typically allows remove/stop. */
            break;

        case IRP_MN_QUERY_BUS_INFORMATION:
            irp->IoStatus.Status = STATUS_NOT_SUPPORTED;
            irp->IoStatus.Information = 0;
            IoCompleteRequest(irp, IO_NO_INCREMENT);
            return STATUS_NOT_SUPPORTED;

        default:
            TRACE("FDO: forwarding minor function %#x to parent.\n", stack->MinorFunction);
            break;
    }

    IoSkipCurrentIrpStackLocation(irp);
    return IoCallDriver(bus_pdo, irp);
}

struct string_buffer
{
    WCHAR *string;
    size_t len;
};

static void WINAPIV append_id(struct string_buffer *buffer, const WCHAR *format, ...)
{
    va_list args;
    WCHAR *string;
    int len;

    va_start(args, format);

    len = _vsnwprintf(NULL, 0, format, args) + 1;
    if (!(string = ExAllocatePool(PagedPool, (buffer->len + len) * sizeof(WCHAR))))
    {
        if (buffer->string)
            ExFreePool(buffer->string);
        buffer->string = NULL;
        return;
    }
    if (buffer->string)
    {
        memcpy(string, buffer->string, buffer->len * sizeof(WCHAR));
        ExFreePool(buffer->string);
    }
    _vsnwprintf(string + buffer->len, len, format, args);
    buffer->string = string;
    buffer->len += len;

    va_end(args);
}

static void get_device_id(const struct usb_device *device, struct string_buffer *buffer)
{
    if (device->interface)
        append_id(buffer, L"USB\\VID_%04X&PID_%04X&MI_%02X",
                device->vendor, device->product, device->interface_index);
    else
        append_id(buffer, L"USB\\VID_%04X&PID_%04X", device->vendor, device->product);
}

static void get_instance_id(const struct usb_device *device, struct string_buffer *buffer)
{
    append_id(buffer, L"%u&%u&%u&%u", device->usbver, device->revision, device->busnum, device->portnum);
}

static void get_hardware_ids(const struct usb_device *device, struct string_buffer *buffer)
{
    if (device->interface)
        append_id(buffer, L"USB\\VID_%04X&PID_%04X&REV_%04X&MI_%02X",
                device->vendor, device->product, device->revision, device->interface_index);
    else
        append_id(buffer, L"USB\\VID_%04X&PID_%04X&REV_%04X",
                device->vendor, device->product, device->revision);

    get_device_id(device, buffer);
    append_id(buffer, L"");
}

static void get_compatible_ids(const struct usb_device *device, struct string_buffer *buffer)
{
    if (device->interface_index != -1)
    {
        append_id(buffer, L"USB\\Class_%02x&SubClass_%02x&Prot_%02x",
                device->class, device->subclass, device->protocol);
        append_id(buffer, L"USB\\Class_%02x&SubClass_%02x", device->class, device->subclass);
        append_id(buffer, L"USB\\Class_%02x", device->class);
    }
    else
    {
        append_id(buffer, L"USB\\DevClass_%02x&SubClass_%02x&Prot_%02x",
                device->class, device->subclass, device->protocol);
        append_id(buffer, L"USB\\DevClass_%02x&SubClass_%02x", device->class, device->subclass);
        append_id(buffer, L"USB\\DevClass_%02x", device->class);
    }
    append_id(buffer, L"");
}

static NTSTATUS query_id(struct usb_device *device, IRP *irp, BUS_QUERY_ID_TYPE type)
{
    struct string_buffer buffer = {0};

    TRACE("type %#x.\n", type);

    switch (type)
    {
        case BusQueryDeviceID:
            get_device_id(device, &buffer);
            break;

        case BusQueryInstanceID:
            get_instance_id(device, &buffer);
            break;

        case BusQueryHardwareIDs:
            get_hardware_ids(device, &buffer);
            break;

        case BusQueryCompatibleIDs:
            get_compatible_ids(device, &buffer);
            break;

        case BusQueryDeviceSerialNumber:
        {
            struct usb_get_serial_params serial_params = { .device = device->unix_device };
            WCHAR *wserial;
            ULONG i, len;

            if (WINE_UNIX_CALL(unix_usb_get_serial_number, &serial_params))
            {
                irp->IoStatus.Status = STATUS_UNSUCCESSFUL;
                return STATUS_UNSUCCESSFUL;
            }
            for (len = 0; serial_params.serial[len]; len++) ;
            if (!len)
            {
                irp->IoStatus.Status = STATUS_NOT_SUPPORTED;
                return STATUS_NOT_SUPPORTED;
            }
            if (!(wserial = ExAllocatePool(PagedPool, (len + 1) * sizeof(WCHAR))))
                return STATUS_NO_MEMORY;
            for (i = 0; i <= len; i++)
                wserial[i] = (WCHAR)(unsigned char)serial_params.serial[i];
            irp->IoStatus.Information = (ULONG_PTR)wserial;
            return STATUS_SUCCESS;
        }

        case BusQueryContainerID:
            TRACE("Query type %#x not supported.\n", type);
            irp->IoStatus.Status = STATUS_NOT_SUPPORTED;
            return STATUS_NOT_SUPPORTED;

        default:
            TRACE("QueryId type %#x not supported.\n", type);
            irp->IoStatus.Status = STATUS_NOT_SUPPORTED;
            return STATUS_NOT_SUPPORTED;
    }

    if (!buffer.string)
        return STATUS_NO_MEMORY;

    irp->IoStatus.Information = (ULONG_PTR)buffer.string;
    return STATUS_SUCCESS;
}

static void remove_pending_irps(struct usb_device *device)
{
    LIST_ENTRY *entry;
    IRP *irp;

    while ((entry = RemoveHeadList(&device->irp_list)) != &device->irp_list)
    {
        irp = CONTAINING_RECORD(entry, IRP, Tail.Overlay.ListEntry);
        irp->IoStatus.Status = STATUS_DELETE_PENDING;
        irp->IoStatus.Information = 0;
        IoCompleteRequest(irp, IO_NO_INCREMENT);
    }
}

static NTSTATUS pdo_pnp(DEVICE_OBJECT *device_obj, IRP *irp)
{
    IO_STACK_LOCATION *stack = IoGetCurrentIrpStackLocation(irp);
    struct usb_device *device = device_obj->DeviceExtension;
    NTSTATUS ret = irp->IoStatus.Status;

    TRACE("device_obj %p, irp %p, minor function %#x.\n", device_obj, irp, stack->MinorFunction);

    switch (stack->MinorFunction)
    {
        case IRP_MN_QUERY_ID:
            ret = query_id(device, irp, stack->Parameters.QueryId.IdType);
            break;

        case IRP_MN_QUERY_CAPABILITIES:
        {
            DEVICE_CAPABILITIES *caps = stack->Parameters.DeviceCapabilities.Capabilities;

            caps->RawDeviceOK = 1;

            ret = STATUS_SUCCESS;
            break;
        }

        case IRP_MN_START_DEVICE:
        {
            NTSTATUS reg_status;

            reg_status = IoRegisterDeviceInterface(device_obj, &GUID_DEVINTERFACE_USB_DEVICE, NULL, &device->link_name);
            if (reg_status)
            {
                ERR("Failed to register device interface, status %#lx.\n", reg_status);
                ret = reg_status;
                break;
            }
            IoSetDeviceInterfaceState(&device->link_name, TRUE);
            ret = STATUS_SUCCESS;
            break;
        }

        case IRP_MN_SURPRISE_REMOVAL:
            if (device->link_name.Buffer)
                IoSetDeviceInterfaceState(&device->link_name, FALSE);
            EnterCriticalSection(&wineusb_cs);
            remove_pending_irps(device);
            if (!device->removed)
                device->removed = TRUE;
            LeaveCriticalSection(&wineusb_cs);
            ret = STATUS_SUCCESS;
            break;

        case IRP_MN_REMOVE_DEVICE:
            assert(device->removed);
            remove_pending_irps(device);
            if (device->link_name.Buffer)
            {
                IoSetDeviceInterfaceState(&device->link_name, FALSE);
                RtlFreeUnicodeString(&device->link_name);
            }
            EnterCriticalSection(&wineusb_cs);
            list_remove(&device->entry);
            LeaveCriticalSection(&wineusb_cs);
            destroy_unix_device(device->unix_device);

            IoDeleteDevice(device->device_obj);
            ret = STATUS_SUCCESS;
            break;

        case IRP_MN_QUERY_DEVICE_TEXT:
            ret = STATUS_NOT_SUPPORTED;
            break;

        case IRP_MN_QUERY_PNP_DEVICE_STATE:
            irp->IoStatus.Information = 0; /* device normal, not disabled */
            ret = STATUS_SUCCESS;
            break;

        default:
            TRACE("PDO: unhandled minor function %#x.\n", stack->MinorFunction);
            ret = STATUS_NOT_SUPPORTED;
            break;
    }

    irp->IoStatus.Status = ret;
    IoCompleteRequest(irp, IO_NO_INCREMENT);
    return ret;
}

static NTSTATUS WINAPI driver_create(DEVICE_OBJECT *device_obj, IRP *irp)
{
    /* Allow opening PDOs (USB devices) for user-mode access via the device interface. */
    if (device_obj != bus_fdo)
    {
        irp->IoStatus.Status = STATUS_SUCCESS;
        irp->IoStatus.Information = 0;
        IoCompleteRequest(irp, IO_NO_INCREMENT);
        return STATUS_SUCCESS;
    }
    irp->IoStatus.Status = STATUS_INVALID_DEVICE_REQUEST;
    irp->IoStatus.Information = 0;
    IoCompleteRequest(irp, IO_NO_INCREMENT);
    return STATUS_INVALID_DEVICE_REQUEST;
}

static NTSTATUS handle_get_config_descriptor(struct usb_device *device, IRP *irp)
{
    IO_STACK_LOCATION *stack = IoGetCurrentIrpStackLocation(irp);
    void *out_buf = irp->AssociatedIrp.SystemBuffer;
    ULONG out_len = stack->Parameters.DeviceIoControl.OutputBufferLength;
    UCHAR setup[8];
    struct usb_control_transfer_sync_params params;
    ULONG actual = 0;

    if (!out_buf || out_len < sizeof(USB_CONFIGURATION_DESCRIPTOR))
        return STATUS_BUFFER_TOO_SMALL;

    setup[0] = 0x80; /* IN, standard, device */
    setup[1] = 0x06; /* GET_DESCRIPTOR */
    setup[2] = 0x02; setup[3] = 0x00; /* wValue: config descriptor type */
    setup[4] = 0; setup[5] = 0;      /* wIndex: 0 */
    setup[6] = (UCHAR)(out_len & 0xff); setup[7] = (UCHAR)(out_len >> 8);

    params.device = device->unix_device;
    memcpy(params.setup, setup, 8);
    params.buffer = out_buf;
    params.length = out_len;
    params.actual_length = &actual;

    if (WINE_UNIX_CALL(unix_usb_control_transfer_sync, &params))
        return STATUS_UNSUCCESSFUL;
    irp->IoStatus.Information = actual;
    return STATUS_SUCCESS;
}

static NTSTATUS handle_control_transfer(struct usb_device *device, IRP *irp)
{
    IO_STACK_LOCATION *stack = IoGetCurrentIrpStackLocation(irp);
    void *buf = irp->AssociatedIrp.SystemBuffer;
    ULONG in_len = stack->Parameters.DeviceIoControl.InputBufferLength;
    ULONG out_len = stack->Parameters.DeviceIoControl.OutputBufferLength;
    struct usb_control_transfer_async_params params;
    UCHAR *setup;
    ULONG data_len;
    NTSTATUS status;

    if (!buf || in_len < 8)
        return STATUS_INVALID_PARAMETER;
    setup = buf;
    data_len = (setup[7] << 8) | setup[6];
    if (setup[0] & 0x80) /* IN */
    {
        if (out_len < data_len)
            return STATUS_BUFFER_TOO_SMALL;
        params.buffer = buf;
        params.length = out_len;
    }
    else
    {
        if (in_len < 8 + data_len)
            return STATUS_INVALID_PARAMETER;
        params.buffer = (char *)buf + 8;
        params.length = data_len;
    }
    params.device = device->unix_device;
    memcpy(params.setup, setup, 8);
    params.irp = irp;

    status = WINE_UNIX_CALL(unix_usb_control_transfer_async, &params);
    if (status == STATUS_PENDING)
    {
        IoMarkIrpPending(irp);
        return STATUS_PENDING;
    }
    return status;
}

static NTSTATUS handle_read_pipe(struct usb_device *device, IRP *irp)
{
    IO_STACK_LOCATION *stack = IoGetCurrentIrpStackLocation(irp);
    void *in_buf = irp->AssociatedIrp.SystemBuffer;
    void *out_buf = irp->AssociatedIrp.SystemBuffer;
    ULONG in_len = stack->Parameters.DeviceIoControl.InputBufferLength;
    ULONG out_len = stack->Parameters.DeviceIoControl.OutputBufferLength;
    struct usb_bulk_transfer_async_params params;
    NTSTATUS status;

    if (!in_buf || in_len < 1 || !out_buf || out_len == 0)
        return STATUS_INVALID_PARAMETER;

    params.device = device->unix_device;
    params.endpoint = *(UCHAR *)in_buf;
    params.buffer = out_buf;
    params.length = out_len;
    params.in = TRUE;
    params.irp = irp;
    params.timeout_ms = (in_len >= 5) ? *(ULONG *)((char *)in_buf + 1) : 0;

    status = WINE_UNIX_CALL(unix_usb_bulk_transfer_async, &params);
    if (status == STATUS_PENDING)
    {
        IoMarkIrpPending(irp);
        return STATUS_PENDING;
    }
    return status;
}

static NTSTATUS handle_write_pipe(struct usb_device *device, IRP *irp)
{
    IO_STACK_LOCATION *stack = IoGetCurrentIrpStackLocation(irp);
    void *buf = irp->AssociatedIrp.SystemBuffer;
    ULONG in_len = stack->Parameters.DeviceIoControl.InputBufferLength;
    struct usb_bulk_transfer_async_params params;
    NTSTATUS status;

    if (!buf || in_len < 2)
        return STATUS_INVALID_PARAMETER;

    params.device = device->unix_device;
    params.endpoint = *(UCHAR *)buf;
    params.buffer = (char *)buf + 1;
    params.length = in_len - 1;
    params.in = FALSE;
    params.irp = irp;
    params.timeout_ms = 0;

    status = WINE_UNIX_CALL(unix_usb_bulk_transfer_async, &params);
    if (status == STATUS_PENDING)
    {
        IoMarkIrpPending(irp);
        return STATUS_PENDING;
    }
    return status;
}

static NTSTATUS handle_abort_pipe(struct usb_device *device, IRP *irp)
{
    LIST_ENTRY *entry, *mark;

    TRACE("device %p, aborting pending transfers\n", device);

    /* The documentation states that URB_FUNCTION_ABORT_PIPE may
     * complete before outstanding requests complete, so we don't need
     * to wait for them. We mimic the same behaviour here for the
     * user-mode WinUSB AbortPipe IOCTL. */
    EnterCriticalSection(&wineusb_cs);
    mark = &device->irp_list;
    for (entry = mark->Flink; entry != mark; entry = entry->Flink)
    {
        IRP *queued_irp = CONTAINING_RECORD(entry, IRP, Tail.Overlay.ListEntry);
        struct usb_cancel_transfer_params params =
        {
            .transfer = queued_irp->Tail.Overlay.DriverContext[0],
        };

        WINE_UNIX_CALL(unix_usb_cancel_transfer, &params);
    }
    LeaveCriticalSection(&wineusb_cs);

    irp->IoStatus.Information = 0;
    return STATUS_SUCCESS;
}

static NTSTATUS handle_set_interface(struct usb_device *device, IRP *irp)
{
    IO_STACK_LOCATION *stack = IoGetCurrentIrpStackLocation(irp);
    void *in_buf = irp->AssociatedIrp.SystemBuffer;
    ULONG in_len = stack->Parameters.DeviceIoControl.InputBufferLength;
    struct usb_set_interface_alt_setting_params params;

    if (!in_buf || in_len < 2)
        return STATUS_INVALID_PARAMETER;

    params.device = device->unix_device;
    params.interface_number = ((UCHAR *)in_buf)[0];
    params.alternate_setting = ((UCHAR *)in_buf)[1];

    if (WINE_UNIX_CALL(unix_usb_set_interface_alt_setting, &params))
        return STATUS_UNSUCCESSFUL;

    irp->IoStatus.Information = 0;
    return STATUS_SUCCESS;
}

#define DEVICE_SPEED 0x01

static NTSTATUS handle_query_device_info(struct usb_device *device, IRP *irp)
{
    IO_STACK_LOCATION *stack = IoGetCurrentIrpStackLocation(irp);
    void *in_buf = irp->AssociatedIrp.SystemBuffer;
    void *out_buf = irp->AssociatedIrp.SystemBuffer;
    ULONG in_len = stack->Parameters.DeviceIoControl.InputBufferLength;
    ULONG out_len = stack->Parameters.DeviceIoControl.OutputBufferLength;
    struct usb_get_device_speed_params params;

    if (!in_buf || in_len < sizeof(ULONG) || !out_buf || out_len < sizeof(ULONG))
        return STATUS_INVALID_PARAMETER;

    if (*(ULONG *)in_buf != DEVICE_SPEED)
        return STATUS_INVALID_PARAMETER;

    params.device = device->unix_device;
    params.speed = 0;
    if (WINE_UNIX_CALL(unix_usb_get_device_speed, &params))
        return STATUS_UNSUCCESSFUL;

    *(ULONG *)out_buf = params.speed;
    irp->IoStatus.Information = sizeof(ULONG);
    return STATUS_SUCCESS;
}

static NTSTATUS WINAPI driver_device_control(DEVICE_OBJECT *device_obj, IRP *irp)
{
    IO_STACK_LOCATION *stack = IoGetCurrentIrpStackLocation(irp);
    ULONG code = stack->Parameters.DeviceIoControl.IoControlCode;
    struct usb_device *device = device_obj->DeviceExtension;
    NTSTATUS status;
    BOOL removed;

    if (device_obj == bus_fdo)
    {
        irp->IoStatus.Status = STATUS_INVALID_DEVICE_REQUEST;
        irp->IoStatus.Information = 0;
        IoCompleteRequest(irp, IO_NO_INCREMENT);
        return STATUS_INVALID_DEVICE_REQUEST;
    }

    EnterCriticalSection(&wineusb_cs);
    removed = device->removed;
    LeaveCriticalSection(&wineusb_cs);
    if (removed)
    {
        irp->IoStatus.Status = STATUS_DELETE_PENDING;
        irp->IoStatus.Information = 0;
        IoCompleteRequest(irp, IO_NO_INCREMENT);
        return STATUS_DELETE_PENDING;
    }

    switch (code)
    {
        case IOCTL_WINEUSB_GET_CONFIG_DESCRIPTOR:
            status = handle_get_config_descriptor(device, irp);
            break;
        case IOCTL_WINEUSB_CONTROL_TRANSFER:
            status = handle_control_transfer(device, irp);
            break;
        case IOCTL_WINEUSB_READ_PIPE:
            status = handle_read_pipe(device, irp);
            break;
        case IOCTL_WINEUSB_WRITE_PIPE:
            status = handle_write_pipe(device, irp);
            break;
        case IOCTL_WINEUSB_ABORT_PIPE:
            status = handle_abort_pipe(device, irp);
            break;
        case IOCTL_WINEUSB_SET_INTERFACE:
            status = handle_set_interface(device, irp);
            break;
        case IOCTL_WINEUSB_QUERY_DEVICE_INFO:
            status = handle_query_device_info(device, irp);
            break;
        default:
            TRACE("Unhandled ioctl %#lx.\n", code);
            status = STATUS_NOT_IMPLEMENTED;
    }

    if (status == STATUS_PENDING)
        return STATUS_PENDING;

    irp->IoStatus.Status = status;
    IoCompleteRequest(irp, IO_NO_INCREMENT);
    return status;
}

static NTSTATUS WINAPI driver_pnp(DEVICE_OBJECT *device, IRP *irp)
{
    if (device == bus_fdo)
        return fdo_pnp(irp);
    return pdo_pnp(device, irp);
}

static NTSTATUS usb_submit_urb(struct usb_device *device, IRP *irp)
{
    URB *urb = IoGetCurrentIrpStackLocation(irp)->Parameters.Others.Argument1;
    NTSTATUS status;

    TRACE("type %#x.\n", urb->UrbHeader.Function);

    switch (urb->UrbHeader.Function)
    {
        case URB_FUNCTION_ABORT_PIPE:
        {
            LIST_ENTRY *entry, *mark;

            /* The documentation states that URB_FUNCTION_ABORT_PIPE may
             * complete before outstanding requests complete, so we don't need
             * to wait for them. */
            EnterCriticalSection(&wineusb_cs);
            mark = &device->irp_list;
            for (entry = mark->Flink; entry != mark; entry = entry->Flink)
            {
                IRP *queued_irp = CONTAINING_RECORD(entry, IRP, Tail.Overlay.ListEntry);
                struct usb_cancel_transfer_params params =
                {
                    .transfer = queued_irp->Tail.Overlay.DriverContext[0],
                };

                WINE_UNIX_CALL(unix_usb_cancel_transfer, &params);
            }
            LeaveCriticalSection(&wineusb_cs);

            return STATUS_SUCCESS;
        }

        case URB_FUNCTION_SYNC_RESET_PIPE:
        case URB_FUNCTION_SYNC_CLEAR_STALL:
        case URB_FUNCTION_SYNC_RESET_PIPE_AND_CLEAR_STALL:
        case URB_FUNCTION_ISOCH_TRANSFER:
        case URB_FUNCTION_BULK_OR_INTERRUPT_TRANSFER:
        case URB_FUNCTION_CONTROL_TRANSFER:
        case URB_FUNCTION_GET_DESCRIPTOR_FROM_DEVICE:
        case URB_FUNCTION_GET_DESCRIPTOR_FROM_INTERFACE:
        case URB_FUNCTION_GET_CONFIGURATION:
        case URB_FUNCTION_GET_INTERFACE:
        case URB_FUNCTION_SET_FEATURE_TO_DEVICE:
        case URB_FUNCTION_SET_FEATURE_TO_INTERFACE:
        case URB_FUNCTION_SET_FEATURE_TO_ENDPOINT:
        case URB_FUNCTION_CLEAR_FEATURE_TO_DEVICE:
        case URB_FUNCTION_CLEAR_FEATURE_TO_INTERFACE:
        case URB_FUNCTION_CLEAR_FEATURE_TO_ENDPOINT:
        case URB_FUNCTION_GET_STATUS_FROM_DEVICE:
        case URB_FUNCTION_GET_STATUS_FROM_INTERFACE:
        case URB_FUNCTION_GET_STATUS_FROM_ENDPOINT:
        case URB_FUNCTION_GET_STATUS_FROM_OTHER:
        case URB_FUNCTION_GET_CURRENT_FRAME_NUMBER:
        case URB_FUNCTION_GET_FRAME_LENGTH:
        case URB_FUNCTION_SET_FRAME_LENGTH:
        case URB_FUNCTION_TAKE_FRAME_LENGTH_CONTROL:
        case URB_FUNCTION_RELEASE_FRAME_LENGTH_CONTROL:
        case URB_FUNCTION_SELECT_INTERFACE:
        case URB_FUNCTION_SELECT_CONFIGURATION:
        case URB_FUNCTION_CLASS_DEVICE:
        case URB_FUNCTION_CLASS_INTERFACE:
        case URB_FUNCTION_CLASS_ENDPOINT:
        case URB_FUNCTION_CLASS_OTHER:
        case URB_FUNCTION_VENDOR_DEVICE:
        case URB_FUNCTION_VENDOR_INTERFACE:
        case URB_FUNCTION_VENDOR_ENDPOINT:
        case URB_FUNCTION_VENDOR_OTHER:
        {
            struct usb_submit_urb_params params =
            {
                .device = device->unix_device,
                .irp = irp,
            };

            switch (urb->UrbHeader.Function)
            {
                case URB_FUNCTION_ISOCH_TRANSFER:
                {
                    struct _URB_ISOCH_TRANSFER *req = &urb->UrbIsochronousTransfer;
                    if (req->TransferBufferMDL)
                        params.transfer_buffer = MmGetSystemAddressForMdlSafe(req->TransferBufferMDL, NormalPagePriority);
                    else
                        params.transfer_buffer = req->TransferBuffer;
                    break;
                }

                case URB_FUNCTION_BULK_OR_INTERRUPT_TRANSFER:
                {
                    struct _URB_BULK_OR_INTERRUPT_TRANSFER *req = &urb->UrbBulkOrInterruptTransfer;
                    if (req->TransferBufferMDL)
                        params.transfer_buffer = MmGetSystemAddressForMdlSafe(req->TransferBufferMDL, NormalPagePriority);
                    else
                        params.transfer_buffer = req->TransferBuffer;
                    break;
                }

                case URB_FUNCTION_CONTROL_TRANSFER:
                {
                    struct _URB_CONTROL_TRANSFER *req = &urb->UrbControlTransfer;
                    if (req->TransferBufferMDL)
                        params.transfer_buffer = MmGetSystemAddressForMdlSafe(req->TransferBufferMDL, NormalPagePriority);
                    else
                        params.transfer_buffer = req->TransferBuffer;
                    break;
                }

                case URB_FUNCTION_GET_DESCRIPTOR_FROM_DEVICE:
                case URB_FUNCTION_GET_DESCRIPTOR_FROM_INTERFACE:
                {
                    struct _URB_CONTROL_DESCRIPTOR_REQUEST *req = &urb->UrbControlDescriptorRequest;
                    if (req->TransferBufferMDL)
                        params.transfer_buffer = MmGetSystemAddressForMdlSafe(req->TransferBufferMDL, NormalPagePriority);
                    else
                        params.transfer_buffer = req->TransferBuffer;
                    break;
                }

                case URB_FUNCTION_GET_CONFIGURATION:
                {
                    struct _URB_CONTROL_GET_CONFIGURATION_REQUEST *req = &urb->UrbControlGetConfigurationRequest;
                    if (req->TransferBufferMDL)
                        params.transfer_buffer = MmGetSystemAddressForMdlSafe(req->TransferBufferMDL, NormalPagePriority);
                    else
                        params.transfer_buffer = req->TransferBuffer;
                    break;
                }

                case URB_FUNCTION_GET_INTERFACE:
                {
                    struct _URB_CONTROL_GET_INTERFACE_REQUEST *req = &urb->UrbControlGetInterfaceRequest;
                    if (req->TransferBufferMDL)
                        params.transfer_buffer = MmGetSystemAddressForMdlSafe(req->TransferBufferMDL, NormalPagePriority);
                    else
                        params.transfer_buffer = req->TransferBuffer;
                    break;
                }

                case URB_FUNCTION_SET_FEATURE_TO_DEVICE:
                case URB_FUNCTION_SET_FEATURE_TO_INTERFACE:
                case URB_FUNCTION_SET_FEATURE_TO_ENDPOINT:
                case URB_FUNCTION_CLEAR_FEATURE_TO_DEVICE:
                case URB_FUNCTION_CLEAR_FEATURE_TO_INTERFACE:
                case URB_FUNCTION_CLEAR_FEATURE_TO_ENDPOINT:
                    params.transfer_buffer = NULL;
                    break;

                case URB_FUNCTION_GET_STATUS_FROM_DEVICE:
                case URB_FUNCTION_GET_STATUS_FROM_INTERFACE:
                case URB_FUNCTION_GET_STATUS_FROM_ENDPOINT:
                case URB_FUNCTION_GET_STATUS_FROM_OTHER:
                {
                    struct _URB_CONTROL_GET_STATUS_REQUEST *req = &urb->UrbControlGetStatusRequest;
                    if (req->TransferBufferMDL)
                        params.transfer_buffer = MmGetSystemAddressForMdlSafe(req->TransferBufferMDL, NormalPagePriority);
                    else
                        params.transfer_buffer = req->TransferBuffer;
                    break;
                }

                case URB_FUNCTION_SYNC_RESET_PIPE:
                case URB_FUNCTION_SYNC_CLEAR_STALL:
                    params.transfer_buffer = NULL;
                    break;

                case URB_FUNCTION_GET_CURRENT_FRAME_NUMBER:
                case URB_FUNCTION_GET_FRAME_LENGTH:
                case URB_FUNCTION_SET_FRAME_LENGTH:
                case URB_FUNCTION_TAKE_FRAME_LENGTH_CONTROL:
                case URB_FUNCTION_RELEASE_FRAME_LENGTH_CONTROL:
                case URB_FUNCTION_SELECT_INTERFACE:
                case URB_FUNCTION_SELECT_CONFIGURATION:
                    params.transfer_buffer = NULL;
                    break;

                case URB_FUNCTION_VENDOR_DEVICE:
                case URB_FUNCTION_VENDOR_INTERFACE:
                case URB_FUNCTION_VENDOR_ENDPOINT:
                case URB_FUNCTION_VENDOR_OTHER:
                case URB_FUNCTION_CLASS_DEVICE:
                case URB_FUNCTION_CLASS_INTERFACE:
                case URB_FUNCTION_CLASS_ENDPOINT:
                case URB_FUNCTION_CLASS_OTHER:
                {
                    struct _URB_CONTROL_VENDOR_OR_CLASS_REQUEST *req = &urb->UrbControlVendorClassRequest;
                    if (req->TransferBufferMDL)
                        params.transfer_buffer = MmGetSystemAddressForMdlSafe(req->TransferBufferMDL, NormalPagePriority);
                    else
                        params.transfer_buffer = req->TransferBuffer;
                    break;
                }
            }

            /* Hold the wineusb lock while submitting and queuing, and
             * similarly hold it in complete_irp(). That way, if libusb reports
             * completion between submitting and queuing, we won't try to
             * dequeue the IRP until it's actually been queued. */
            EnterCriticalSection(&wineusb_cs);
            status = WINE_UNIX_CALL(unix_usb_submit_urb, &params);
            if (status == STATUS_PENDING)
            {
                IoMarkIrpPending(irp);
                InsertTailList(&device->irp_list, &irp->Tail.Overlay.ListEntry);
            }
            LeaveCriticalSection(&wineusb_cs);

            return status;
        }

        default:
            TRACE("Unhandled URB function %#x.\n", urb->UrbHeader.Function);
            status = STATUS_NOT_IMPLEMENTED;
            break;
    }

    return STATUS_NOT_IMPLEMENTED;
}

static NTSTATUS WINAPI driver_internal_ioctl(DEVICE_OBJECT *device_obj, IRP *irp)
{
    IO_STACK_LOCATION *stack = IoGetCurrentIrpStackLocation(irp);
    ULONG code = stack->Parameters.DeviceIoControl.IoControlCode;
    struct usb_device *device = device_obj->DeviceExtension;
    NTSTATUS status = STATUS_NOT_IMPLEMENTED;
    BOOL removed;

    TRACE("device_obj %p, irp %p, code %#lx.\n", device_obj, irp, code);

    EnterCriticalSection(&wineusb_cs);
    removed = device->removed;
    LeaveCriticalSection(&wineusb_cs);

    if (removed)
    {
        irp->IoStatus.Status = STATUS_DELETE_PENDING;
        IoCompleteRequest(irp, IO_NO_INCREMENT);
        return STATUS_DELETE_PENDING;
    }

    switch (code)
    {
        case IOCTL_INTERNAL_USB_SUBMIT_URB:
            status = usb_submit_urb(device, irp);
            break;

        default:
            TRACE("Unhandled internal ioctl %#lx.\n", code);
    }

    if (status != STATUS_PENDING)
    {
        irp->IoStatus.Status = status;
        IoCompleteRequest(irp, IO_NO_INCREMENT);
    }
    return status;
}

static NTSTATUS WINAPI driver_add_device(DRIVER_OBJECT *driver, DEVICE_OBJECT *pdo)
{
    NTSTATUS ret;

    TRACE("driver %p, pdo %p.\n", driver, pdo);

    if ((ret = IoCreateDevice(driver, 0, NULL, FILE_DEVICE_BUS_EXTENDER, 0, FALSE, &bus_fdo)))
    {
        ERR("Failed to create FDO, status %#lx.\n", ret);
        return ret;
    }

    IoAttachDeviceToDeviceStack(bus_fdo, pdo);
    bus_pdo = pdo;
    bus_fdo->Flags &= ~DO_DEVICE_INITIALIZING;

    return STATUS_SUCCESS;
}

static void WINAPI driver_unload(DRIVER_OBJECT *driver)
{
}

NTSTATUS WINAPI DriverEntry(DRIVER_OBJECT *driver, UNICODE_STRING *path)
{
    NTSTATUS status;

    TRACE("driver %p, path %s.\n", driver, debugstr_w(path->Buffer));

    if ((status = __wine_init_unix_call()))
    {
        ERR("Failed to initialize Unix library, status %#lx.\n", status);
        return status;
    }

    driver_obj = driver;

    driver->DriverExtension->AddDevice = driver_add_device;
    driver->DriverUnload = driver_unload;
    driver->MajorFunction[IRP_MJ_CREATE] = driver_create;
    driver->MajorFunction[IRP_MJ_DEVICE_CONTROL] = driver_device_control;
    driver->MajorFunction[IRP_MJ_PNP] = driver_pnp;
    driver->MajorFunction[IRP_MJ_INTERNAL_DEVICE_CONTROL] = driver_internal_ioctl;

    return STATUS_SUCCESS;
}
