/*
 * Copyright (C) 2013 Damjan Jovanovic
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

#ifndef __DDK_USBIODEF_H__
#define __DDK_USBIODEF_H__

#include <guiddef.h>

#define USB_SUBMIT_URB 0

#define FILE_DEVICE_USB FILE_DEVICE_UNKNOWN

/* Device interface GUID for USB devices (used with SetupAPI / CreateFile) */
DEFINE_GUID(GUID_DEVINTERFACE_USB_DEVICE, 0xa5dcbf10, 0x6530, 0x11d2, 0x90, 0x1f, 0x00, 0xc0, 0x4f, 0xb9, 0x51, 0xed);

#endif /* __DDK_USBIODEF_H__ */
