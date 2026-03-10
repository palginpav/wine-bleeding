/*
 * wineusb Unix library interface
 *
 * Copyright 2022 Zebediah Figura for CodeWeavers
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

#ifndef __WINE_WINEUSB_UNIXLIB_H
#define __WINE_WINEUSB_UNIXLIB_H

#include "windef.h"
#include "winternl.h"
#include "ddk/wdm.h"
#include "wine/unixlib.h"

enum usb_event_type
{
    USB_EVENT_ADD_DEVICE,
    USB_EVENT_REMOVE_DEVICE,
    USB_EVENT_TRANSFER_COMPLETE,
    USB_EVENT_IOCTL_COMPLETE,
};

struct usb_event
{
    enum usb_event_type type;

    union
    {
        struct usb_add_device_event
        {
            struct unix_device *device;
            UINT16 vendor, product, revision, usbver;
            UINT8 class, subclass, protocol, busnum, portnum;
            bool interface;
            INT16 interface_index;
        } added_device;
        struct unix_device *removed_device;
        IRP *completed_irp;
        struct usb_ioctl_complete
        {
            IRP *irp;
            ULONG actual_length;
            NTSTATUS status;
        } ioctl_complete;
    } u;
};

struct usb_main_loop_params
{
    struct usb_event *event;
};

struct usb_submit_urb_params
{
    struct unix_device *device;
    IRP *irp;
    void *transfer_buffer;
};

struct usb_cancel_transfer_params
{
    void *transfer;
};

struct usb_destroy_device_params
{
    struct unix_device *device;
};

struct usb_control_transfer_sync_params
{
    struct unix_device *device;
    UCHAR setup[8];
    void *buffer;
    ULONG length;
    ULONG *actual_length;
};

struct usb_bulk_transfer_sync_params
{
    struct unix_device *device;
    UCHAR endpoint;
    void *buffer;
    ULONG length;
    BOOL in;
    ULONG *actual_length;
};

struct usb_control_transfer_async_params
{
    struct unix_device *device;
    UCHAR setup[8];
    void *buffer;
    ULONG length;
    IRP *irp;
};

struct usb_bulk_transfer_async_params
{
    struct unix_device *device;
    UCHAR endpoint;
    void *buffer;
    ULONG length;
    BOOL in;
    IRP *irp;
    ULONG timeout_ms;  /* 0 = use default 5000 */
};

struct usb_set_interface_alt_setting_params
{
    struct unix_device *device;
    UCHAR interface_number;
    UCHAR alternate_setting;
};

struct usb_get_device_speed_params
{
    struct unix_device *device;
    ULONG speed;
};

#define USB_SERIAL_BUFFER_SIZE 256

struct usb_get_serial_params
{
    struct unix_device *device;
    char serial[USB_SERIAL_BUFFER_SIZE];
};

enum unix_funcs
{
    unix_usb_main_loop,
    unix_usb_init,
    unix_usb_exit,
    unix_usb_submit_urb,
    unix_usb_cancel_transfer,
    unix_usb_destroy_device,
    unix_usb_control_transfer_sync,
    unix_usb_bulk_transfer_sync,
    unix_usb_control_transfer_async,
    unix_usb_bulk_transfer_async,
    unix_usb_set_interface_alt_setting,
    unix_usb_get_device_speed,
    unix_usb_get_serial_number,
};

#endif
