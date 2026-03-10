/*
 * WinUSB API tests
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA
 */

#include <stdarg.h>
#include "windef.h"
#include "winbase.h"
#include "winuser.h"
#include "winusb.h"
#include "setupapi.h"
#include "wine/test.h"

#include "initguid.h"
#include "ddk/usbiodef.h"

static BOOL (WINAPI *pWinUsb_Free)(WINUSB_INTERFACE_HANDLE);
static BOOL (WINAPI *pWinUsb_Initialize)(HANDLE, WINUSB_INTERFACE_HANDLE *);
static BOOL (WINAPI *pWinUsb_SetPipePolicy)(WINUSB_INTERFACE_HANDLE, UCHAR, ULONG, ULONG, PVOID);
static BOOL (WINAPI *pWinUsb_GetPipePolicy)(WINUSB_INTERFACE_HANDLE, UCHAR, ULONG, PULONG, PVOID);
static BOOL (WINAPI *pWinUsb_QueryPipe)(WINUSB_INTERFACE_HANDLE, UCHAR, UCHAR, PWINUSB_PIPE_INFORMATION);
static BOOL (WINAPI *pWinUsb_ResetPipe)(WINUSB_INTERFACE_HANDLE, UCHAR);
static BOOL (WINAPI *pWinUsb_FlushPipe)(WINUSB_INTERFACE_HANDLE, UCHAR);
static BOOL (WINAPI *pWinUsb_GetDescriptor)(WINUSB_INTERFACE_HANDLE, UCHAR, UCHAR, ULONG, void *, ULONG, ULONG *);

static void test_WinUsb_Free(void)
{
    BOOL ret;

    ret = pWinUsb_Free(NULL);
    ok(ret == TRUE, "WinUsb_Free(NULL) returned %d\n", ret);
}

static void test_WinUsb_Initialize(void)
{
    BOOL ret;
    WINUSB_INTERFACE_HANDLE iface = NULL;

    ret = pWinUsb_Initialize(INVALID_HANDLE_VALUE, &iface);
    ok(ret == FALSE, "WinUsb_Initialize(INVALID_HANDLE_VALUE) returned %d\n", ret);
    ok(iface == NULL, "interface handle should be NULL on failure, got %p\n", iface);

    ret = pWinUsb_Initialize(NULL, &iface);
    ok(ret == FALSE, "WinUsb_Initialize(NULL) returned %d\n", ret);
}

static void test_WinUsb_invalid_handle(void)
{
    ULONG len;
    UCHAR buf;
    WINUSB_PIPE_INFORMATION pipe_info;

    if (!pWinUsb_SetPipePolicy || !pWinUsb_GetPipePolicy || !pWinUsb_QueryPipe)
        return;

    ok(pWinUsb_SetPipePolicy(NULL, 0x81, 3, sizeof(ULONG), &buf) == FALSE,
       "WinUsb_SetPipePolicy(NULL) should return FALSE\n");
    len = 0;
    ok(pWinUsb_GetPipePolicy(NULL, 0x81, 3, &len, &buf) == FALSE,
       "WinUsb_GetPipePolicy(NULL) should return FALSE\n");
    ok(pWinUsb_QueryPipe(NULL, 0, 0, &pipe_info) == FALSE,
       "WinUsb_QueryPipe(NULL) should return FALSE\n");
}

static void test_WinUsb_ResetPipe_FlushPipe(void)
{
    if (!pWinUsb_ResetPipe || !pWinUsb_FlushPipe)
        return;

    ok(pWinUsb_ResetPipe(NULL, 0x81) == FALSE,
       "WinUsb_ResetPipe(NULL) should return FALSE\n");
    ok(pWinUsb_FlushPipe(NULL, 0x02) == FALSE,
       "WinUsb_FlushPipe(NULL) should return FALSE\n");
}

static void test_WinUsb_GetDescriptor(void)
{
    UCHAR buf[64];
    ULONG transferred;

    if (!pWinUsb_GetDescriptor)
        return;

    ok(pWinUsb_GetDescriptor(NULL, 0x01, 0, 0, buf, sizeof(buf), &transferred) == FALSE,
       "WinUsb_GetDescriptor(NULL) should return FALSE\n");
}

static void test_SetupAPI_enum_device_interface(void)
{
    HDEVINFO set;
    SP_DEVICE_INTERFACE_DATA iface = {sizeof(iface)};
    DWORD i;
    BOOL ret;

    set = SetupDiGetClassDevsW(&GUID_DEVINTERFACE_USB_DEVICE, NULL, NULL,
                               DIGCF_DEVICEINTERFACE | DIGCF_PRESENT);
    ok(set != INVALID_HANDLE_VALUE, "SetupDiGetClassDevsW failed, error %lu\n", GetLastError());
    if (set == INVALID_HANDLE_VALUE)
        return;

    for (i = 0; ; i++)
    {
        ret = SetupDiEnumDeviceInterfaces(set, NULL, &GUID_DEVINTERFACE_USB_DEVICE, i, &iface);
        if (!ret)
        {
            ok(GetLastError() == ERROR_NO_MORE_ITEMS, "SetupDiEnumDeviceInterfaces(%lu) failed, error %lu\n", i, GetLastError());
            break;
        }
    }
    SetupDiDestroyDeviceInfoList(set);
}

START_TEST(winusb)
{
    HMODULE mod;

    mod = LoadLibraryA("winusb.dll");
    ok(!!mod, "LoadLibrary(winusb.dll) failed\n");
    if (!mod) return;

    pWinUsb_Free = (void *)GetProcAddress(mod, "WinUsb_Free");
    pWinUsb_Initialize = (void *)GetProcAddress(mod, "WinUsb_Initialize");
    pWinUsb_SetPipePolicy = (void *)GetProcAddress(mod, "WinUsb_SetPipePolicy");
    pWinUsb_GetPipePolicy = (void *)GetProcAddress(mod, "WinUsb_GetPipePolicy");
    pWinUsb_QueryPipe = (void *)GetProcAddress(mod, "WinUsb_QueryPipe");
    pWinUsb_ResetPipe = (void *)GetProcAddress(mod, "WinUsb_ResetPipe");
    pWinUsb_FlushPipe = (void *)GetProcAddress(mod, "WinUsb_FlushPipe");
    pWinUsb_GetDescriptor = (void *)GetProcAddress(mod, "WinUsb_GetDescriptor");
    ok(!!pWinUsb_Free, "WinUsb_Free not found\n");
    ok(!!pWinUsb_Initialize, "WinUsb_Initialize not found\n");
    if (!pWinUsb_Free || !pWinUsb_Initialize)
    {
        FreeLibrary(mod);
        return;
    }

    test_WinUsb_Free();
    test_WinUsb_Initialize();
    test_WinUsb_invalid_handle();
    test_WinUsb_ResetPipe_FlushPipe();
    test_WinUsb_GetDescriptor();
    test_SetupAPI_enum_device_interface();

    FreeLibrary(mod);
}
