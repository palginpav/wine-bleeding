/*
 * Copyright (C) 2022 Mohamad Al-Jaf
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

#include <stdarg.h>

#include "windef.h"
#include "winbase.h"
#include "winusb.h"
#include "winusbioctl.h"
#include "ddk/usb100.h"

#include "wine/debug.h"

WINE_DEFAULT_DEBUG_CHANNEL(winusb);

struct pipe_policy_entry
{
    struct pipe_policy_entry *next;
    UCHAR pipe_id;
    ULONG policy_type;
    ULONG value_len;
    UCHAR value[1];
};

struct power_policy_entry
{
    struct power_policy_entry *next;
    ULONG policy_type;
    ULONG value_len;
    UCHAR value[1];
};

struct winusb_handle
{
    HANDLE device_handle;
    struct pipe_policy_entry *policies;
    struct power_policy_entry *power_policies;
    UCHAR current_alternate_setting;
    UCHAR interface_index;
};

/***********************************************************************
 *           WinUsb_Initialize (winusb.@)
 */
BOOL WINAPI WinUsb_Initialize(HANDLE device_handle, PWINUSB_INTERFACE_HANDLE interface_handle)
{
    struct winusb_handle *handle;

    TRACE("(%p, %p)\n", device_handle, interface_handle);

    if (!device_handle || device_handle == INVALID_HANDLE_VALUE || !interface_handle)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    if (!(handle = HeapAlloc(GetProcessHeap(), 0, sizeof(*handle))))
    {
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return FALSE;
    }
    handle->device_handle = device_handle;
    handle->policies = NULL;
    handle->power_policies = NULL;
    handle->current_alternate_setting = 0;
    handle->interface_index = 0;
    *interface_handle = handle;
    return TRUE;
}

/***********************************************************************
 *           WinUsb_Free (winusb.@)
 */
BOOL WINAPI WinUsb_Free(WINUSB_INTERFACE_HANDLE interface_handle)
{
    struct winusb_handle *handle = interface_handle;

    TRACE("(%p)\n", interface_handle);

    if (!handle)
        return TRUE;
    while (handle->policies)
    {
        struct pipe_policy_entry *cur = handle->policies;
        handle->policies = cur->next;
        HeapFree(GetProcessHeap(), 0, cur);
    }
    while (handle->power_policies)
    {
        struct power_policy_entry *cur = handle->power_policies;
        handle->power_policies = cur->next;
        HeapFree(GetProcessHeap(), 0, cur);
    }
    HeapFree(GetProcessHeap(), 0, handle);
    return TRUE;
}

/***********************************************************************
 *           WinUsb_ControlTransfer (winusb.@)
 */
BOOL WINAPI WinUsb_ControlTransfer(WINUSB_INTERFACE_HANDLE interface_handle,
    const WINUSB_SETUP_PACKET *setup_packet, PUCHAR buffer, ULONG buffer_length,
    PULONG length_transferred, LPOVERLAPPED overlapped)
{
    struct winusb_handle *handle = interface_handle;
    UCHAR ioctl_buf[8 + 4096];
    DWORD bytes_returned;
    BOOL ret;

    TRACE("(%p, %p, %p, %lu, %p, %p)\n", interface_handle, setup_packet, buffer,
          buffer_length, length_transferred, overlapped);

    if (!handle || !setup_packet)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }
    ioctl_buf[0] = setup_packet->RequestType;
    ioctl_buf[1] = setup_packet->Request;
    ioctl_buf[2] = (UCHAR)(setup_packet->Value);
    ioctl_buf[3] = (UCHAR)(setup_packet->Value >> 8);
    ioctl_buf[4] = (UCHAR)(setup_packet->Index);
    ioctl_buf[5] = (UCHAR)(setup_packet->Index >> 8);
    ioctl_buf[6] = (UCHAR)(setup_packet->Length);
    ioctl_buf[7] = (UCHAR)(setup_packet->Length >> 8);

    if (!(setup_packet->RequestType & 0x80) && setup_packet->Length && buffer)
        memcpy(ioctl_buf + 8, buffer, min(setup_packet->Length, buffer_length));

    ret = DeviceIoControl(handle->device_handle, IOCTL_WINEUSB_CONTROL_TRANSFER,
            ioctl_buf, 8 + ((setup_packet->RequestType & 0x80) ? 0 : min(setup_packet->Length, buffer_length)),
            (setup_packet->RequestType & 0x80) ? buffer : NULL,
            (setup_packet->RequestType & 0x80) ? buffer_length : 0,
            &bytes_returned, overlapped);
    if (ret && length_transferred && !overlapped)
        *length_transferred = bytes_returned;
    if (!ret && overlapped && GetLastError() == ERROR_IO_PENDING)
        return TRUE;
    return ret;
}

#define PIPE_TRANSFER_TIMEOUT 3

/***********************************************************************
 *           WinUsb_ReadPipe (winusb.@)
 */
BOOL WINAPI WinUsb_ReadPipe(WINUSB_INTERFACE_HANDLE interface_handle, UCHAR pipe_id,
    PUCHAR buffer, ULONG buffer_length, PULONG length_transferred, LPOVERLAPPED overlapped)
{
    struct winusb_handle *handle = interface_handle;
    struct pipe_policy_entry *p;
    DWORD bytes_returned;
    BOOL ret;
    UCHAR in_buf[5];
    void *in_ptr = &pipe_id;
    ULONG in_len = 1;

    TRACE("(%p, %u, %p, %lu, %p, %p)\n", interface_handle, pipe_id, buffer,
          buffer_length, length_transferred, overlapped);

    if (!handle || !buffer)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }
    if (!overlapped)
    {
        for (p = handle->policies; p; p = p->next)
        {
            if (p->pipe_id == pipe_id && p->policy_type == PIPE_TRANSFER_TIMEOUT && p->value_len >= sizeof(ULONG))
            {
                in_buf[0] = pipe_id;
                *(ULONG *)(in_buf + 1) = *(ULONG *)p->value;
                in_ptr = in_buf;
                in_len = 5;
                break;
            }
        }
    }
    ret = DeviceIoControl(handle->device_handle, IOCTL_WINEUSB_READ_PIPE,
            in_ptr, in_len, buffer, buffer_length, &bytes_returned, overlapped);
    if (ret && length_transferred && !overlapped)
        *length_transferred = bytes_returned;
    if (!ret && overlapped && GetLastError() == ERROR_IO_PENDING)
        return TRUE;
    return ret;
}

/***********************************************************************
 *           WinUsb_WritePipe (winusb.@)
 */
BOOL WINAPI WinUsb_WritePipe(WINUSB_INTERFACE_HANDLE interface_handle, UCHAR pipe_id,
    PUCHAR buffer, ULONG buffer_length, PULONG length_transferred, LPOVERLAPPED overlapped)
{
    struct winusb_handle *handle = interface_handle;
    UCHAR *ioctl_buf;
    DWORD bytes_returned;
    BOOL ret;

    TRACE("(%p, %u, %p, %lu, %p, %p)\n", interface_handle, pipe_id, buffer,
          buffer_length, length_transferred, overlapped);

    if (!handle || !buffer)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }
    if (!(ioctl_buf = HeapAlloc(GetProcessHeap(), 0, 1 + buffer_length)))
    {
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return FALSE;
    }
    ioctl_buf[0] = pipe_id;
    memcpy(ioctl_buf + 1, buffer, buffer_length);
    ret = DeviceIoControl(handle->device_handle, IOCTL_WINEUSB_WRITE_PIPE,
            ioctl_buf, 1 + buffer_length, NULL, 0, &bytes_returned, overlapped);
    HeapFree(GetProcessHeap(), 0, ioctl_buf);
    if (ret && length_transferred && !overlapped)
        *length_transferred = bytes_returned;
    if (!ret && overlapped && GetLastError() == ERROR_IO_PENDING)
        return TRUE;
    return ret;
}

/***********************************************************************
 *           WinUsb_GetOverlappedResult (winusb.@)
 */
BOOL WINAPI WinUsb_GetOverlappedResult(WINUSB_INTERFACE_HANDLE interface_handle,
    LPOVERLAPPED overlapped, PULONG length_transferred, BOOL wait)
{
    struct winusb_handle *handle = interface_handle;

    TRACE("(%p, %p, %p, %d)\n", interface_handle, overlapped, length_transferred, wait);

    if (!handle || !overlapped)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }
    return GetOverlappedResult(handle->device_handle, overlapped, (LPDWORD)length_transferred, wait);
}

/***********************************************************************
 *           WinUsb_AbortPipe (winusb.@)
 */
BOOL WINAPI WinUsb_AbortPipe(WINUSB_INTERFACE_HANDLE interface_handle, UCHAR pipe_id)
{
    struct winusb_handle *handle = interface_handle;
    DWORD bytes_returned;
    BOOL ret;

    TRACE("(%p, %u)\n", interface_handle, pipe_id);

    if (!handle)
    {
        SetLastError(ERROR_INVALID_HANDLE);
        return FALSE;
    }

    ret = DeviceIoControl(handle->device_handle, IOCTL_WINEUSB_ABORT_PIPE,
            &pipe_id, sizeof(pipe_id), NULL, 0, &bytes_returned, NULL);
    return ret;
}

/***********************************************************************
 *           WinUsb_ResetPipe (winusb.@)
 */
BOOL WINAPI WinUsb_ResetPipe(WINUSB_INTERFACE_HANDLE interface_handle, UCHAR pipe_id)
{
    WINUSB_SETUP_PACKET setup;

    TRACE("(%p, %u)\n", interface_handle, pipe_id);

    /* Standard CLEAR_FEATURE(ENDPOINT_HALT) for this endpoint. */
    memset(&setup, 0, sizeof(setup));
    setup.RequestType = 0x02; /* standard, recipient endpoint, host-to-device */
    setup.Request     = 0x01; /* CLEAR_FEATURE */
    setup.Value       = 0x0000; /* ENDPOINT_HALT */
    setup.Index       = pipe_id;
    setup.Length      = 0;

    return WinUsb_ControlTransfer(interface_handle, &setup, NULL, 0, NULL, NULL);
}

/***********************************************************************
 *           WinUsb_FlushPipe (winusb.@)
 */
BOOL WINAPI WinUsb_FlushPipe(WINUSB_INTERFACE_HANDLE interface_handle, UCHAR pipe_id)
{
    struct winusb_handle *handle = interface_handle;
    TRACE("(%p, %u)\n", interface_handle, pipe_id);

    /* No extra buffering in wineusb.sys; nothing to flush. */
    if (!handle)
    {
        SetLastError(ERROR_INVALID_HANDLE);
        return FALSE;
    }
    return TRUE;
}

/***********************************************************************
 *           WinUsb_SetPipePolicy (winusb.@)
 */
BOOL WINAPI WinUsb_SetPipePolicy(WINUSB_INTERFACE_HANDLE interface_handle, UCHAR pipe_id,
    ULONG policy_type, ULONG value_length, PVOID value)
{
    struct winusb_handle *handle = interface_handle;
    struct pipe_policy_entry **p, *entry;

    TRACE("(%p, %u, %lu, %lu, %p)\n", interface_handle, pipe_id, policy_type, value_length, value);

    if (!handle || !value)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    for (p = &handle->policies; *p; p = &(*p)->next)
    {
        if ((*p)->pipe_id == pipe_id && (*p)->policy_type == policy_type)
        {
            if (value_length != (*p)->value_len)
            {
                entry = HeapReAlloc(GetProcessHeap(), 0, *p, sizeof(struct pipe_policy_entry) + value_length);
                if (!entry)
                {
                    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
                    return FALSE;
                }
                *p = entry;
            }
            entry = *p;
            entry->value_len = value_length;
            memcpy(entry->value, value, value_length);
            return TRUE;
        }
    }

    entry = HeapAlloc(GetProcessHeap(), 0, sizeof(struct pipe_policy_entry) + value_length);
    if (!entry)
    {
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return FALSE;
    }
    entry->next = handle->policies;
    entry->pipe_id = pipe_id;
    entry->policy_type = policy_type;
    entry->value_len = value_length;
    memcpy(entry->value, value, value_length);
    handle->policies = entry;
    return TRUE;
}

/***********************************************************************
 *           WinUsb_GetPipePolicy (winusb.@)
 */
BOOL WINAPI WinUsb_GetPipePolicy(WINUSB_INTERFACE_HANDLE interface_handle, UCHAR pipe_id,
    ULONG policy_type, PULONG value_length, PVOID value)
{
    struct winusb_handle *handle = interface_handle;
    struct pipe_policy_entry *p;

    TRACE("(%p, %u, %lu, %p, %p)\n", interface_handle, pipe_id, policy_type, value_length, value);

    if (!handle || !value_length)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    for (p = handle->policies; p; p = p->next)
    {
        if (p->pipe_id == pipe_id && p->policy_type == policy_type)
        {
            if (*value_length < p->value_len)
            {
                *value_length = p->value_len;
                SetLastError(ERROR_INSUFFICIENT_BUFFER);
                return FALSE;
            }
            *value_length = p->value_len;
            if (value && p->value_len)
                memcpy(value, p->value, p->value_len);
            return TRUE;
        }
    }

    SetLastError(ERROR_NOT_FOUND);
    return FALSE;
}

/***********************************************************************
 *           WinUsb_SetPowerPolicy (winusb.@)
 */
BOOL WINAPI WinUsb_SetPowerPolicy(WINUSB_INTERFACE_HANDLE interface_handle, ULONG policy_type,
    ULONG value_length, PVOID value)
{
    struct winusb_handle *handle = interface_handle;
    struct power_policy_entry **p, *entry;

    TRACE("(%p, %lu, %lu, %p)\n", interface_handle, policy_type, value_length, value);

    if (!handle || !value)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    for (p = &handle->power_policies; *p; p = &(*p)->next)
    {
        if ((*p)->policy_type == policy_type)
        {
            if (value_length != (*p)->value_len)
            {
                entry = HeapReAlloc(GetProcessHeap(), 0, *p, sizeof(struct power_policy_entry) + value_length);
                if (!entry)
                {
                    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
                    return FALSE;
                }
                *p = entry;
            }
            entry = *p;
            entry->value_len = value_length;
            memcpy(entry->value, value, value_length);
            return TRUE;
        }
    }

    entry = HeapAlloc(GetProcessHeap(), 0, sizeof(struct power_policy_entry) + value_length);
    if (!entry)
    {
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return FALSE;
    }
    entry->next = handle->power_policies;
    entry->policy_type = policy_type;
    entry->value_len = value_length;
    memcpy(entry->value, value, value_length);
    handle->power_policies = entry;
    return TRUE;
}

/***********************************************************************
 *           WinUsb_GetPowerPolicy (winusb.@)
 */
BOOL WINAPI WinUsb_GetPowerPolicy(WINUSB_INTERFACE_HANDLE interface_handle, ULONG policy_type,
    PULONG value_length, PVOID value)
{
    struct winusb_handle *handle = interface_handle;
    struct power_policy_entry *p;

    TRACE("(%p, %lu, %p, %p)\n", interface_handle, policy_type, value_length, value);

    if (!handle || !value_length)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    for (p = handle->power_policies; p; p = p->next)
    {
        if (p->policy_type == policy_type)
        {
            if (*value_length < p->value_len)
            {
                *value_length = p->value_len;
                SetLastError(ERROR_INSUFFICIENT_BUFFER);
                return FALSE;
            }
            *value_length = p->value_len;
            if (value && p->value_len)
                memcpy(value, p->value, p->value_len);
            return TRUE;
        }
    }

    SetLastError(ERROR_NOT_FOUND);
    return FALSE;
}

/***********************************************************************
 *           WinUsb_QueryDeviceInformation (winusb.@)
 */
BOOL WINAPI WinUsb_QueryDeviceInformation(WINUSB_INTERFACE_HANDLE interface_handle, ULONG information_type,
    PULONG buffer_length, PVOID buffer)
{
    struct winusb_handle *handle = interface_handle;
    DWORD bytes_returned;
    ULONG in_buf;

    TRACE("(%p, %lu, %p, %p)\n", interface_handle, information_type, buffer_length, buffer);

    if (!handle || !buffer_length)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    if (information_type != 0x01) /* DEVICE_SPEED */
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    if (*buffer_length < sizeof(ULONG))
    {
        *buffer_length = sizeof(ULONG);
        SetLastError(ERROR_INSUFFICIENT_BUFFER);
        return FALSE;
    }

    in_buf = information_type;
    if (!DeviceIoControl(handle->device_handle, IOCTL_WINEUSB_QUERY_DEVICE_INFO, &in_buf, sizeof(in_buf),
            buffer, sizeof(ULONG), &bytes_returned, NULL))
        return FALSE;

    *buffer_length = sizeof(ULONG);
    return TRUE;
}

/***********************************************************************
 *           WinUsb_QueryPipe (winusb.@)
 */
BOOL WINAPI WinUsb_QueryPipe(WINUSB_INTERFACE_HANDLE interface_handle, UCHAR alternate_interface_number,
    UCHAR pipe_index, PWINUSB_PIPE_INFORMATION pipe_information)
{
    struct winusb_handle *handle = interface_handle;
    UCHAR *config_buf = NULL;
    DWORD config_len = 4096;
    DWORD bytes_returned;
    const UCHAR *ptr, *end;
    BOOL found = FALSE;
    UCHAR i;

    TRACE("(%p, %u, %u, %p)\n", interface_handle, alternate_interface_number, pipe_index, pipe_information);

    if (!handle || !pipe_information)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    config_buf = HeapAlloc(GetProcessHeap(), 0, config_len);
    if (!config_buf)
    {
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return FALSE;
    }
    if (!DeviceIoControl(handle->device_handle, IOCTL_WINEUSB_GET_CONFIG_DESCRIPTOR, NULL, 0,
            config_buf, config_len, &bytes_returned, NULL))
    {
        HeapFree(GetProcessHeap(), 0, config_buf);
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    ptr = config_buf;
    end = config_buf + bytes_returned;
    if (ptr + sizeof(USB_CONFIGURATION_DESCRIPTOR) > end)
        goto not_found;
    ptr += sizeof(USB_CONFIGURATION_DESCRIPTOR);

    while (ptr + sizeof(USB_COMMON_DESCRIPTOR) <= end)
    {
        const USB_COMMON_DESCRIPTOR *common = (const USB_COMMON_DESCRIPTOR *)ptr;
        if (common->bLength < 2)
            break;
        if (ptr + common->bLength > end)
            break;

        if (common->bDescriptorType == USB_INTERFACE_DESCRIPTOR_TYPE)
        {
            const USB_INTERFACE_DESCRIPTOR *iface = (const USB_INTERFACE_DESCRIPTOR *)ptr;
            if (iface->bInterfaceNumber == handle->interface_index && iface->bAlternateSetting == alternate_interface_number)
            {
                if (pipe_index >= iface->bNumEndpoints)
                {
                    SetLastError(ERROR_NO_MORE_ITEMS);
                    goto done;
                }
                ptr += iface->bLength;
                for (i = 0; i < iface->bNumEndpoints && ptr + sizeof(USB_ENDPOINT_DESCRIPTOR) <= end; i++)
                {
                    const USB_ENDPOINT_DESCRIPTOR *ep = (const USB_ENDPOINT_DESCRIPTOR *)ptr;
                    if (ep->bDescriptorType != USB_ENDPOINT_DESCRIPTOR_TYPE)
                        break;
                    if (i == pipe_index)
                    {
                        pipe_information->PipeId = ep->bEndpointAddress;
                        pipe_information->MaximumPacketSize = ep->wMaxPacketSize;
                        pipe_information->Interval = ep->bInterval;
                        switch (ep->bmAttributes & 0x03)
                        {
                            case USB_ENDPOINT_TYPE_ISOCHRONOUS:
                                pipe_information->PipeType = UsbdPipeTypeIsochronous;
                                break;
                            case USB_ENDPOINT_TYPE_BULK:
                                pipe_information->PipeType = UsbdPipeTypeBulk;
                                break;
                            case USB_ENDPOINT_TYPE_INTERRUPT:
                                pipe_information->PipeType = UsbdPipeTypeInterrupt;
                                break;
                            default:
                                pipe_information->PipeType = UsbdPipeTypeControl;
                                break;
                        }
                        found = TRUE;
                        goto done;
                    }
                    ptr += ep->bLength;
                }
                SetLastError(ERROR_NO_MORE_ITEMS);
                goto done;
            }
        }
        ptr += common->bLength;
    }
not_found:
    SetLastError(ERROR_INVALID_PARAMETER);
done:
    HeapFree(GetProcessHeap(), 0, config_buf);
    return found;
}

/***********************************************************************
 *           WinUsb_GetAssociatedInterface (winusb.@)
 */
BOOL WINAPI WinUsb_GetAssociatedInterface(WINUSB_INTERFACE_HANDLE interface_handle, UCHAR associated_interface_index,
    PWINUSB_INTERFACE_HANDLE associated_interface_handle)
{
    struct winusb_handle *parent = interface_handle;
    struct winusb_handle *handle;

    TRACE("(%p, %u, %p)\n", interface_handle, associated_interface_index, associated_interface_handle);

    if (!parent || !associated_interface_handle)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    if (!(handle = HeapAlloc(GetProcessHeap(), 0, sizeof(*handle))))
    {
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return FALSE;
    }
    handle->device_handle = parent->device_handle;
    handle->policies = NULL;
    handle->power_policies = NULL;
    handle->current_alternate_setting = 0;
    handle->interface_index = associated_interface_index;
    *associated_interface_handle = handle;
    return TRUE;
}

/***********************************************************************
 *           WinUsb_GetDescriptor (winusb.@)
 */
BOOL WINAPI WinUsb_GetDescriptor(WINUSB_INTERFACE_HANDLE interface_handle, UCHAR descriptor_type,
    UCHAR index, USHORT language_id, PUCHAR buffer, ULONG buffer_length, PULONG length_transferred)
{
    struct winusb_handle *handle = interface_handle;
    WINUSB_SETUP_PACKET setup;

    TRACE("(%p, %u, %u, %u, %p, %lu, %p)\n", interface_handle, descriptor_type, index, language_id,
          buffer, buffer_length, length_transferred);

    if (!handle || !buffer || !length_transferred)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    setup.RequestType = 0x80;  /* device-to-host, standard, device */
    setup.Request     = 0x06;   /* GET_DESCRIPTOR */
    setup.Value       = (descriptor_type << 8) | index;
    setup.Index       = language_id;
    setup.Length      = (USHORT)buffer_length;

    if (!WinUsb_ControlTransfer(interface_handle, &setup, buffer, buffer_length, length_transferred, NULL))
        return FALSE;
    return TRUE;
}

/***********************************************************************
 *           WinUsb_SetCurrentAlternateSetting (winusb.@)
 */
BOOL WINAPI WinUsb_SetCurrentAlternateSetting(WINUSB_INTERFACE_HANDLE interface_handle, UCHAR setting_number)
{
    struct winusb_handle *handle = interface_handle;
    UCHAR inbuf[2];
    DWORD bytes_returned;

    TRACE("(%p, %u)\n", interface_handle, setting_number);

    if (!handle)
    {
        SetLastError(ERROR_INVALID_HANDLE);
        return FALSE;
    }

    inbuf[0] = handle->interface_index;
    inbuf[1] = setting_number;
    if (!DeviceIoControl(handle->device_handle, IOCTL_WINEUSB_SET_INTERFACE, inbuf, sizeof(inbuf), NULL, 0, &bytes_returned, NULL))
        return FALSE;
    handle->current_alternate_setting = setting_number;
    return TRUE;
}

/***********************************************************************
 *           WinUsb_GetCurrentAlternateSetting (winusb.@)
 */
BOOL WINAPI WinUsb_GetCurrentAlternateSetting(WINUSB_INTERFACE_HANDLE interface_handle, PUCHAR setting_number)
{
    struct winusb_handle *handle = interface_handle;

    TRACE("(%p, %p)\n", interface_handle, setting_number);

    if (!handle || !setting_number)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }
    *setting_number = handle->current_alternate_setting;
    return TRUE;
}

/***********************************************************************
 *           WinUsb_ParseConfigurationDescriptor (winusb.@)
 */
PUSB_INTERFACE_DESCRIPTOR WINAPI WinUsb_ParseConfigurationDescriptor(
    PUSB_CONFIGURATION_DESCRIPTOR configuration_descriptor, UCHAR interface_number, UCHAR alternate_setting)
{
    const UCHAR *ptr, *end;
    const USB_COMMON_DESCRIPTOR *common;

    TRACE("(%p, %u, %u)\n", configuration_descriptor, interface_number, alternate_setting);

    if (!configuration_descriptor || configuration_descriptor->bLength < sizeof(USB_CONFIGURATION_DESCRIPTOR))
        return NULL;

    ptr = (const UCHAR *)configuration_descriptor;
    end = ptr + configuration_descriptor->wTotalLength;

    ptr += configuration_descriptor->bLength;
    while (ptr + sizeof(USB_COMMON_DESCRIPTOR) <= end)
    {
        common = (const USB_COMMON_DESCRIPTOR *)ptr;
        if (common->bLength < 2 || ptr + common->bLength > end)
            break;
        if (common->bDescriptorType == USB_INTERFACE_DESCRIPTOR_TYPE)
        {
            const USB_INTERFACE_DESCRIPTOR *iface = (const USB_INTERFACE_DESCRIPTOR *)ptr;
            if (iface->bInterfaceNumber == interface_number && iface->bAlternateSetting == alternate_setting)
                return (PUSB_INTERFACE_DESCRIPTOR)(void *)ptr;
        }
        ptr += common->bLength;
    }
    return NULL;
}

/***********************************************************************
 *           WinUsb_QueryInterfaceSettings (winusb.@)
 */
BOOL WINAPI WinUsb_QueryInterfaceSettings(WINUSB_INTERFACE_HANDLE interface_handle, UCHAR alternate_interface_number,
    PUSB_INTERFACE_DESCRIPTOR usb_alt_interface_descriptor)
{
    struct winusb_handle *handle = interface_handle;
    UCHAR *config_buf = NULL;
    DWORD config_len = 4096;
    DWORD bytes_returned;
    const UCHAR *ptr, *end;
    BOOL found = FALSE;

    TRACE("(%p, %u, %p)\n", interface_handle, alternate_interface_number, usb_alt_interface_descriptor);

    if (!handle || !usb_alt_interface_descriptor)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    config_buf = HeapAlloc(GetProcessHeap(), 0, config_len);
    if (!config_buf)
    {
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return FALSE;
    }
    if (!DeviceIoControl(handle->device_handle, IOCTL_WINEUSB_GET_CONFIG_DESCRIPTOR, NULL, 0,
            config_buf, config_len, &bytes_returned, NULL))
    {
        HeapFree(GetProcessHeap(), 0, config_buf);
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    ptr = config_buf;
    end = config_buf + bytes_returned;
    if (ptr + sizeof(USB_CONFIGURATION_DESCRIPTOR) > end)
        goto not_found;
    ptr += sizeof(USB_CONFIGURATION_DESCRIPTOR);

    while (ptr + sizeof(USB_COMMON_DESCRIPTOR) <= end)
    {
        const USB_COMMON_DESCRIPTOR *common = (const USB_COMMON_DESCRIPTOR *)ptr;
        if (common->bLength < 2 || ptr + common->bLength > end)
            break;
        if (common->bDescriptorType == USB_INTERFACE_DESCRIPTOR_TYPE)
        {
            const USB_INTERFACE_DESCRIPTOR *iface = (const USB_INTERFACE_DESCRIPTOR *)ptr;
            if (iface->bInterfaceNumber == handle->interface_index && iface->bAlternateSetting == alternate_interface_number)
            {
                memcpy(usb_alt_interface_descriptor, iface, sizeof(USB_INTERFACE_DESCRIPTOR));
                found = TRUE;
                break;
            }
        }
        ptr += common->bLength;
    }
not_found:
    HeapFree(GetProcessHeap(), 0, config_buf);
    if (!found)
        SetLastError(ERROR_NO_MORE_ITEMS);
    return found;
}

/***********************************************************************
 *           WinUsb_ParseDescriptors (winusb.@)
 */
PUSB_COMMON_DESCRIPTOR WINAPI WinUsb_ParseDescriptors(PVOID descriptor_buffer, ULONG total_length,
    PVOID start_position, LONG descriptor_type)
{
    PUSB_COMMON_DESCRIPTOR common;

    TRACE("(%p, %lu, %p, %ld)\n", descriptor_buffer, total_length, start_position, descriptor_type);

    if (!descriptor_buffer)
        return NULL;

    for (common = (PUSB_COMMON_DESCRIPTOR)descriptor_buffer;
         (const UCHAR *)common + sizeof(USB_COMMON_DESCRIPTOR) <= (const UCHAR *)descriptor_buffer + total_length;
         common = (PUSB_COMMON_DESCRIPTOR)((const UCHAR *)common + common->bLength))
    {
        if (start_position <= (PVOID)common && common->bDescriptorType == (UCHAR)descriptor_type)
            return common;
    }
    return NULL;
}
