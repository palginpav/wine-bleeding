/*
 * Wine WinUSB IOCTL codes for user-mode DeviceIoControl to wineusb.sys
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 */

#ifndef __WINE_WINUSBIOCTL_H
#define __WINE_WINUSBIOCTL_H

#include <winioctl.h>

#define IOCTL_WINEUSB_GET_CONFIG_DESCRIPTOR \
    CTL_CODE(FILE_DEVICE_UNKNOWN, 0x800, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_WINEUSB_CONTROL_TRANSFER \
    CTL_CODE(FILE_DEVICE_UNKNOWN, 0x801, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_WINEUSB_READ_PIPE \
    CTL_CODE(FILE_DEVICE_UNKNOWN, 0x802, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_WINEUSB_WRITE_PIPE \
    CTL_CODE(FILE_DEVICE_UNKNOWN, 0x803, METHOD_BUFFERED, FILE_ANY_ACCESS)

/* IOCTL_WINEUSB_CONTROL_TRANSFER: Input = 8-byte setup packet then optional data. Output = optional data. */
/* IOCTL_WINEUSB_READ_PIPE: Input = UCHAR PipeID. Output = data. */
/* IOCTL_WINEUSB_WRITE_PIPE: Input = UCHAR PipeID then data. Output = bytes written (optional). */

#define IOCTL_WINEUSB_SET_INTERFACE \
    CTL_CODE(FILE_DEVICE_UNKNOWN, 0x805, METHOD_BUFFERED, FILE_ANY_ACCESS)
/* IOCTL_WINEUSB_SET_INTERFACE: Input = UCHAR interface_number, UCHAR alternate_setting. */

#define IOCTL_WINEUSB_QUERY_DEVICE_INFO \
    CTL_CODE(FILE_DEVICE_UNKNOWN, 0x806, METHOD_BUFFERED, FILE_ANY_ACCESS)

#endif /* __WINE_WINUSBIOCTL_H */
