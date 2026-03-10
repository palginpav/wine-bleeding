/*
 * libusb backend
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

#if 0
#pragma makedep unix
#endif

#include <stdarg.h>
#include <stdbool.h>
#include <stdlib.h>
#include <time.h>
#include <libusb.h>
#include <pthread.h>
#include "ntstatus.h"
#define WIN32_NO_STATUS
#include "windef.h"
#include "winternl.h"
#include "ddk/wdm.h"
#include "ddk/usb.h"
#include "wine/debug.h"
#include "wine/list.h"

#include "unixlib.h"

WINE_DEFAULT_DEBUG_CHANNEL(wineusb);

struct unix_device
{
    struct list entry;

    libusb_device_handle *handle;
    struct unix_device *parent;
    unsigned int refcount;
};

static libusb_hotplug_callback_handle hotplug_cb_handle;

static volatile bool thread_shutdown;

static struct usb_event *usb_events;
static size_t usb_event_count, usb_events_capacity;

static pthread_mutex_t device_mutex = PTHREAD_MUTEX_INITIALIZER;

static struct list device_list = LIST_INIT(device_list);

static bool array_reserve(void **elements, size_t *capacity, size_t count, size_t size)
{
    unsigned int new_capacity, max_capacity;
    void *new_elements;

    if (count <= *capacity)
        return true;

    max_capacity = ~(size_t)0 / size;
    if (count > max_capacity)
        return false;

    new_capacity = max(4, *capacity);
    while (new_capacity < count && new_capacity <= max_capacity / 2)
        new_capacity *= 2;
    if (new_capacity < count)
        new_capacity = max_capacity;

    if (!(new_elements = realloc(*elements, new_capacity * size)))
        return false;

    *elements = new_elements;
    *capacity = new_capacity;

    return true;
}

static void queue_event(const struct usb_event *event)
{
    if (array_reserve((void **)&usb_events, &usb_events_capacity, usb_event_count + 1, sizeof(*usb_events)))
        usb_events[usb_event_count++] = *event;
    else
        ERR("Failed to queue event.\n");
}

static bool get_event(struct usb_event *event)
{
    if (!usb_event_count) return false;

    *event = usb_events[0];
    if (--usb_event_count)
        memmove(usb_events, usb_events + 1, usb_event_count * sizeof(*usb_events));

    return true;
}

static void add_usb_device(libusb_device *libusb_device)
{
    struct libusb_config_descriptor *config_desc;
    struct libusb_device_descriptor device_desc;
    struct unix_device *unix_device;
    struct usb_event usb_event;
    int ret;

    libusb_get_device_descriptor(libusb_device, &device_desc);

    TRACE("Adding new device %p, vendor %04x, product %04x.\n", libusb_device,
            device_desc.idVendor, device_desc.idProduct);

    if (!(unix_device = calloc(1, sizeof(*unix_device))))
        return;

    if ((ret = libusb_open(libusb_device, &unix_device->handle)))
    {
        WARN("Failed to open device: %s\n", libusb_strerror(ret));
        free(unix_device);
        return;
    }
    unix_device->refcount = 1;

    pthread_mutex_lock(&device_mutex);
    list_add_tail(&device_list, &unix_device->entry);
    pthread_mutex_unlock(&device_mutex);

    usb_event.type = USB_EVENT_ADD_DEVICE;
    usb_event.u.added_device.device = unix_device;
    usb_event.u.added_device.vendor = device_desc.idVendor;
    usb_event.u.added_device.product = device_desc.idProduct;
    usb_event.u.added_device.revision = device_desc.bcdDevice;
    usb_event.u.added_device.usbver = device_desc.bcdUSB;
    usb_event.u.added_device.class = device_desc.bDeviceClass;
    usb_event.u.added_device.subclass = device_desc.bDeviceSubClass;
    usb_event.u.added_device.protocol = device_desc.bDeviceProtocol;
    usb_event.u.added_device.busnum = libusb_get_bus_number(libusb_device);
    usb_event.u.added_device.portnum = libusb_get_port_number(libusb_device);
    usb_event.u.added_device.interface = false;
    usb_event.u.added_device.interface_index = -1;

    if (!(ret = libusb_get_active_config_descriptor(libusb_device, &config_desc)))
    {
        const struct libusb_interface *interface;
        const struct libusb_interface_descriptor *iface_desc;

        if (config_desc->bNumInterfaces == 1)
        {
            interface = &config_desc->interface[0];
            if (interface->num_altsetting != 1)
                WARN("Interface 0 has %u alternate settings; using the first one.\n",
                        interface->num_altsetting);
            iface_desc = &interface->altsetting[0];

            usb_event.u.added_device.class = iface_desc->bInterfaceClass;
            usb_event.u.added_device.subclass = iface_desc->bInterfaceSubClass;
            usb_event.u.added_device.protocol = iface_desc->bInterfaceProtocol;
            usb_event.u.added_device.interface_index = iface_desc->bInterfaceNumber;
        }
        queue_event(&usb_event);

        /* Create new devices for interfaces of composite devices.
         * When Interface Association Descriptors (IAD) are present, create one
         * PDO per function (IAD group), matching usbccgp behaviour. Otherwise
         * create one PDO per interface.
         */
        if (config_desc->bNumInterfaces > 1)
        {
            uint8_t i;
            struct unix_device *unix_iface;
#define MAX_INTERFACES 256
            uint8_t iad_first[MAX_INTERFACES], iad_count[MAX_INTERFACES];
            unsigned int num_iads = 0;
            int used_by_iad[MAX_INTERFACES];

            memset(used_by_iad, 0, sizeof(used_by_iad));

            /* Parse IAD from config descriptor extra (descriptor type 0x0B). */
            if (config_desc->extra && config_desc->extra_length >= 8)
            {
                const unsigned char *p = config_desc->extra;
                int left = config_desc->extra_length;

                while (left >= 2)
                {
                    int len = p[0];
                    if (len < 2 || len > left)
                        break;
                    if (p[1] == LIBUSB_DT_INTERFACE_ASSOCIATION && len >= 8)
                    {
                        if (num_iads < MAX_INTERFACES)
                        {
                            iad_first[num_iads] = p[2]; /* bFirstInterface */
                            iad_count[num_iads] = p[3]; /* bInterfaceCount */
                            if (iad_count[num_iads] > 0)
                            {
                                unsigned int k;
                                for (k = 0; k < iad_count[num_iads] && (iad_first[num_iads] + k) < MAX_INTERFACES; k++)
                                    used_by_iad[iad_first[num_iads] + k] = 1;
                                num_iads++;
                            }
                        }
                    }
                    p += len;
                    left -= len;
                }
            }
#undef MAX_INTERFACES

            if (num_iads > 0)
            {
                /* One PDO per IAD (function). */
                for (i = 0; i < num_iads; i++)
                {
                    uint8_t first = iad_first[i];
                    uint8_t count = iad_count[i];

                    if (first >= config_desc->bNumInterfaces || first + count > config_desc->bNumInterfaces)
                        continue;
                    interface = &config_desc->interface[first];
                    if (interface->num_altsetting != 1)
                        WARN("Interface %u has %u alternate settings; using the first one.\n",
                                first, interface->num_altsetting);
                    iface_desc = &interface->altsetting[0];

                    if (!(unix_iface = calloc(1, sizeof(*unix_iface))))
                        return;

                    ++unix_device->refcount;
                    unix_iface->refcount = 1;
                    unix_iface->handle = unix_device->handle;
                    unix_iface->parent = unix_device;
                    pthread_mutex_lock(&device_mutex);
                    list_add_tail(&device_list, &unix_iface->entry);
                    pthread_mutex_unlock(&device_mutex);

                    usb_event.u.added_device.device = unix_iface;
                    usb_event.u.added_device.class = iface_desc->bInterfaceClass;
                    usb_event.u.added_device.subclass = iface_desc->bInterfaceSubClass;
                    usb_event.u.added_device.protocol = iface_desc->bInterfaceProtocol;
                    usb_event.u.added_device.interface = true;
                    usb_event.u.added_device.interface_index = first;
                    queue_event(&usb_event);
                }
            }

            /* One PDO per interface not covered by any IAD. */
            for (i = 0; i < config_desc->bNumInterfaces; i++)
            {
                if (used_by_iad[i])
                    continue;

                interface = &config_desc->interface[i];
                if (interface->num_altsetting != 1)
                    WARN("Interface %u has %u alternate settings; using the first one.\n",
                            i, interface->num_altsetting);
                iface_desc = &interface->altsetting[0];

                if (!(unix_iface = calloc(1, sizeof(*unix_iface))))
                    return;

                ++unix_device->refcount;
                unix_iface->refcount = 1;
                unix_iface->handle = unix_device->handle;
                unix_iface->parent = unix_device;
                pthread_mutex_lock(&device_mutex);
                list_add_tail(&device_list, &unix_iface->entry);
                pthread_mutex_unlock(&device_mutex);

                usb_event.u.added_device.device = unix_iface;
                usb_event.u.added_device.class = iface_desc->bInterfaceClass;
                usb_event.u.added_device.subclass = iface_desc->bInterfaceSubClass;
                usb_event.u.added_device.protocol = iface_desc->bInterfaceProtocol;
                usb_event.u.added_device.interface = true;
                usb_event.u.added_device.interface_index = iface_desc->bInterfaceNumber;
                queue_event(&usb_event);
            }
        }
        libusb_free_config_descriptor(config_desc);
    }
    else
    {
        queue_event(&usb_event);

        ERR("Failed to get configuration descriptor: %s\n", libusb_strerror(ret));
    }
}

static void remove_usb_device(libusb_device *libusb_device)
{
    struct unix_device *unix_device;
    struct usb_event usb_event;

    TRACE("Removing device %p.\n", libusb_device);

    LIST_FOR_EACH_ENTRY(unix_device, &device_list, struct unix_device, entry)
    {
        if (libusb_get_device(unix_device->handle) == libusb_device)
        {
            usb_event.type = USB_EVENT_REMOVE_DEVICE;
            usb_event.u.removed_device = unix_device;
            queue_event(&usb_event);
        }
    }
}

static int LIBUSB_CALL hotplug_cb(libusb_context *context, libusb_device *device,
        libusb_hotplug_event event, void *user_data)
{
    if (event == LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED)
        add_usb_device(device);
    else
        remove_usb_device(device);

    return 0;
}

static NTSTATUS usb_main_loop(void *args)
{
    const struct usb_main_loop_params *params = args;
    int ret;

    while (!thread_shutdown)
    {
        if (get_event(params->event)) return STATUS_PENDING;

        if ((ret = libusb_handle_events(NULL)))
            ERR("Error handling events: %s\n", libusb_strerror(ret));
    }

    libusb_exit(NULL);
    free(usb_events);
    usb_events = NULL;
    usb_event_count = usb_events_capacity = 0;
    thread_shutdown = false;

    TRACE("USB main loop exiting.\n");
    return STATUS_SUCCESS;
}

static NTSTATUS usb_init(void *args)
{
    int ret;

    if ((ret = libusb_init(NULL)))
    {
        ERR("Failed to initialize libusb: %s\n", libusb_strerror(ret));
        return STATUS_UNSUCCESSFUL;
    }

    if ((ret = libusb_hotplug_register_callback(NULL,
            LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED | LIBUSB_HOTPLUG_EVENT_DEVICE_LEFT,
            LIBUSB_HOTPLUG_ENUMERATE, LIBUSB_HOTPLUG_MATCH_ANY, LIBUSB_HOTPLUG_MATCH_ANY,
            LIBUSB_HOTPLUG_MATCH_ANY, hotplug_cb, NULL, &hotplug_cb_handle)))
    {
        ERR("Failed to register callback: %s\n", libusb_strerror(ret));
        libusb_exit(NULL);
        return STATUS_UNSUCCESSFUL;
    }

    return STATUS_SUCCESS;
}

static NTSTATUS usb_exit(void *args)
{
    libusb_hotplug_deregister_callback(NULL, hotplug_cb_handle);
    thread_shutdown = true;
    libusb_interrupt_event_handler(NULL);

    return STATUS_SUCCESS;
}

static NTSTATUS usbd_status_from_libusb(enum libusb_transfer_status status)
{
    switch (status)
    {
        case LIBUSB_TRANSFER_CANCELLED:
            return USBD_STATUS_CANCELED;
        case LIBUSB_TRANSFER_COMPLETED:
            return USBD_STATUS_SUCCESS;
        case LIBUSB_TRANSFER_NO_DEVICE:
            return USBD_STATUS_DEVICE_GONE;
        case LIBUSB_TRANSFER_STALL:
            return USBD_STATUS_ENDPOINT_HALTED;
        case LIBUSB_TRANSFER_TIMED_OUT:
            return USBD_STATUS_TIMEOUT;
        case LIBUSB_TRANSFER_OVERFLOW:
            return USBD_STATUS_DATA_OVERRUN;
        default:
            TRACE("Unknown transfer status %#x, mapping to REQUEST_FAILED.\n", status);
            /* fall through */
        case LIBUSB_TRANSFER_ERROR:
            return USBD_STATUS_REQUEST_FAILED;
    }
}

struct transfer_ctx
{
    IRP *irp;
    void *transfer_buffer;
};

static void LIBUSB_CALL transfer_cb(struct libusb_transfer *transfer)
{
    struct transfer_ctx *transfer_ctx = transfer->user_data;
    IRP *irp = transfer_ctx->irp;
    URB *urb = IoGetCurrentIrpStackLocation(irp)->Parameters.Others.Argument1;
    unsigned char *transfer_buffer = transfer_ctx->transfer_buffer;
    struct usb_event event;

    TRACE("Completing IRP %p, status %#x.\n", irp, transfer->status);

    free(transfer_ctx);
    urb->UrbHeader.Status = usbd_status_from_libusb(transfer->status);

    if (transfer->status == LIBUSB_TRANSFER_COMPLETED)
    {
        switch (urb->UrbHeader.Function)
        {
            case URB_FUNCTION_BULK_OR_INTERRUPT_TRANSFER:
                urb->UrbBulkOrInterruptTransfer.TransferBufferLength = transfer->actual_length;
                break;

            case URB_FUNCTION_GET_DESCRIPTOR_FROM_DEVICE:
            case URB_FUNCTION_GET_DESCRIPTOR_FROM_INTERFACE:
            {
                struct _URB_CONTROL_DESCRIPTOR_REQUEST *req = &urb->UrbControlDescriptorRequest;
                req->TransferBufferLength = transfer->actual_length;
                memcpy(transfer_buffer, libusb_control_transfer_get_data(transfer), transfer->actual_length);
                break;
            }

            case URB_FUNCTION_GET_CONFIGURATION:
            {
                struct _URB_CONTROL_GET_CONFIGURATION_REQUEST *req = &urb->UrbControlGetConfigurationRequest;
                req->TransferBufferLength = transfer->actual_length;
                if (transfer->actual_length)
                    memcpy(transfer_buffer, libusb_control_transfer_get_data(transfer), transfer->actual_length);
                break;
            }

            case URB_FUNCTION_GET_INTERFACE:
            {
                struct _URB_CONTROL_GET_INTERFACE_REQUEST *req = &urb->UrbControlGetInterfaceRequest;
                req->TransferBufferLength = transfer->actual_length;
                if (transfer->actual_length)
                    memcpy(transfer_buffer, libusb_control_transfer_get_data(transfer), transfer->actual_length);
                break;
            }

            case URB_FUNCTION_SET_FEATURE_TO_DEVICE:
            case URB_FUNCTION_SET_FEATURE_TO_INTERFACE:
            case URB_FUNCTION_SET_FEATURE_TO_ENDPOINT:
            case URB_FUNCTION_CLEAR_FEATURE_TO_DEVICE:
            case URB_FUNCTION_CLEAR_FEATURE_TO_INTERFACE:
            case URB_FUNCTION_CLEAR_FEATURE_TO_ENDPOINT:
                /* No data to copy */
                break;

            case URB_FUNCTION_GET_STATUS_FROM_DEVICE:
            case URB_FUNCTION_GET_STATUS_FROM_INTERFACE:
            case URB_FUNCTION_GET_STATUS_FROM_ENDPOINT:
            case URB_FUNCTION_GET_STATUS_FROM_OTHER:
            {
                struct _URB_CONTROL_GET_STATUS_REQUEST *req = &urb->UrbControlGetStatusRequest;
                req->TransferBufferLength = transfer->actual_length;
                if (transfer->actual_length && transfer_buffer)
                    memcpy(transfer_buffer, libusb_control_transfer_get_data(transfer), transfer->actual_length);
                break;
            }

            case URB_FUNCTION_CONTROL_TRANSFER:
            {
                struct _URB_CONTROL_TRANSFER *req = &urb->UrbControlTransfer;
                req->TransferBufferLength = transfer->actual_length;
                if (req->TransferFlags & USBD_TRANSFER_DIRECTION_IN)
                    memcpy(transfer_buffer, libusb_control_transfer_get_data(transfer), transfer->actual_length);
                break;
            }

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
                req->TransferBufferLength = transfer->actual_length;
                if (req->TransferFlags & USBD_TRANSFER_DIRECTION_IN)
                    memcpy(transfer_buffer, libusb_control_transfer_get_data(transfer), transfer->actual_length);
                break;
            }

            case URB_FUNCTION_ISOCH_TRANSFER:
                /* Per-packet status and ErrorCount filled below for all outcomes */
                break;

            default:
                ERR("Unexpected function %#x.\n", urb->UrbHeader.Function);
        }
    }

    if (urb->UrbHeader.Function == URB_FUNCTION_ISOCH_TRANSFER && transfer->type == LIBUSB_TRANSFER_TYPE_ISOCHRONOUS)
    {
        struct _URB_ISOCH_TRANSFER *req = &urb->UrbIsochronousTransfer;
        ULONG i, n = req->NumberOfPackets;

        req->ErrorCount = 0;
        for (i = 0; i < n && i < transfer->num_iso_packets; i++)
        {
            req->IsoPacket[i].Status = usbd_status_from_libusb(transfer->iso_packet_desc[i].status);
            req->IsoPacket[i].Length = transfer->iso_packet_desc[i].actual_length;
            if (req->IsoPacket[i].Status != USBD_STATUS_SUCCESS)
                req->ErrorCount++;
        }
    }

    event.type = USB_EVENT_TRANSFER_COMPLETE;
    event.u.completed_irp = irp;
    queue_event(&event);
}

struct pipe
{
    unsigned char endpoint;
    unsigned char type;
};

static HANDLE make_pipe_handle(unsigned char endpoint, USBD_PIPE_TYPE type)
{
    union
    {
        struct pipe pipe;
        HANDLE handle;
    } u;

    u.pipe.endpoint = endpoint;
    u.pipe.type = type;
    return u.handle;
}

static struct pipe get_pipe(HANDLE handle)
{
    union
    {
        struct pipe pipe;
        HANDLE handle;
    } u;

    u.handle = handle;
    return u.pipe;
}

static NTSTATUS usb_submit_urb(void *args)
{
    const struct usb_submit_urb_params *params = args;
    IRP *irp = params->irp;

    URB *urb = IoGetCurrentIrpStackLocation(irp)->Parameters.Others.Argument1;
    libusb_device_handle *handle = params->device->handle;
    struct libusb_transfer *transfer;
    int ret;

    TRACE("type %#x.\n", urb->UrbHeader.Function);

    switch (urb->UrbHeader.Function)
    {
        case URB_FUNCTION_SYNC_RESET_PIPE:
        case URB_FUNCTION_SYNC_CLEAR_STALL:
        case URB_FUNCTION_SYNC_RESET_PIPE_AND_CLEAR_STALL:
        {
            struct _URB_PIPE_REQUEST *req = &urb->UrbPipeRequest;
            struct pipe pipe = get_pipe(req->PipeHandle);

            if ((ret = libusb_clear_halt(handle, pipe.endpoint)) < 0)
                ERR("Failed to clear halt: %s\n", libusb_strerror(ret));

            return STATUS_SUCCESS;
        }

        case URB_FUNCTION_ISOCH_TRANSFER:
        {
            struct _URB_ISOCH_TRANSFER *req = &urb->UrbIsochronousTransfer;
            struct pipe pipe = get_pipe(req->PipeHandle);
            struct transfer_ctx *transfer_ctx;
            ULONG i, n = req->NumberOfPackets;

            if (n == 0 || !params->transfer_buffer)
                return STATUS_INVALID_PARAMETER;
            if (pipe.type != UsbdPipeTypeIsochronous)
            {
                WARN("Pipe type %#x is not isochronous.\n", pipe.type);
                return USBD_STATUS_INVALID_PIPE_HANDLE;
            }

            if (!(transfer_ctx = calloc(1, sizeof(*transfer_ctx))))
                return STATUS_NO_MEMORY;
            transfer_ctx->irp = irp;
            transfer_ctx->transfer_buffer = params->transfer_buffer;

            if (!(transfer = libusb_alloc_transfer(n)))
            {
                free(transfer_ctx);
                return STATUS_NO_MEMORY;
            }
            irp->Tail.Overlay.DriverContext[0] = transfer;

            libusb_fill_iso_transfer(transfer, handle, pipe.endpoint,
                    params->transfer_buffer, req->TransferBufferLength, n, transfer_cb, transfer_ctx, 0);
            for (i = 0; i < n; i++)
                transfer->iso_packet_desc[i].length = req->IsoPacket[i].Length;

            transfer->flags = LIBUSB_TRANSFER_FREE_TRANSFER;
            ret = libusb_submit_transfer(transfer);
            if (ret < 0)
            {
                ERR("Failed to submit isoch transfer: %s\n", libusb_strerror(ret));
                free(transfer_ctx);
                libusb_free_transfer(transfer);
                return STATUS_UNSUCCESSFUL;
            }
            return STATUS_PENDING;
        }

        case URB_FUNCTION_BULK_OR_INTERRUPT_TRANSFER:
        {
            struct _URB_BULK_OR_INTERRUPT_TRANSFER *req = &urb->UrbBulkOrInterruptTransfer;
            struct pipe pipe = get_pipe(req->PipeHandle);
            struct transfer_ctx *transfer_ctx;

            if (!(transfer_ctx = calloc(1, sizeof(*transfer_ctx))))
                return STATUS_NO_MEMORY;
            transfer_ctx->irp = irp;
            transfer_ctx->transfer_buffer = params->transfer_buffer;

            if (!(transfer = libusb_alloc_transfer(0)))
            {
                free(transfer_ctx);
                return STATUS_NO_MEMORY;
            }
            irp->Tail.Overlay.DriverContext[0] = transfer;

            if (pipe.type == UsbdPipeTypeBulk)
            {
                libusb_fill_bulk_transfer(transfer, handle, pipe.endpoint,
                        params->transfer_buffer, req->TransferBufferLength, transfer_cb, transfer_ctx, 0);
            }
            else if (pipe.type == UsbdPipeTypeInterrupt)
            {
                libusb_fill_interrupt_transfer(transfer, handle, pipe.endpoint,
                        params->transfer_buffer, req->TransferBufferLength, transfer_cb, transfer_ctx, 0);
            }
            else
            {
                WARN("Invalid pipe type %#x.\n", pipe.type);
                free(transfer_ctx);
                libusb_free_transfer(transfer);
                return USBD_STATUS_INVALID_PIPE_HANDLE;
            }

            transfer->flags = LIBUSB_TRANSFER_FREE_TRANSFER;
            ret = libusb_submit_transfer(transfer);
            if (ret < 0)
                ERR("Failed to submit bulk transfer: %s\n", libusb_strerror(ret));

            return STATUS_PENDING;
        }

        case URB_FUNCTION_CONTROL_TRANSFER:
        {
            struct _URB_CONTROL_TRANSFER *req = &urb->UrbControlTransfer;
            struct transfer_ctx *transfer_ctx;
            unsigned char *buffer;
            UCHAR *setup = req->SetupPacket;

            if (!(transfer_ctx = calloc(1, sizeof(*transfer_ctx))))
                return STATUS_NO_MEMORY;
            transfer_ctx->irp = irp;
            transfer_ctx->transfer_buffer = params->transfer_buffer;

            if (!(transfer = libusb_alloc_transfer(0)))
            {
                free(transfer_ctx);
                return STATUS_NO_MEMORY;
            }
            irp->Tail.Overlay.DriverContext[0] = transfer;

            if (!(buffer = malloc(sizeof(struct libusb_control_setup) + req->TransferBufferLength)))
            {
                free(transfer_ctx);
                libusb_free_transfer(transfer);
                return STATUS_NO_MEMORY;
            }

            libusb_fill_control_setup(buffer, setup[0], setup[1],
                    (setup[3] << 8) | setup[2], (setup[5] << 8) | setup[4],
                    (setup[7] << 8) | setup[6]);
            if (!(setup[0] & 0x80) && req->TransferBufferLength)
                memcpy(buffer + sizeof(struct libusb_control_setup), params->transfer_buffer, req->TransferBufferLength);
            libusb_fill_control_transfer(transfer, handle, buffer, transfer_cb, transfer_ctx, 0);
            transfer->flags = LIBUSB_TRANSFER_FREE_BUFFER | LIBUSB_TRANSFER_FREE_TRANSFER;
            ret = libusb_submit_transfer(transfer);
            if (ret < 0)
            {
                ERR("Failed to submit CONTROL_TRANSFER: %s\n", libusb_strerror(ret));
                free(transfer_ctx);
                libusb_free_transfer(transfer);
                return STATUS_UNSUCCESSFUL;
            }
            return STATUS_PENDING;
        }

        case URB_FUNCTION_GET_DESCRIPTOR_FROM_DEVICE:
        {
            struct _URB_CONTROL_DESCRIPTOR_REQUEST *req = &urb->UrbControlDescriptorRequest;
            struct transfer_ctx *transfer_ctx;
            unsigned char *buffer;

            if (!(transfer_ctx = calloc(1, sizeof(*transfer_ctx))))
                return STATUS_NO_MEMORY;
            transfer_ctx->irp = irp;
            transfer_ctx->transfer_buffer = params->transfer_buffer;

            if (!(transfer = libusb_alloc_transfer(0)))
            {
                free(transfer_ctx);
                return STATUS_NO_MEMORY;
            }
            irp->Tail.Overlay.DriverContext[0] = transfer;

            if (!(buffer = malloc(sizeof(struct libusb_control_setup) + req->TransferBufferLength)))
            {
                free(transfer_ctx);
                libusb_free_transfer(transfer);
                return STATUS_NO_MEMORY;
            }

            libusb_fill_control_setup(buffer,
                    LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_STANDARD | LIBUSB_RECIPIENT_DEVICE,
                    LIBUSB_REQUEST_GET_DESCRIPTOR, (req->DescriptorType << 8) | req->Index,
                    req->LanguageId, req->TransferBufferLength);
            libusb_fill_control_transfer(transfer, handle, buffer, transfer_cb, transfer_ctx, 0);
            transfer->flags = LIBUSB_TRANSFER_FREE_BUFFER | LIBUSB_TRANSFER_FREE_TRANSFER;
            ret = libusb_submit_transfer(transfer);
            if (ret < 0)
                ERR("Failed to submit GET_DESCRIPTOR transfer: %s\n", libusb_strerror(ret));

            return STATUS_PENDING;
        }

        case URB_FUNCTION_GET_DESCRIPTOR_FROM_INTERFACE:
        {
            struct _URB_CONTROL_DESCRIPTOR_REQUEST *req = &urb->UrbControlDescriptorRequest;
            struct transfer_ctx *transfer_ctx;
            unsigned char *buffer;

            if (!(transfer_ctx = calloc(1, sizeof(*transfer_ctx))))
                return STATUS_NO_MEMORY;
            transfer_ctx->irp = irp;
            transfer_ctx->transfer_buffer = params->transfer_buffer;

            if (!(transfer = libusb_alloc_transfer(0)))
            {
                free(transfer_ctx);
                return STATUS_NO_MEMORY;
            }
            irp->Tail.Overlay.DriverContext[0] = transfer;

            if (!(buffer = malloc(sizeof(struct libusb_control_setup) + req->TransferBufferLength)))
            {
                free(transfer_ctx);
                libusb_free_transfer(transfer);
                return STATUS_NO_MEMORY;
            }

            /* wValue = (DescriptorType<<8)|DescriptorIndex, wIndex = InterfaceNumber */
            libusb_fill_control_setup(buffer,
                    LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_STANDARD | LIBUSB_RECIPIENT_INTERFACE,
                    LIBUSB_REQUEST_GET_DESCRIPTOR, (req->DescriptorType << 8) | req->Index,
                    req->LanguageId, req->TransferBufferLength);
            libusb_fill_control_transfer(transfer, handle, buffer, transfer_cb, transfer_ctx, 0);
            transfer->flags = LIBUSB_TRANSFER_FREE_BUFFER | LIBUSB_TRANSFER_FREE_TRANSFER;
            ret = libusb_submit_transfer(transfer);
            if (ret < 0)
            {
                ERR("Failed to submit GET_DESCRIPTOR_FROM_INTERFACE: %s\n", libusb_strerror(ret));
                free(transfer_ctx);
                libusb_free_transfer(transfer);
                return STATUS_UNSUCCESSFUL;
            }
            return STATUS_PENDING;
        }

        case URB_FUNCTION_GET_CONFIGURATION:
        {
            struct transfer_ctx *transfer_ctx;
            unsigned char *buffer;

            if (!(transfer_ctx = calloc(1, sizeof(*transfer_ctx))))
                return STATUS_NO_MEMORY;
            transfer_ctx->irp = irp;
            transfer_ctx->transfer_buffer = params->transfer_buffer;

            if (!(transfer = libusb_alloc_transfer(0)))
            {
                free(transfer_ctx);
                return STATUS_NO_MEMORY;
            }
            irp->Tail.Overlay.DriverContext[0] = transfer;

            if (!(buffer = malloc(sizeof(struct libusb_control_setup) + 1)))
            {
                free(transfer_ctx);
                libusb_free_transfer(transfer);
                return STATUS_NO_MEMORY;
            }

            libusb_fill_control_setup(buffer,
                    LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_STANDARD | LIBUSB_RECIPIENT_DEVICE,
                    0x08, 0, 0, 1); /* GET_CONFIGURATION */
            libusb_fill_control_transfer(transfer, handle, buffer, transfer_cb, transfer_ctx, 0);
            transfer->flags = LIBUSB_TRANSFER_FREE_BUFFER | LIBUSB_TRANSFER_FREE_TRANSFER;
            ret = libusb_submit_transfer(transfer);
            if (ret < 0)
            {
                ERR("Failed to submit GET_CONFIGURATION: %s\n", libusb_strerror(ret));
                free(transfer_ctx);
                libusb_free_transfer(transfer);
                return STATUS_UNSUCCESSFUL;
            }
            return STATUS_PENDING;
        }

        case URB_FUNCTION_GET_INTERFACE:
        {
            struct _URB_CONTROL_GET_INTERFACE_REQUEST *req = &urb->UrbControlGetInterfaceRequest;
            struct transfer_ctx *transfer_ctx;
            unsigned char *buffer;

            if (!(transfer_ctx = calloc(1, sizeof(*transfer_ctx))))
                return STATUS_NO_MEMORY;
            transfer_ctx->irp = irp;
            transfer_ctx->transfer_buffer = params->transfer_buffer;

            if (!(transfer = libusb_alloc_transfer(0)))
            {
                free(transfer_ctx);
                return STATUS_NO_MEMORY;
            }
            irp->Tail.Overlay.DriverContext[0] = transfer;

            if (!(buffer = malloc(sizeof(struct libusb_control_setup) + 1)))
            {
                free(transfer_ctx);
                libusb_free_transfer(transfer);
                return STATUS_NO_MEMORY;
            }

            libusb_fill_control_setup(buffer,
                    LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_STANDARD | LIBUSB_RECIPIENT_INTERFACE,
                    0x0a, 0, req->Interface, 1); /* GET_INTERFACE */
            libusb_fill_control_transfer(transfer, handle, buffer, transfer_cb, transfer_ctx, 0);
            transfer->flags = LIBUSB_TRANSFER_FREE_BUFFER | LIBUSB_TRANSFER_FREE_TRANSFER;
            ret = libusb_submit_transfer(transfer);
            if (ret < 0)
            {
                ERR("Failed to submit GET_INTERFACE: %s\n", libusb_strerror(ret));
                free(transfer_ctx);
                libusb_free_transfer(transfer);
                return STATUS_UNSUCCESSFUL;
            }
            return STATUS_PENDING;
        }

        case URB_FUNCTION_SET_FEATURE_TO_DEVICE:
        case URB_FUNCTION_SET_FEATURE_TO_INTERFACE:
        case URB_FUNCTION_SET_FEATURE_TO_ENDPOINT:
        case URB_FUNCTION_CLEAR_FEATURE_TO_DEVICE:
        case URB_FUNCTION_CLEAR_FEATURE_TO_INTERFACE:
        case URB_FUNCTION_CLEAR_FEATURE_TO_ENDPOINT:
        {
            struct _URB_CONTROL_FEATURE_REQUEST *req = &urb->UrbControlFeatureRequest;
            struct transfer_ctx *transfer_ctx;
            unsigned char *buffer;
            uint8_t req_type = LIBUSB_REQUEST_TYPE_STANDARD;
            uint8_t b_request;

            if (urb->UrbHeader.Function == URB_FUNCTION_SET_FEATURE_TO_DEVICE ||
                urb->UrbHeader.Function == URB_FUNCTION_SET_FEATURE_TO_INTERFACE ||
                urb->UrbHeader.Function == URB_FUNCTION_SET_FEATURE_TO_ENDPOINT)
                b_request = 0x03; /* SET_FEATURE */
            else
                b_request = 0x01; /* CLEAR_FEATURE */

            if (urb->UrbHeader.Function == URB_FUNCTION_SET_FEATURE_TO_DEVICE ||
                urb->UrbHeader.Function == URB_FUNCTION_CLEAR_FEATURE_TO_DEVICE)
                req_type |= LIBUSB_RECIPIENT_DEVICE;
            else if (urb->UrbHeader.Function == URB_FUNCTION_SET_FEATURE_TO_INTERFACE ||
                     urb->UrbHeader.Function == URB_FUNCTION_CLEAR_FEATURE_TO_INTERFACE)
                req_type |= LIBUSB_RECIPIENT_INTERFACE;
            else
                req_type |= LIBUSB_RECIPIENT_ENDPOINT;

            if (!(transfer_ctx = calloc(1, sizeof(*transfer_ctx))))
                return STATUS_NO_MEMORY;
            transfer_ctx->irp = irp;
            transfer_ctx->transfer_buffer = NULL;

            if (!(transfer = libusb_alloc_transfer(0)))
            {
                free(transfer_ctx);
                return STATUS_NO_MEMORY;
            }
            irp->Tail.Overlay.DriverContext[0] = transfer;

            if (!(buffer = malloc(sizeof(struct libusb_control_setup))))
            {
                free(transfer_ctx);
                libusb_free_transfer(transfer);
                return STATUS_NO_MEMORY;
            }

            libusb_fill_control_setup(buffer, req_type, b_request,
                    req->FeatureSelector, req->Index, 0);
            libusb_fill_control_transfer(transfer, handle, buffer, transfer_cb, transfer_ctx, 0);
            transfer->flags = LIBUSB_TRANSFER_FREE_BUFFER | LIBUSB_TRANSFER_FREE_TRANSFER;
            ret = libusb_submit_transfer(transfer);
            if (ret < 0)
            {
                ERR("Failed to submit feature request: %s\n", libusb_strerror(ret));
                free(transfer_ctx);
                libusb_free_transfer(transfer);
                return STATUS_UNSUCCESSFUL;
            }
            return STATUS_PENDING;
        }

        case URB_FUNCTION_GET_STATUS_FROM_DEVICE:
        case URB_FUNCTION_GET_STATUS_FROM_INTERFACE:
        case URB_FUNCTION_GET_STATUS_FROM_ENDPOINT:
        case URB_FUNCTION_GET_STATUS_FROM_OTHER:
        {
            struct _URB_CONTROL_GET_STATUS_REQUEST *req = &urb->UrbControlGetStatusRequest;
            struct transfer_ctx *transfer_ctx;
            unsigned char *buffer;
            uint8_t req_type = LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_STANDARD;

            if (!(transfer_ctx = calloc(1, sizeof(*transfer_ctx))))
                return STATUS_NO_MEMORY;
            transfer_ctx->irp = irp;
            transfer_ctx->transfer_buffer = params->transfer_buffer;

            if (!(transfer = libusb_alloc_transfer(0)))
            {
                free(transfer_ctx);
                return STATUS_NO_MEMORY;
            }
            irp->Tail.Overlay.DriverContext[0] = transfer;

            if (!(buffer = malloc(sizeof(struct libusb_control_setup) + 2)))
            {
                free(transfer_ctx);
                libusb_free_transfer(transfer);
                return STATUS_NO_MEMORY;
            }

            if (urb->UrbHeader.Function == URB_FUNCTION_GET_STATUS_FROM_DEVICE)
                req_type |= LIBUSB_RECIPIENT_DEVICE;
            else if (urb->UrbHeader.Function == URB_FUNCTION_GET_STATUS_FROM_INTERFACE)
                req_type |= LIBUSB_RECIPIENT_INTERFACE;
            else if (urb->UrbHeader.Function == URB_FUNCTION_GET_STATUS_FROM_ENDPOINT)
                req_type |= LIBUSB_RECIPIENT_ENDPOINT;
            else
                req_type |= LIBUSB_RECIPIENT_OTHER;

            libusb_fill_control_setup(buffer, req_type, 0x00, 0, req->Index, 2); /* GET_STATUS */
            libusb_fill_control_transfer(transfer, handle, buffer, transfer_cb, transfer_ctx, 0);
            transfer->flags = LIBUSB_TRANSFER_FREE_BUFFER | LIBUSB_TRANSFER_FREE_TRANSFER;
            ret = libusb_submit_transfer(transfer);
            if (ret < 0)
            {
                ERR("Failed to submit GET_STATUS: %s\n", libusb_strerror(ret));
                free(transfer_ctx);
                libusb_free_transfer(transfer);
                return STATUS_UNSUCCESSFUL;
            }
            return STATUS_PENDING;
        }

        case URB_FUNCTION_GET_CURRENT_FRAME_NUMBER:
        {
            struct _URB_GET_CURRENT_FRAME_NUMBER *req = &urb->UrbGetCurrentFrameNumber;
            struct timespec ts;

            clock_gettime(CLOCK_MONOTONIC, &ts);
            /* USB 1.1 frame = 1ms; use milliseconds as frame number (libusb has no real frame number). */
            req->FrameNumber = (ULONG)((ts.tv_sec * 1000UL) + (ts.tv_nsec / 1000000));
            return STATUS_SUCCESS;
        }

        case URB_FUNCTION_GET_FRAME_LENGTH:
        {
            struct _URB_GET_FRAME_LENGTH *req = &urb->UrbGetFrameLength;
            libusb_device *dev = libusb_get_device(handle);
            int speed = libusb_get_device_speed(dev);
            struct timespec ts;

            switch (speed)
            {
                case LIBUSB_SPEED_LOW:   req->FrameLength = 64; break;   /* low speed max packet */
                case LIBUSB_SPEED_FULL: req->FrameLength = 1500; break; /* full speed bytes per frame */
                case LIBUSB_SPEED_HIGH:  req->FrameLength = 3072; break; /* high speed per microframe */
                case LIBUSB_SPEED_SUPER: req->FrameLength = 12288; break; /* super speed */
                default:                 req->FrameLength = 1500; break;
            }
            clock_gettime(CLOCK_MONOTONIC, &ts);
            req->FrameNumber = (ULONG)((ts.tv_sec * 1000UL) + (ts.tv_nsec / 1000000));
            return STATUS_SUCCESS;
        }

        case URB_FUNCTION_SET_FRAME_LENGTH:
            /* libusb does not support changing frame length; no-op for compatibility. */
            return STATUS_SUCCESS;

        case URB_FUNCTION_TAKE_FRAME_LENGTH_CONTROL:
        case URB_FUNCTION_RELEASE_FRAME_LENGTH_CONTROL:
            /* libusb has no host scheduler; no-op for compatibility. */
            return STATUS_SUCCESS;

        case URB_FUNCTION_SELECT_INTERFACE:
        {
            struct _URB_SELECT_INTERFACE *req = &urb->UrbSelectInterface;
            ULONG i;

            ret = libusb_set_interface_alt_setting(handle, req->Interface.InterfaceNumber, req->Interface.AlternateSetting);
            if (ret < 0)
            {
                ERR("Failed to set interface %u alt setting %u: %s\n",
                    req->Interface.InterfaceNumber, req->Interface.AlternateSetting, libusb_strerror(ret));
                return STATUS_UNSUCCESSFUL;
            }
            for (i = 0; i < req->Interface.NumberOfPipes; ++i)
            {
                USBD_PIPE_INFORMATION *pipe = &req->Interface.Pipes[i];
                pipe->PipeHandle = make_pipe_handle(pipe->EndpointAddress, pipe->PipeType);
            }
            return STATUS_SUCCESS;
        }

        case URB_FUNCTION_SELECT_CONFIGURATION:
        {
            struct _URB_SELECT_CONFIGURATION *req = &urb->UrbSelectConfiguration;
            ULONG i;

            /* Prefer to avoid sending SET_CONFIGURATION redundantly.
             * Some devices (e.g. CASIO FX-9750GII) misbehave if they receive it
             * when the requested configuration is already active. */
            if (req->ConfigurationDescriptor && !params->device->parent)
            {
                int current_cfg, new_cfg = req->ConfigurationDescriptor->bConfigurationValue;

                ret = libusb_get_configuration(handle, &current_cfg);
                if (ret < 0)
                {
                    WARN("Failed to get current configuration: %s\n", libusb_strerror(ret));
                }
                else if (current_cfg != new_cfg)
                {
                    TRACE("Setting configuration from %d to %d.\n", current_cfg, new_cfg);
                    ret = libusb_set_configuration(handle, new_cfg);
                    if (ret < 0)
                    {
                        ERR("Failed to set configuration %d: %s\n", new_cfg, libusb_strerror(ret));
                        return STATUS_UNSUCCESSFUL;
                    }
                }
            }

            for (i = 0; i < req->Interface.NumberOfPipes; ++i)
            {
                USBD_PIPE_INFORMATION *pipe = &req->Interface.Pipes[i];
                pipe->PipeHandle = make_pipe_handle(pipe->EndpointAddress, pipe->PipeType);
            }

            return STATUS_SUCCESS;
        }

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
            uint8_t req_type;
            struct transfer_ctx *transfer_ctx;
            unsigned char *buffer;

            if (urb->UrbHeader.Function == URB_FUNCTION_CLASS_DEVICE ||
                urb->UrbHeader.Function == URB_FUNCTION_CLASS_INTERFACE ||
                urb->UrbHeader.Function == URB_FUNCTION_CLASS_ENDPOINT ||
                urb->UrbHeader.Function == URB_FUNCTION_CLASS_OTHER)
                req_type = LIBUSB_REQUEST_TYPE_CLASS;
            else
                req_type = LIBUSB_REQUEST_TYPE_VENDOR;

            if (urb->UrbHeader.Function == URB_FUNCTION_VENDOR_DEVICE ||
                urb->UrbHeader.Function == URB_FUNCTION_CLASS_DEVICE)
                req_type |= LIBUSB_RECIPIENT_DEVICE;
            else if (urb->UrbHeader.Function == URB_FUNCTION_VENDOR_INTERFACE ||
                     urb->UrbHeader.Function == URB_FUNCTION_CLASS_INTERFACE)
                req_type |= LIBUSB_RECIPIENT_INTERFACE;
            else if (urb->UrbHeader.Function == URB_FUNCTION_VENDOR_ENDPOINT ||
                     urb->UrbHeader.Function == URB_FUNCTION_CLASS_ENDPOINT)
                req_type |= LIBUSB_RECIPIENT_ENDPOINT;
            else
                req_type |= LIBUSB_RECIPIENT_OTHER;

            if (!(transfer_ctx = calloc(1, sizeof(*transfer_ctx))))
                return STATUS_NO_MEMORY;
            transfer_ctx->irp = irp;
            transfer_ctx->transfer_buffer = params->transfer_buffer;

            if (req->TransferFlags & USBD_TRANSFER_DIRECTION_IN)
                req_type |= LIBUSB_ENDPOINT_IN;
            if (req->TransferFlags & ~USBD_TRANSFER_DIRECTION_IN)
                TRACE("Other transfer flags %#x (using direction only).\n", (int)req->TransferFlags);

            if (!(transfer = libusb_alloc_transfer(0)))
            {
                free(transfer_ctx);
                return STATUS_NO_MEMORY;
            }
            irp->Tail.Overlay.DriverContext[0] = transfer;

            if (!(buffer = malloc(sizeof(struct libusb_control_setup) + req->TransferBufferLength)))
            {
                free(transfer_ctx);
                libusb_free_transfer(transfer);
                return STATUS_NO_MEMORY;
            }

            libusb_fill_control_setup(buffer, req_type, req->Request,
                    req->Value, req->Index, req->TransferBufferLength);
            if (!(req->TransferFlags & USBD_TRANSFER_DIRECTION_IN))
                memcpy(buffer + LIBUSB_CONTROL_SETUP_SIZE, params->transfer_buffer, req->TransferBufferLength);
            libusb_fill_control_transfer(transfer, handle, buffer, transfer_cb, transfer_ctx, 0);
            transfer->flags = LIBUSB_TRANSFER_FREE_BUFFER | LIBUSB_TRANSFER_FREE_TRANSFER;
            ret = libusb_submit_transfer(transfer);
            if (ret < 0)
                ERR("Failed to submit vendor-specific interface transfer: %s\n", libusb_strerror(ret));

            return STATUS_PENDING;
        }

        default:
            TRACE("Unhandled URB function %#x.\n", urb->UrbHeader.Function);
            return STATUS_NOT_IMPLEMENTED;
    }

    return STATUS_NOT_IMPLEMENTED;
}

static NTSTATUS usb_cancel_transfer(void *args)
{
    const struct usb_cancel_transfer_params *params = args;
    int ret;

    if ((ret = libusb_cancel_transfer(params->transfer)) < 0)
        ERR("Failed to cancel transfer: %s\n", libusb_strerror(ret));

    return STATUS_SUCCESS;
}

static void decref_device(struct unix_device *device)
{
    pthread_mutex_lock(&device_mutex);

    if (--device->refcount)
    {
        pthread_mutex_unlock(&device_mutex);
        return;
    }

    list_remove(&device->entry);

    pthread_mutex_unlock(&device_mutex);

    if (device->parent)
        decref_device(device->parent);
    else
        libusb_close(device->handle);
    free(device);
}

static NTSTATUS usb_destroy_device(void *args)
{
    const struct usb_destroy_device_params *params = args;
    struct unix_device *device = params->device;

    decref_device(device);

    return STATUS_SUCCESS;
}

static NTSTATUS usb_control_transfer_sync(void *args)
{
    const struct usb_control_transfer_sync_params *params = args;
    const UCHAR *setup = params->setup;
    int ret;

    ret = libusb_control_transfer(params->device->handle, setup[0], setup[1],
            (setup[3] << 8) | setup[2], (setup[5] << 8) | setup[4],
            params->buffer, params->length, 5000);
    if (params->actual_length)
        *params->actual_length = ret >= 0 ? (ULONG)ret : 0;
    if (ret < 0)
        return STATUS_UNSUCCESSFUL;
    return STATUS_SUCCESS;
}

static NTSTATUS usb_bulk_transfer_sync(void *args)
{
    const struct usb_bulk_transfer_sync_params *params = args;
    int ret, transferred = 0;

    if (params->in)
        ret = libusb_bulk_transfer(params->device->handle, params->endpoint,
                params->buffer, params->length, &transferred, 5000);
    else
        ret = libusb_bulk_transfer(params->device->handle, params->endpoint,
                params->buffer, params->length, &transferred, 5000);
    if (params->actual_length)
        *params->actual_length = (ULONG)transferred;
    if (ret < 0)
        return STATUS_UNSUCCESSFUL;
    return STATUS_SUCCESS;
}

static NTSTATUS usb_set_interface_alt_setting(void *args)
{
    const struct usb_set_interface_alt_setting_params *params = args;
    int ret;

    ret = libusb_set_interface_alt_setting(params->device->handle,
            params->interface_number, params->alternate_setting);
    if (ret < 0)
    {
        WARN("libusb_set_interface_alt_setting: %s\n", libusb_strerror(ret));
        return STATUS_UNSUCCESSFUL;
    }
    return STATUS_SUCCESS;
}

/* Windows USB_DEVICE_SPEED: Low=0, Full=1, High=2, Super=3 */
static NTSTATUS usb_get_device_speed(void *args)
{
    struct usb_get_device_speed_params *params = args;
    libusb_device *dev;
    int speed;

    dev = libusb_get_device(params->device->handle);
    if (!dev)
        return STATUS_UNSUCCESSFUL;
    speed = libusb_get_device_speed(dev);
    switch (speed)
    {
        case LIBUSB_SPEED_LOW:   params->speed = 0; break;
        case LIBUSB_SPEED_FULL:  params->speed = 1; break;
        case LIBUSB_SPEED_HIGH:  params->speed = 2; break;
        case LIBUSB_SPEED_SUPER: params->speed = 3; break;
        default:                 params->speed = 1; break; /* assume full-speed */
    }
    return STATUS_SUCCESS;
}

static NTSTATUS usb_get_serial_number(void *args)
{
    struct usb_get_serial_params *params = args;
    libusb_device *dev;
    struct libusb_device_descriptor desc;
    int ret;

    params->serial[0] = '\0';
    dev = libusb_get_device(params->device->handle);
    if (!dev)
        return STATUS_UNSUCCESSFUL;
    if ((ret = libusb_get_device_descriptor(dev, &desc)) < 0)
        return STATUS_UNSUCCESSFUL;
    if (!desc.iSerialNumber)
        return STATUS_SUCCESS; /* no serial, leave buffer empty */
    ret = libusb_get_string_descriptor_ascii(params->device->handle, desc.iSerialNumber,
            (unsigned char *)params->serial, sizeof(params->serial));
    if (ret < 0)
    {
        WARN("Failed to get serial string: %s\n", libusb_strerror(ret));
        return STATUS_SUCCESS; /* device has no readable serial, leave empty */
    }
    if ((size_t)ret >= sizeof(params->serial))
        params->serial[sizeof(params->serial) - 1] = '\0';
    return STATUS_SUCCESS;
}

struct ioctl_async_ctx
{
    IRP *irp;
    void *user_buffer;
};

static void LIBUSB_CALL ioctl_control_cb(struct libusb_transfer *transfer)
{
    struct ioctl_async_ctx *ctx = transfer->user_data;
    struct usb_event event;
    NTSTATUS status = STATUS_SUCCESS;

    if (transfer->status != LIBUSB_TRANSFER_COMPLETED)
        status = STATUS_UNSUCCESSFUL;
    if (status == STATUS_SUCCESS && (transfer->buffer[0] & 0x80) && transfer->actual_length)
        memcpy(ctx->user_buffer, libusb_control_transfer_get_data(transfer), transfer->actual_length);

    libusb_free_transfer(transfer);
    event.type = USB_EVENT_IOCTL_COMPLETE;
    event.u.ioctl_complete.irp = ctx->irp;
    event.u.ioctl_complete.actual_length = transfer->actual_length;
    event.u.ioctl_complete.status = status;
    queue_event(&event);
    free(ctx);
}

static NTSTATUS usb_control_transfer_async(void *args)
{
    const struct usb_control_transfer_async_params *params = args;
    const UCHAR *setup = params->setup;
    struct libusb_transfer *transfer;
    struct ioctl_async_ctx *ctx;
    unsigned char *buffer;
    size_t buf_len = sizeof(struct libusb_control_setup) + params->length;

    if (!(ctx = calloc(1, sizeof(*ctx))))
        return STATUS_NO_MEMORY;
    ctx->irp = params->irp;
    ctx->user_buffer = params->buffer;

    if (!(transfer = libusb_alloc_transfer(0)))
    {
        free(ctx);
        return STATUS_NO_MEMORY;
    }
    if (!(buffer = malloc(buf_len)))
    {
        libusb_free_transfer(transfer);
        free(ctx);
        return STATUS_NO_MEMORY;
    }

    libusb_fill_control_setup(buffer, setup[0], setup[1],
            (setup[3] << 8) | setup[2], (setup[5] << 8) | setup[4],
            (setup[7] << 8) | setup[6]);
    if (!(setup[0] & 0x80) && params->length)
        memcpy(buffer + sizeof(struct libusb_control_setup), params->buffer, params->length);
    libusb_fill_control_transfer(transfer, params->device->handle, buffer, ioctl_control_cb, ctx, 5000);
    transfer->flags = LIBUSB_TRANSFER_FREE_BUFFER;

    if (libusb_submit_transfer(transfer) < 0)
    {
        free(buffer);
        libusb_free_transfer(transfer);
        free(ctx);
        return STATUS_UNSUCCESSFUL;
    }
    return STATUS_PENDING;
}

static void LIBUSB_CALL ioctl_bulk_cb(struct libusb_transfer *transfer)
{
    struct ioctl_async_ctx *ctx = transfer->user_data;
    struct usb_event event;

    event.type = USB_EVENT_IOCTL_COMPLETE;
    event.u.ioctl_complete.irp = ctx->irp;
    event.u.ioctl_complete.actual_length = transfer->actual_length;
    event.u.ioctl_complete.status = (transfer->status == LIBUSB_TRANSFER_COMPLETED) ? STATUS_SUCCESS : STATUS_UNSUCCESSFUL;
    queue_event(&event);
    libusb_free_transfer(transfer);
    free(ctx);
}

static NTSTATUS usb_bulk_transfer_async(void *args)
{
    const struct usb_bulk_transfer_async_params *params = args;
    struct libusb_transfer *transfer;
    struct ioctl_async_ctx *ctx;

    if (!(ctx = calloc(1, sizeof(*ctx))))
        return STATUS_NO_MEMORY;
    ctx->irp = params->irp;
    ctx->user_buffer = NULL;

    if (!(transfer = libusb_alloc_transfer(0)))
    {
        free(ctx);
        return STATUS_NO_MEMORY;
    }
    libusb_fill_bulk_transfer(transfer, params->device->handle, params->endpoint,
            params->buffer, params->length, ioctl_bulk_cb, ctx,
            params->timeout_ms ? params->timeout_ms : 5000);

    if (libusb_submit_transfer(transfer) < 0)
    {
        libusb_free_transfer(transfer);
        free(ctx);
        return STATUS_UNSUCCESSFUL;
    }
    return STATUS_PENDING;
}

const unixlib_entry_t __wine_unix_call_funcs[] =
{
#define X(name) [unix_ ## name] = name
    X(usb_main_loop),
    X(usb_init),
    X(usb_exit),
    X(usb_submit_urb),
    X(usb_cancel_transfer),
    X(usb_destroy_device),
    X(usb_control_transfer_sync),
    X(usb_bulk_transfer_sync),
    X(usb_control_transfer_async),
    X(usb_bulk_transfer_async),
    X(usb_set_interface_alt_setting),
    X(usb_get_device_speed),
    X(usb_get_serial_number),
};
