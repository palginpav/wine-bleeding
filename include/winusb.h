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

#ifndef _WINUSB_H_
#define _WINUSB_H_

#include <winioctl.h>
#include <ddk/usb100.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef PVOID WINUSB_INTERFACE_HANDLE, *PWINUSB_INTERFACE_HANDLE;

typedef enum _USBD_PIPE_TYPE {
    UsbdPipeTypeControl = 0,
    UsbdPipeTypeIsochronous,
    UsbdPipeTypeBulk,
    UsbdPipeTypeInterrupt
} USBD_PIPE_TYPE;

typedef struct _WINUSB_PIPE_INFORMATION {
    USBD_PIPE_TYPE PipeType;
    UCHAR PipeId;
    USHORT MaximumPacketSize;
    UCHAR Interval;
} WINUSB_PIPE_INFORMATION, *PWINUSB_PIPE_INFORMATION;

typedef struct _WINUSB_SETUP_PACKET {
  UCHAR  RequestType;
  UCHAR  Request;
  USHORT Value;
  USHORT Index;
  USHORT Length;
} WINUSB_SETUP_PACKET, *PWINUSB_SETUP_PACKET;

BOOL WINAPI WinUsb_Initialize(HANDLE DeviceHandle, PWINUSB_INTERFACE_HANDLE InterfaceHandle);
BOOL WINAPI WinUsb_Free(WINUSB_INTERFACE_HANDLE InterfaceHandle);
BOOL WINAPI WinUsb_ControlTransfer(WINUSB_INTERFACE_HANDLE InterfaceHandle, const WINUSB_SETUP_PACKET *SetupPacket,
    PUCHAR Buffer, ULONG BufferLength, PULONG LengthTransferred, LPOVERLAPPED Overlapped);
BOOL WINAPI WinUsb_ReadPipe(WINUSB_INTERFACE_HANDLE InterfaceHandle, UCHAR PipeID, PUCHAR Buffer,
    ULONG BufferLength, PULONG LengthTransferred, LPOVERLAPPED Overlapped);
BOOL WINAPI WinUsb_WritePipe(WINUSB_INTERFACE_HANDLE InterfaceHandle, UCHAR PipeID, PUCHAR Buffer,
    ULONG BufferLength, PULONG LengthTransferred, LPOVERLAPPED Overlapped);
BOOL WINAPI WinUsb_GetOverlappedResult(WINUSB_INTERFACE_HANDLE InterfaceHandle, LPOVERLAPPED Overlapped,
    PULONG LengthTransferred, BOOL Wait);
BOOL WINAPI WinUsb_SetPipePolicy(WINUSB_INTERFACE_HANDLE InterfaceHandle, UCHAR PipeID, ULONG PolicyType,
    ULONG ValueLength, PVOID Value);
BOOL WINAPI WinUsb_GetPipePolicy(WINUSB_INTERFACE_HANDLE InterfaceHandle, UCHAR PipeID, ULONG PolicyType,
    PULONG ValueLength, PVOID Value);
BOOL WINAPI WinUsb_QueryPipe(WINUSB_INTERFACE_HANDLE InterfaceHandle, UCHAR AlternateInterfaceNumber,
    UCHAR PipeIndex, PWINUSB_PIPE_INFORMATION PipeInformation);
BOOL WINAPI WinUsb_GetAssociatedInterface(WINUSB_INTERFACE_HANDLE InterfaceHandle, UCHAR AssociatedInterfaceIndex,
    PWINUSB_INTERFACE_HANDLE AssociatedInterfaceHandle);
BOOL WINAPI WinUsb_GetDescriptor(WINUSB_INTERFACE_HANDLE InterfaceHandle, UCHAR DescriptorType,
    UCHAR Index, USHORT LanguageID, PUCHAR Buffer, ULONG BufferLength, PULONG LengthTransferred);
BOOL WINAPI WinUsb_SetCurrentAlternateSetting(WINUSB_INTERFACE_HANDLE InterfaceHandle, UCHAR SettingNumber);
BOOL WINAPI WinUsb_GetCurrentAlternateSetting(WINUSB_INTERFACE_HANDLE InterfaceHandle, PUCHAR SettingNumber);
PUSB_INTERFACE_DESCRIPTOR WINAPI WinUsb_ParseConfigurationDescriptor(PUSB_CONFIGURATION_DESCRIPTOR ConfigurationDescriptor,
    UCHAR InterfaceNumber, UCHAR AlternateSetting);
BOOL WINAPI WinUsb_QueryInterfaceSettings(WINUSB_INTERFACE_HANDLE InterfaceHandle, UCHAR AlternateInterfaceNumber,
    PUSB_INTERFACE_DESCRIPTOR UsbAltInterfaceDescriptor);
PUSB_COMMON_DESCRIPTOR WINAPI WinUsb_ParseDescriptors(PVOID DescriptorBuffer, ULONG TotalLength,
    PVOID StartPosition, LONG DescriptorType);
BOOL WINAPI WinUsb_SetPowerPolicy(WINUSB_INTERFACE_HANDLE InterfaceHandle, ULONG PolicyType,
    ULONG ValueLength, PVOID Value);
BOOL WINAPI WinUsb_GetPowerPolicy(WINUSB_INTERFACE_HANDLE InterfaceHandle, ULONG PolicyType,
    PULONG ValueLength, PVOID Value);
BOOL WINAPI WinUsb_QueryDeviceInformation(WINUSB_INTERFACE_HANDLE InterfaceHandle, ULONG InformationType,
    PULONG BufferLength, PVOID Buffer);

#ifdef __cplusplus
}
#endif

#endif /* _WINUSB_H_ */
