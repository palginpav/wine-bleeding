/* WinRT Windows.Devices.Usb UsbDevice Implementation
 *
 * Copyright (C) 2023 Mohamad Al-Jaf
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

#include "private.h"
#include "wine/debug.h"
#include <ddk/usb100.h>

WINE_DEFAULT_DEBUG_CHANNEL(usb);

#define USB_REQUEST_GET_DESCRIPTOR 0x06

struct usb_device;
struct usb_configuration;
struct usb_bulk_in_pipe;
struct usb_bulk_out_pipe;
struct usb_interrupt_in_pipe;
struct usb_interrupt_out_pipe;
static HRESULT usb_configuration_create( struct usb_device *device, IUsbConfiguration **out );
static HRESULT WINAPI usb_device_get_Configuration( IUsbDevice *iface, IUsbConfiguration **value );
static HRESULT usb_configuration_descriptor_create( const USB_CONFIGURATION_DESCRIPTOR *raw,
        IUsbConfigurationDescriptor **out );
static HRESULT usb_configuration_ensure_raw_descriptor( struct usb_configuration *impl );
static HRESULT usb_descriptor_create( const BYTE *data, BYTE length, IUsbDescriptor **out );
static HRESULT usb_descriptor_vector_view_create( IUsbDescriptor **items, UINT32 count,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor **out );
static HRESULT usb_interface_create( struct usb_device *device, const BYTE *start, const BYTE *end, IUsbInterface **out );
static HRESULT usb_interface_setting_create( struct usb_device *device, const BYTE *start, const BYTE *end,
    IUsbInterfaceSetting **out );
static HRESULT usb_interface_settings_view_create( IUsbInterfaceSetting **items, UINT32 count,
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSetting **out );

struct usb_device_statics
{
    IActivationFactory IActivationFactory_iface;
    IUsbDeviceStatics IUsbDeviceStatics_iface;
    LONG ref;
};

static inline struct usb_device_statics *impl_from_IActivationFactory( IActivationFactory *iface )
{
    return CONTAINING_RECORD( iface, struct usb_device_statics, IActivationFactory_iface );
}

static HRESULT WINAPI factory_QueryInterface( IActivationFactory *iface, REFIID iid, void **out )
{
    struct usb_device_statics *impl = impl_from_IActivationFactory( iface );

    TRACE( "iface %p, iid %s, out %p.\n", iface, debugstr_guid( iid ), out );

    if (IsEqualGUID( iid, &IID_IUnknown ) ||
        IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAgileObject ) ||
        IsEqualGUID( iid, &IID_IActivationFactory ))
    {
        *out = &impl->IActivationFactory_iface;
        IInspectable_AddRef( *out );
        return S_OK;
    }

    if (IsEqualGUID( iid, &IID_IUsbDeviceStatics ))
    {
        *out = &impl->IUsbDeviceStatics_iface;
        IInspectable_AddRef( *out );
        return S_OK;
    }

    FIXME( "%s not implemented, returning E_NOINTERFACE.\n", debugstr_guid( iid ) );
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI factory_AddRef( IActivationFactory *iface )
{
    struct usb_device_statics *impl = impl_from_IActivationFactory( iface );
    ULONG ref = InterlockedIncrement( &impl->ref );
    TRACE( "iface %p increasing refcount to %lu.\n", iface, ref );
    return ref;
}

static ULONG WINAPI factory_Release( IActivationFactory *iface )
{
    struct usb_device_statics *impl = impl_from_IActivationFactory( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    TRACE( "iface %p decreasing refcount to %lu.\n", iface, ref );
    return ref;
}

static HRESULT WINAPI factory_GetIids( IActivationFactory *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IActivationFactory };
    IID *out;
    ULONG i;

    TRACE( "iface %p, iid_count %p, iids %p.\n", iface, iid_count, iids );
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}

static HRESULT WINAPI factory_GetRuntimeClassName( IActivationFactory *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbDevice";
    TRACE( "iface %p, class_name %p.\n", iface, class_name );
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}

static HRESULT WINAPI factory_GetTrustLevel( IActivationFactory *iface, TrustLevel *trust_level )
{
    TRACE( "iface %p, trust_level %p.\n", iface, trust_level );
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI factory_ActivateInstance( IActivationFactory *iface, IInspectable **instance )
{
    TRACE( "iface %p, instance %p.\n", iface, instance );
    if (!instance) return E_INVALIDARG;
    /* UsbDevice is a statics class; instances are obtained via GetFromIdAsync, not ActivateInstance. */
    return E_ILLEGAL_METHOD_CALL;
}

static const struct IActivationFactoryVtbl factory_vtbl =
{
    factory_QueryInterface,
    factory_AddRef,
    factory_Release,
    /* IInspectable methods */
    factory_GetIids,
    factory_GetRuntimeClassName,
    factory_GetTrustLevel,
    /* IActivationFactory methods */
    factory_ActivateInstance,
};

DEFINE_IINSPECTABLE( usb_device_statics, IUsbDeviceStatics, struct usb_device_statics, IActivationFactory_iface )

static void format_guid(const GUID *g, WCHAR *buf)
{
    swprintf(buf, 39, L"{%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x}",
             (unsigned)g->Data1, g->Data2, g->Data3,
             g->Data4[0], g->Data4[1], g->Data4[2], g->Data4[3],
             g->Data4[4], g->Data4[5], g->Data4[6], g->Data4[7]);
}

static HRESULT WINAPI usb_device_statics_GetDeviceSelector( IUsbDeviceStatics *iface, UINT32 vendor,
                                                            UINT32 product, GUID class, HSTRING *value )
{
    static const WCHAR *format = L"System.Devices.InterfaceClassGuid:=\"%s\""
                                 L" AND System.Devices.InterfaceEnabled:=System.StructuredQueryType.Boolean#True"
                                 L" AND System.DeviceInterface.WinUsb.UsbVendorId:=%d"
                                 L" AND System.DeviceInterface.WinUsb.UsbProductId:=%d";
    WCHAR guid_str[39];
    WCHAR buffer[320];
    HRESULT hr;

    TRACE( "iface %p, vendor %u, product %u, class %s, value %p.\n", iface, vendor, product, debugstr_guid(&class), value );
    if (!value) return E_INVALIDARG;

    format_guid(&class, guid_str);
    swprintf(buffer, ARRAYSIZE(buffer), format, guid_str, (INT32)vendor, (INT32)product);
    hr = WindowsCreateString(buffer, wcslen(buffer), value);
    return hr;
}

static HRESULT WINAPI usb_device_statics_GetDeviceSelectorGuidOnly( IUsbDeviceStatics *iface, GUID class, HSTRING *value )
{
    static const WCHAR *format = L"System.Devices.InterfaceClassGuid:=\"%s\""
                                 L" AND System.Devices.InterfaceEnabled:=System.StructuredQueryType.Boolean#True";
    WCHAR guid_str[39];
    WCHAR buffer[120];
    HRESULT hr;

    TRACE( "iface %p, class %s, value %p.\n", iface, debugstr_guid(&class), value );
    if (!value) return E_INVALIDARG;

    format_guid(&class, guid_str);
    swprintf(buffer, ARRAYSIZE(buffer), format, guid_str);
    hr = WindowsCreateString(buffer, wcslen(buffer), value);
    return hr;
}

static HRESULT WINAPI usb_device_statics_GetDeviceSelectorVidPidOnly( IUsbDeviceStatics *iface, UINT32 vendor,
                                                                      UINT32 product, HSTRING *value )
{
    static const WCHAR *format = L"System.Devices.InterfaceClassGuid:=\"{DEE824EF-729B-4A0E-9C14-B7117D33A817}\""
                                 L" AND System.Devices.InterfaceEnabled:=System.StructuredQueryType.Boolean#True"
                                 L" AND System.DeviceInterface.WinUsb.UsbVendorId:=%d"
                                 L" AND System.DeviceInterface.WinUsb.UsbProductId:=%d";
    WCHAR buffer[254 + 20];
    HRESULT hr;

    TRACE( "iface %p, vendor %d, product %d, value %p.\n", iface, vendor, product, value );

    if (!value) return E_INVALIDARG;

    swprintf( buffer, ARRAYSIZE(buffer), format, (INT32)vendor, (INT32)product );
    hr = WindowsCreateString( buffer, wcslen(buffer), value );

    TRACE( "Returning value = %s\n", debugstr_hstring(*value) );
    return hr;
}

static HRESULT WINAPI usb_device_statics_GetDeviceClassSelector( IUsbDeviceStatics *iface, IUsbDeviceClass *class, HSTRING *value )
{
    BYTE class_code;
    GUID class_guid;
    HRESULT hr;

    TRACE( "iface %p, class %p, value %p.\n", iface, class, value );
    if (!class || !value) return E_INVALIDARG;

    hr = IUsbDeviceClass_get_ClassCode( class, &class_code );
    if (FAILED( hr )) return hr;

    /* Map USB interface class code to device interface GUID for AQS. Use WinUSB GUID as default. */
    if (class_code == 0x03)
    {
        /* HID */
        class_guid.Data1 = 0x4d1e55b2;
        class_guid.Data2 = 0xf16f;
        class_guid.Data3 = 0x11cf;
        class_guid.Data4[0] = 0x88; class_guid.Data4[1] = 0xcb; class_guid.Data4[2] = 0x00;
        class_guid.Data4[3] = 0x11; class_guid.Data4[4] = 0x11; class_guid.Data4[5] = 0x00;
        class_guid.Data4[6] = 0x00; class_guid.Data4[7] = 0x30;
    }
    else if (class_code == 0x08)
    {
        /* Mass storage */
        class_guid.Data1 = 0x53f56307;
        class_guid.Data2 = 0xb6bf;
        class_guid.Data3 = 0x11d0;
        class_guid.Data4[0] = 0x94; class_guid.Data4[1] = 0xf2; class_guid.Data4[2] = 0x00;
        class_guid.Data4[3] = 0xa0; class_guid.Data4[4] = 0xc9; class_guid.Data4[5] = 0x0e;
        class_guid.Data4[6] = 0xfb; class_guid.Data4[7] = 0x8b;
    }
    else
    {
        /* WinUSB / generic */
        class_guid.Data1 = 0xdee824ef;
        class_guid.Data2 = 0x729b;
        class_guid.Data3 = 0x4a0e;
        class_guid.Data4[0] = 0x9c; class_guid.Data4[1] = 0x14; class_guid.Data4[2] = 0xb7;
        class_guid.Data4[3] = 0x11; class_guid.Data4[4] = 0x7d; class_guid.Data4[5] = 0x33;
        class_guid.Data4[6] = 0xa8; class_guid.Data4[7] = 0x17;
    }
    return usb_device_statics_GetDeviceSelectorGuidOnly( iface, class_guid, value );
}

static HRESULT usb_device_async_create( HSTRING id, IAsyncOperation_UsbDevice **operation );

static HRESULT WINAPI usb_device_statics_FromIdAsync( IUsbDeviceStatics *iface, HSTRING id, IAsyncOperation_UsbDevice **operation )
{
    TRACE( "iface %p, id %s, operation %p.\n", iface, debugstr_hstring(id), operation );

    if (!id || !operation) return E_INVALIDARG;

    return usb_device_async_create( id, operation );
}

static const struct IUsbDeviceStaticsVtbl usb_device_statics_vtbl =
{
    usb_device_statics_QueryInterface,
    usb_device_statics_AddRef,
    usb_device_statics_Release,
    /* IInspectable methods */
    usb_device_statics_GetIids,
    usb_device_statics_GetRuntimeClassName,
    usb_device_statics_GetTrustLevel,
    /* IUsbDeviceStatics methods */
    usb_device_statics_GetDeviceSelector,
    usb_device_statics_GetDeviceSelectorGuidOnly,
    usb_device_statics_GetDeviceSelectorVidPidOnly,
    usb_device_statics_GetDeviceClassSelector,
    usb_device_statics_FromIdAsync,
};

static struct usb_device_statics usb_device_statics =
{
    {&factory_vtbl},
    {&usb_device_statics_vtbl},
    1,
};

IActivationFactory *usb_device_factory = &usb_device_statics.IActivationFactory_iface;

struct usb_device
{
    IUsbDevice IUsbDevice_iface;
    IUsbDeviceDescriptor *device_descriptor;
    IUsbConfiguration *configuration;
    HSTRING id;
    HANDLE handle;
    WINUSB_INTERFACE_HANDLE winusb;
    LONG ref;
};

static inline struct usb_device *impl_from_IUsbDevice( IUsbDevice *iface )
{
    return CONTAINING_RECORD( iface, struct usb_device, IUsbDevice_iface );
}

static HRESULT WINAPI usb_device_QueryInterface( IUsbDevice *iface, REFIID iid, void **out )
{
    TRACE( "iface %p, iid %s, out %p.\n", iface, debugstr_guid( iid ), out );

    if (IsEqualGUID( iid, &IID_IUnknown ) ||
        IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAgileObject ) ||
        IsEqualGUID( iid, &IID_IUsbDevice ))
    {
        IUsbDevice_AddRef( iface );
        *out = iface;
        return S_OK;
    }

    *out = NULL;
    FIXME( "%s not implemented, returning E_NOINTERFACE.\n", debugstr_guid( iid ) );
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_device_AddRef( IUsbDevice *iface )
{
    struct usb_device *impl = impl_from_IUsbDevice( iface );
    ULONG ref = InterlockedIncrement( &impl->ref );
    TRACE( "iface %p increasing refcount to %lu.\n", iface, ref );
    return ref;
}

static ULONG WINAPI usb_device_Release( IUsbDevice *iface )
{
    struct usb_device *impl = impl_from_IUsbDevice( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );

    TRACE( "iface %p decreasing refcount to %lu.\n", iface, ref );

    if (!ref)
    {
        if (impl->device_descriptor) IUsbDeviceDescriptor_Release( impl->device_descriptor );
        if (impl->configuration) IUsbConfiguration_Release( impl->configuration );
        if (impl->winusb) WinUsb_Free( impl->winusb );
        if (impl->handle && impl->handle != INVALID_HANDLE_VALUE) CloseHandle( impl->handle );
        WindowsDeleteString( impl->id );
        free( impl );
    }

    return ref;
}

static HRESULT WINAPI usb_device_GetIids( IUsbDevice *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IUsbDevice };
    IID *out;
    ULONG i;

    TRACE( "iface %p, iid_count %p, iids %p.\n", iface, iid_count, iids );
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}

static HRESULT WINAPI usb_device_GetRuntimeClassName( IUsbDevice *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbDevice";

    TRACE( "iface %p, class_name %p.\n", iface, class_name );

    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}

static HRESULT WINAPI usb_device_GetTrustLevel( IUsbDevice *iface, TrustLevel *trust_level )
{
    TRACE( "iface %p, trust_level %p.\n", iface, trust_level );
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI usb_device_SendControlOutTransferAsync( IUsbDevice *iface,
        IUsbSetupPacket *packet, IBuffer *buffer, __FIAsyncOperation_1_UINT32 **operation )
{
    struct usb_device *impl = impl_from_IUsbDevice( iface );
    IUsbControlRequestType *req_type = NULL;
    WINUSB_SETUP_PACKET setup;
    BYTE bmRequestType;
    BYTE request;
    UINT32 value, index, length;
    HRESULT hr;
    BYTE *data = NULL;
    ULONG transferred = 0;
    BOOL ret;

    if (!packet || !operation) return E_INVALIDARG;
    *operation = NULL;

    hr = IUsbSetupPacket_get_RequestType( packet, &req_type );
    if (FAILED( hr )) return hr;
    hr = IUsbControlRequestType_get_AsByte( req_type, &bmRequestType );
    IUsbControlRequestType_Release( req_type );
    if (FAILED( hr )) return hr;

    hr = IUsbSetupPacket_get_Request( packet, &request );
    if (FAILED( hr )) return hr;
    hr = IUsbSetupPacket_get_Value( packet, &value );
    if (FAILED( hr )) return hr;
    hr = IUsbSetupPacket_get_Index( packet, &index );
    if (FAILED( hr )) return hr;
    hr = IUsbSetupPacket_get_Length( packet, &length );
    if (FAILED( hr )) return hr;

    setup.RequestType = bmRequestType;
    setup.Request = request;
    setup.Value = (USHORT)value;
    setup.Index = (USHORT)index;
    setup.Length = (USHORT)length;

    if (buffer && length)
    {
        UINT32 buf_len = 0;
        IBufferByteAccess *byte_access = NULL;
        BYTE *buf_data = NULL;

        hr = IBuffer_get_Length( buffer, &buf_len );
        if (FAILED( hr )) return hr;
        if (buf_len)
        {
            hr = IBuffer_QueryInterface( buffer, &IID_IBufferByteAccess, (void **)&byte_access );
            if (FAILED( hr )) return hr;
            hr = IBufferByteAccess_Buffer( byte_access, (byte **)&buf_data );
            IBufferByteAccess_Release( byte_access );
            if (FAILED( hr )) return hr;
            data = buf_data;
            if (buf_len < length) length = buf_len;
        }
    }

    ret = WinUsb_ControlTransfer( impl->winusb, &setup, data, length, &transferred, NULL );
    if (!ret)
        return HRESULT_FROM_WIN32( GetLastError() );

    return async_uint32_create( transferred, operation );
}

static HRESULT WINAPI usb_device_SendControlOutTransferAsyncNoBuffer( IUsbDevice *iface,
        IUsbSetupPacket *packet, __FIAsyncOperation_1_UINT32 **operation )
{
    return usb_device_SendControlOutTransferAsync( iface, packet, NULL, operation );
}

static HRESULT WINAPI usb_device_SendControlInTransferAsync( IUsbDevice *iface,
        IUsbSetupPacket *packet, IBuffer *buffer,
        __FIAsyncOperation_1_Windows__CStorage__CStreams__CIBuffer **operation )
{
    struct usb_device *impl = impl_from_IUsbDevice( iface );
    IUsbControlRequestType *req_type = NULL;
    WINUSB_SETUP_PACKET setup;
    BYTE bmRequestType;
    BYTE request;
    UINT32 value, index, length;
    HRESULT hr;
    BYTE *data = NULL;
    ULONG transferred = 0;
    BOOL ret;

    if (!packet || !buffer || !operation) return E_INVALIDARG;
    *operation = NULL;

    hr = IUsbSetupPacket_get_RequestType( packet, &req_type );
    if (FAILED( hr )) return hr;
    hr = IUsbControlRequestType_get_AsByte( req_type, &bmRequestType );
    IUsbControlRequestType_Release( req_type );
    if (FAILED( hr )) return hr;

    hr = IUsbSetupPacket_get_Request( packet, &request );
    if (FAILED( hr )) return hr;
    hr = IUsbSetupPacket_get_Value( packet, &value );
    if (FAILED( hr )) return hr;
    hr = IUsbSetupPacket_get_Index( packet, &index );
    if (FAILED( hr )) return hr;
    hr = IUsbSetupPacket_get_Length( packet, &length );
    if (FAILED( hr )) return hr;

    setup.RequestType = bmRequestType | 0x80;
    setup.Request = request;
    setup.Value = (USHORT)value;
    setup.Index = (USHORT)index;
    setup.Length = (USHORT)length;

    {
        IBufferByteAccess *byte_access = NULL;
        hr = IBuffer_QueryInterface( buffer, &IID_IBufferByteAccess, (void **)&byte_access );
        if (FAILED( hr )) return hr;
        hr = IBufferByteAccess_Buffer( byte_access, (byte **)&data );
        IBufferByteAccess_Release( byte_access );
        if (FAILED( hr )) return hr;
    }

    ret = WinUsb_ControlTransfer( impl->winusb, &setup, data, length, &transferred, NULL );
    if (!ret)
        return HRESULT_FROM_WIN32( GetLastError() );

    return async_buffer_from_existing( buffer, operation );
}

static HRESULT WINAPI usb_device_SendControlInTransferAsyncNoBuffer( IUsbDevice *iface,
        IUsbSetupPacket *packet, __FIAsyncOperation_1_Windows__CStorage__CStreams__CIBuffer **operation )
{
    IBuffer *buffer;
    HRESULT hr;

    if (!operation) return E_INVALIDARG;
    *operation = NULL;

    hr = Buffer_Create( 0, &buffer );
    if (FAILED( hr )) return hr;

    hr = usb_device_SendControlInTransferAsync( iface, packet, buffer, operation );
    IBuffer_Release( buffer );
    return hr;
}

/* CLEAR_FEATURE(ENDPOINT_HALT) to clear stall on an endpoint */
static HRESULT usb_clear_endpoint_stall( struct usb_device *device, UCHAR endpoint_address )
{
    WINUSB_SETUP_PACKET setup;
    BOOL ret;

    if (!device || !device->winusb) return E_INVALIDARG;
    setup.RequestType = 0x02;  /* recipient: endpoint */
    setup.Request = 0x01;      /* CLEAR_FEATURE */
    setup.Value = 0;           /* ENDPOINT_HALT */
    setup.Index = endpoint_address;
    setup.Length = 0;
    ret = WinUsb_ControlTransfer( device->winusb, &setup, NULL, 0, NULL, NULL );
    if (!ret) return HRESULT_FROM_WIN32( GetLastError() );
    return S_OK;
}

static HRESULT WINAPI usb_device_get_DefaultInterface( IUsbDevice *iface, IUsbInterface **value )
{
    IUsbConfiguration *config = NULL;
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface *interfaces = NULL;
    UINT32 size = 0;
    HRESULT hr;

    if (!value) return E_INVALIDARG;
    *value = NULL;

    hr = usb_device_get_Configuration( iface, &config );
    if (FAILED( hr )) return hr;
    hr = IUsbConfiguration_get_UsbInterfaces( config, &interfaces );
    if (FAILED( hr ))
    {
        IUsbConfiguration_Release( config );
        return hr;
    }
    hr = __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface_get_Size( interfaces, &size );
    if (SUCCEEDED( hr ) && size > 0)
        hr = __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface_GetAt( interfaces, 0, value );

    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface_Release( interfaces );
    IUsbConfiguration_Release( config );
    return hr;
}

struct usb_device_descriptor_obj
{
    IUsbDeviceDescriptor IUsbDeviceDescriptor_iface;
    LONG ref;
    UINT32 bcd_usb;
    BYTE max_packet_size0;
    UINT32 vendor_id;
    UINT32 product_id;
    UINT32 bcd_device_revision;
    BYTE num_configurations;
};

static inline struct usb_device_descriptor_obj *impl_from_IUsbDeviceDescriptor( IUsbDeviceDescriptor *iface )
{
    return CONTAINING_RECORD( iface, struct usb_device_descriptor_obj, IUsbDeviceDescriptor_iface );
}

static HRESULT WINAPI usb_device_descriptor_QueryInterface( IUsbDeviceDescriptor *iface, REFIID iid, void **out )
{
    TRACE( "iface %p, iid %s, out %p.\n", iface, debugstr_guid( iid ), out );

    if (IsEqualGUID( iid, &IID_IUnknown ) ||
        IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAgileObject ) ||
        IsEqualGUID( iid, &IID_IUsbDeviceDescriptor ))
    {
        IUsbDeviceDescriptor_AddRef( iface );
        *out = iface;
        return S_OK;
    }

    *out = NULL;
    FIXME( "%s not implemented, returning E_NOINTERFACE.\n", debugstr_guid( iid ) );
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_device_descriptor_AddRef( IUsbDeviceDescriptor *iface )
{
    struct usb_device_descriptor_obj *impl = impl_from_IUsbDeviceDescriptor( iface );
    ULONG ref = InterlockedIncrement( &impl->ref );
    TRACE( "iface %p increasing refcount to %lu.\n", iface, ref );
    return ref;
}

static ULONG WINAPI usb_device_descriptor_Release( IUsbDeviceDescriptor *iface )
{
    struct usb_device_descriptor_obj *impl = impl_from_IUsbDeviceDescriptor( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );

    TRACE( "iface %p decreasing refcount to %lu.\n", iface, ref );

    if (!ref)
        free( impl );

    return ref;
}

static HRESULT WINAPI usb_device_descriptor_GetIids( IUsbDeviceDescriptor *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IUsbDeviceDescriptor };
    IID *out;
    ULONG i;

    TRACE( "iface %p, iid_count %p, iids %p.\n", iface, iid_count, iids );
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}

static HRESULT WINAPI usb_device_descriptor_GetRuntimeClassName( IUsbDeviceDescriptor *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbDeviceDescriptor";

    TRACE( "iface %p, class_name %p.\n", iface, class_name );

    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}

static HRESULT WINAPI usb_device_descriptor_GetTrustLevel( IUsbDeviceDescriptor *iface, TrustLevel *trust_level )
{
    TRACE( "iface %p, trust_level %p.\n", iface, trust_level );
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI usb_device_descriptor_get_BcdUsb( IUsbDeviceDescriptor *iface, UINT32 *value )
{
    struct usb_device_descriptor_obj *impl = impl_from_IUsbDeviceDescriptor( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->bcd_usb;
    return S_OK;
}

static HRESULT WINAPI usb_device_descriptor_get_MaxPacketSize0( IUsbDeviceDescriptor *iface, BYTE *value )
{
    struct usb_device_descriptor_obj *impl = impl_from_IUsbDeviceDescriptor( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->max_packet_size0;
    return S_OK;
}

static HRESULT WINAPI usb_device_descriptor_get_VendorId( IUsbDeviceDescriptor *iface, UINT32 *value )
{
    struct usb_device_descriptor_obj *impl = impl_from_IUsbDeviceDescriptor( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->vendor_id;
    return S_OK;
}

static HRESULT WINAPI usb_device_descriptor_get_ProductId( IUsbDeviceDescriptor *iface, UINT32 *value )
{
    struct usb_device_descriptor_obj *impl = impl_from_IUsbDeviceDescriptor( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->product_id;
    return S_OK;
}

static HRESULT WINAPI usb_device_descriptor_get_BcdDeviceRevision( IUsbDeviceDescriptor *iface, UINT32 *value )
{
    struct usb_device_descriptor_obj *impl = impl_from_IUsbDeviceDescriptor( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->bcd_device_revision;
    return S_OK;
}

static HRESULT WINAPI usb_device_descriptor_get_NumberOfConfigurations( IUsbDeviceDescriptor *iface, BYTE *value )
{
    struct usb_device_descriptor_obj *impl = impl_from_IUsbDeviceDescriptor( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->num_configurations;
    return S_OK;
}

static const IUsbDeviceDescriptorVtbl usb_device_descriptor_vtbl =
{
    usb_device_descriptor_QueryInterface,
    usb_device_descriptor_AddRef,
    usb_device_descriptor_Release,
    usb_device_descriptor_GetIids,
    usb_device_descriptor_GetRuntimeClassName,
    usb_device_descriptor_GetTrustLevel,
    usb_device_descriptor_get_BcdUsb,
    usb_device_descriptor_get_MaxPacketSize0,
    usb_device_descriptor_get_VendorId,
    usb_device_descriptor_get_ProductId,
    usb_device_descriptor_get_BcdDeviceRevision,
    usb_device_descriptor_get_NumberOfConfigurations,
};

static HRESULT usb_device_descriptor_create( const USB_DEVICE_DESCRIPTOR *d, IUsbDeviceDescriptor **out )
{
    struct usb_device_descriptor_obj *impl;

    if (!out) return E_INVALIDARG;
    *out = NULL;

    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IUsbDeviceDescriptor_iface.lpVtbl = &usb_device_descriptor_vtbl;
    impl->ref = 1;
    impl->bcd_usb = d->bcdUSB;
    impl->max_packet_size0 = d->bMaxPacketSize0;
    impl->vendor_id = d->idVendor;
    impl->product_id = d->idProduct;
    impl->bcd_device_revision = d->bcdDevice;
    impl->num_configurations = d->bNumConfigurations;

    *out = &impl->IUsbDeviceDescriptor_iface;
    return S_OK;
}

static HRESULT WINAPI usb_device_get_DeviceDescriptor( IUsbDevice *iface, IUsbDeviceDescriptor **value )
{
    struct usb_device *impl = impl_from_IUsbDevice( iface );
    HRESULT hr;

    if (!value) return E_INVALIDARG;
    *value = NULL;

    if (!impl->device_descriptor)
    {
        BYTE desc[18];
        ULONG transferred = 0;
        WINUSB_SETUP_PACKET setup;
        BOOL ret;

        setup.RequestType = 0x80;
        setup.Request = 0x06;
        setup.Value = (USB_DEVICE_DESCRIPTOR_TYPE << 8);
        setup.Index = 0;
        setup.Length = sizeof(desc);

        ret = WinUsb_ControlTransfer( impl->winusb, &setup, desc, sizeof(desc), &transferred, NULL );
        if (!ret)
            return HRESULT_FROM_WIN32( GetLastError() );
        if (transferred < sizeof(USB_DEVICE_DESCRIPTOR))
            return E_FAIL;

        hr = usb_device_descriptor_create( (USB_DEVICE_DESCRIPTOR *)desc, &impl->device_descriptor );
        if (FAILED( hr )) return hr;
    }

    *value = impl->device_descriptor;
    IUsbDeviceDescriptor_AddRef( *value );
    return S_OK;
}

static HRESULT WINAPI usb_device_get_Configuration( IUsbDevice *iface, IUsbConfiguration **value )
{
    struct usb_device *impl = impl_from_IUsbDevice( iface );

    if (!value) return E_INVALIDARG;
    *value = NULL;

    if (!impl->configuration)
    {
        HRESULT hr = usb_configuration_create( impl, &impl->configuration );
        if (FAILED( hr )) return hr;
    }

    *value = impl->configuration;
    IUsbConfiguration_AddRef( *value );
    return S_OK;
}

static const IUsbDeviceVtbl usb_device_vtbl =
{
    usb_device_QueryInterface,
    usb_device_AddRef,
    usb_device_Release,
    usb_device_GetIids,
    usb_device_GetRuntimeClassName,
    usb_device_GetTrustLevel,
    usb_device_SendControlOutTransferAsync,
    usb_device_SendControlOutTransferAsyncNoBuffer,
    usb_device_SendControlInTransferAsync,
    usb_device_SendControlInTransferAsyncNoBuffer,
    usb_device_get_DefaultInterface,
    usb_device_get_DeviceDescriptor,
    usb_device_get_Configuration,
};

struct usb_configuration
{
    IUsbConfiguration IUsbConfiguration_iface;
    LONG ref;
    struct usb_device *device;
    IUsbConfigurationDescriptor *configuration_descriptor;
    BYTE *raw_config;
    ULONG raw_config_len;
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface *interfaces;
};

static inline struct usb_configuration *impl_from_IUsbConfiguration( IUsbConfiguration *iface )
{
    return CONTAINING_RECORD( iface, struct usb_configuration, IUsbConfiguration_iface );
}

struct usb_interface_vector_view
{
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface IVectorView_iface;
    LONG ref;
    UINT32 size;
    IUsbInterface **items;
};

static inline struct usb_interface_vector_view *impl_from_usb_interface_vector_view(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface *iface )
{
    return CONTAINING_RECORD( iface, struct usb_interface_vector_view, IVectorView_iface );
}

struct usb_bulk_in_pipes
{
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe IVectorView_iface;
    LONG ref;
    UINT32 size;
    IUsbBulkInPipe **items;
};

static inline struct usb_bulk_in_pipes *impl_from_usb_bulk_in_pipes(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe *iface )
{
    return CONTAINING_RECORD( iface, struct usb_bulk_in_pipes, IVectorView_iface );
}

struct usb_bulk_in_pipe
{
    IUsbBulkInPipe IUsbBulkInPipe_iface;
    LONG ref;
    struct usb_device *device;
    UCHAR endpoint_address;
    UINT32 max_transfer_size;
    UsbReadOptions read_options;
};

static inline struct usb_bulk_in_pipe *impl_from_IUsbBulkInPipe( IUsbBulkInPipe *iface )
{
    return CONTAINING_RECORD( iface, struct usb_bulk_in_pipe, IUsbBulkInPipe_iface );
}

struct usb_bulk_out_pipes
{
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe IVectorView_iface;
    LONG ref;
    UINT32 size;
    IUsbBulkOutPipe **items;
};

static inline struct usb_bulk_out_pipes *impl_from_usb_bulk_out_pipes(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe *iface )
{
    return CONTAINING_RECORD( iface, struct usb_bulk_out_pipes, IVectorView_iface );
}

struct usb_bulk_out_pipe
{
    IUsbBulkOutPipe IUsbBulkOutPipe_iface;
    LONG ref;
    struct usb_device *device;
    UCHAR endpoint_address;
    UINT32 max_packet_size;
    UsbWriteOptions write_options;
};

static inline struct usb_bulk_out_pipe *impl_from_IUsbBulkOutPipe( IUsbBulkOutPipe *iface )
{
    return CONTAINING_RECORD( iface, struct usb_bulk_out_pipe, IUsbBulkOutPipe_iface );
}

static HRESULT usb_bulk_in_endpoint_descriptor_create( struct usb_bulk_in_pipe *pipe,
    IUsbBulkInEndpointDescriptor **out );
static HRESULT usb_bulk_out_endpoint_descriptor_create( struct usb_bulk_out_pipe *pipe,
    IUsbBulkOutEndpointDescriptor **out );
static HRESULT usb_interrupt_in_endpoint_descriptor_create( struct usb_interrupt_in_pipe *pipe,
    IUsbInterruptInEndpointDescriptor **out );
static HRESULT usb_interrupt_out_endpoint_descriptor_create( struct usb_interrupt_out_pipe *pipe,
    IUsbInterruptOutEndpointDescriptor **out );

/* UsbBulkInEndpointDescriptor */
struct usb_bulk_in_endpoint_descriptor
{
    IUsbBulkInEndpointDescriptor IUsbBulkInEndpointDescriptor_iface;
    LONG ref;
    IUsbBulkInPipe *pipe;
    UINT32 max_packet_size;
    BYTE endpoint_number;
};

static inline struct usb_bulk_in_endpoint_descriptor *impl_from_IUsbBulkInEndpointDescriptor(
    IUsbBulkInEndpointDescriptor *iface )
{
    return CONTAINING_RECORD( iface, struct usb_bulk_in_endpoint_descriptor, IUsbBulkInEndpointDescriptor_iface );
}

static HRESULT WINAPI usb_bulk_in_endpoint_descriptor_QueryInterface( IUsbBulkInEndpointDescriptor *iface, REFIID iid, void **out )
{
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IUsbBulkInEndpointDescriptor ))
    {
        *out = iface;
        IUsbBulkInEndpointDescriptor_AddRef( iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_bulk_in_endpoint_descriptor_AddRef( IUsbBulkInEndpointDescriptor *iface )
{
    return InterlockedIncrement( &impl_from_IUsbBulkInEndpointDescriptor( iface )->ref );
}

static ULONG WINAPI usb_bulk_in_endpoint_descriptor_Release( IUsbBulkInEndpointDescriptor *iface )
{
    struct usb_bulk_in_endpoint_descriptor *impl = impl_from_IUsbBulkInEndpointDescriptor( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref) { if (impl->pipe) IUsbBulkInPipe_Release( impl->pipe ); free( impl ); }
    return ref;
}

static HRESULT WINAPI usb_bulk_in_endpoint_descriptor_GetIids( IUsbBulkInEndpointDescriptor *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IUsbBulkInEndpointDescriptor };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}
static HRESULT WINAPI usb_bulk_in_endpoint_descriptor_GetRuntimeClassName( IUsbBulkInEndpointDescriptor *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbBulkInEndpointDescriptor";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI usb_bulk_in_endpoint_descriptor_GetTrustLevel( IUsbBulkInEndpointDescriptor *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI usb_bulk_in_endpoint_descriptor_get_MaxPacketSize( IUsbBulkInEndpointDescriptor *iface, UINT32 *value )
{
    if (!value) return E_INVALIDARG;
    *value = impl_from_IUsbBulkInEndpointDescriptor( iface )->max_packet_size;
    return S_OK;
}
static HRESULT WINAPI usb_bulk_in_endpoint_descriptor_get_EndpointNumber( IUsbBulkInEndpointDescriptor *iface, BYTE *value )
{
    if (!value) return E_INVALIDARG;
    *value = impl_from_IUsbBulkInEndpointDescriptor( iface )->endpoint_number;
    return S_OK;
}
static HRESULT WINAPI usb_bulk_in_endpoint_descriptor_get_Pipe( IUsbBulkInEndpointDescriptor *iface, IUsbBulkInPipe **value )
{
    struct usb_bulk_in_endpoint_descriptor *impl = impl_from_IUsbBulkInEndpointDescriptor( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->pipe;
    if (impl->pipe) IUsbBulkInPipe_AddRef( impl->pipe );
    return S_OK;
}

static const IUsbBulkInEndpointDescriptorVtbl usb_bulk_in_endpoint_descriptor_vtbl = {
    usb_bulk_in_endpoint_descriptor_QueryInterface,
    usb_bulk_in_endpoint_descriptor_AddRef,
    usb_bulk_in_endpoint_descriptor_Release,
    usb_bulk_in_endpoint_descriptor_GetIids,
    usb_bulk_in_endpoint_descriptor_GetRuntimeClassName,
    usb_bulk_in_endpoint_descriptor_GetTrustLevel,
    usb_bulk_in_endpoint_descriptor_get_MaxPacketSize,
    usb_bulk_in_endpoint_descriptor_get_EndpointNumber,
    usb_bulk_in_endpoint_descriptor_get_Pipe,
};

static HRESULT usb_bulk_in_endpoint_descriptor_create( struct usb_bulk_in_pipe *pipe,
    IUsbBulkInEndpointDescriptor **out )
{
    struct usb_bulk_in_endpoint_descriptor *impl;
    if (!out || !pipe) return E_INVALIDARG;
    *out = NULL;
    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IUsbBulkInEndpointDescriptor_iface.lpVtbl = &usb_bulk_in_endpoint_descriptor_vtbl;
    impl->ref = 1;
    impl->pipe = &pipe->IUsbBulkInPipe_iface;
    IUsbBulkInPipe_AddRef( impl->pipe );
    impl->max_packet_size = pipe->max_transfer_size;
    impl->endpoint_number = pipe->endpoint_address & 0x0f;
    *out = &impl->IUsbBulkInEndpointDescriptor_iface;
    return S_OK;
}

/* UsbBulkOutEndpointDescriptor */
struct usb_bulk_out_endpoint_descriptor
{
    IUsbBulkOutEndpointDescriptor IUsbBulkOutEndpointDescriptor_iface;
    LONG ref;
    IUsbBulkOutPipe *pipe;
    UINT32 max_packet_size;
    BYTE endpoint_number;
};

static inline struct usb_bulk_out_endpoint_descriptor *impl_from_IUsbBulkOutEndpointDescriptor(
    IUsbBulkOutEndpointDescriptor *iface )
{
    return CONTAINING_RECORD( iface, struct usb_bulk_out_endpoint_descriptor, IUsbBulkOutEndpointDescriptor_iface );
}

static HRESULT WINAPI usb_bulk_out_endpoint_descriptor_QueryInterface( IUsbBulkOutEndpointDescriptor *iface, REFIID iid, void **out )
{
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IUsbBulkOutEndpointDescriptor ))
    {
        *out = iface;
        IUsbBulkOutEndpointDescriptor_AddRef( iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_bulk_out_endpoint_descriptor_AddRef( IUsbBulkOutEndpointDescriptor *iface )
{
    return InterlockedIncrement( &impl_from_IUsbBulkOutEndpointDescriptor( iface )->ref );
}

static ULONG WINAPI usb_bulk_out_endpoint_descriptor_Release( IUsbBulkOutEndpointDescriptor *iface )
{
    struct usb_bulk_out_endpoint_descriptor *impl = impl_from_IUsbBulkOutEndpointDescriptor( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref) { if (impl->pipe) IUsbBulkOutPipe_Release( impl->pipe ); free( impl ); }
    return ref;
}

static HRESULT WINAPI usb_bulk_out_endpoint_descriptor_GetIids( IUsbBulkOutEndpointDescriptor *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IUsbBulkOutEndpointDescriptor };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}
static HRESULT WINAPI usb_bulk_out_endpoint_descriptor_GetRuntimeClassName( IUsbBulkOutEndpointDescriptor *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbBulkOutEndpointDescriptor";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI usb_bulk_out_endpoint_descriptor_GetTrustLevel( IUsbBulkOutEndpointDescriptor *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI usb_bulk_out_endpoint_descriptor_get_MaxPacketSize( IUsbBulkOutEndpointDescriptor *iface, UINT32 *value )
{
    if (!value) return E_INVALIDARG;
    *value = impl_from_IUsbBulkOutEndpointDescriptor( iface )->max_packet_size;
    return S_OK;
}
static HRESULT WINAPI usb_bulk_out_endpoint_descriptor_get_EndpointNumber( IUsbBulkOutEndpointDescriptor *iface, BYTE *value )
{
    if (!value) return E_INVALIDARG;
    *value = impl_from_IUsbBulkOutEndpointDescriptor( iface )->endpoint_number;
    return S_OK;
}
static HRESULT WINAPI usb_bulk_out_endpoint_descriptor_get_Pipe( IUsbBulkOutEndpointDescriptor *iface, IUsbBulkOutPipe **value )
{
    struct usb_bulk_out_endpoint_descriptor *impl = impl_from_IUsbBulkOutEndpointDescriptor( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->pipe;
    if (impl->pipe) IUsbBulkOutPipe_AddRef( impl->pipe );
    return S_OK;
}

static const IUsbBulkOutEndpointDescriptorVtbl usb_bulk_out_endpoint_descriptor_vtbl = {
    usb_bulk_out_endpoint_descriptor_QueryInterface,
    usb_bulk_out_endpoint_descriptor_AddRef,
    usb_bulk_out_endpoint_descriptor_Release,
    usb_bulk_out_endpoint_descriptor_GetIids,
    usb_bulk_out_endpoint_descriptor_GetRuntimeClassName,
    usb_bulk_out_endpoint_descriptor_GetTrustLevel,
    usb_bulk_out_endpoint_descriptor_get_MaxPacketSize,
    usb_bulk_out_endpoint_descriptor_get_EndpointNumber,
    usb_bulk_out_endpoint_descriptor_get_Pipe,
};

static HRESULT usb_bulk_out_endpoint_descriptor_create( struct usb_bulk_out_pipe *pipe,
    IUsbBulkOutEndpointDescriptor **out )
{
    struct usb_bulk_out_endpoint_descriptor *impl;
    if (!out || !pipe) return E_INVALIDARG;
    *out = NULL;
    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IUsbBulkOutEndpointDescriptor_iface.lpVtbl = &usb_bulk_out_endpoint_descriptor_vtbl;
    impl->ref = 1;
    impl->pipe = &pipe->IUsbBulkOutPipe_iface;
    IUsbBulkOutPipe_AddRef( impl->pipe );
    impl->max_packet_size = pipe->max_packet_size;
    impl->endpoint_number = pipe->endpoint_address & 0x0f;
    *out = &impl->IUsbBulkOutEndpointDescriptor_iface;
    return S_OK;
}

/* UsbInterfaceDescriptor */
struct usb_interface_descriptor_obj
{
    IUsbInterfaceDescriptor IUsbInterfaceDescriptor_iface;
    LONG ref;
    BYTE class_code;
    BYTE subclass_code;
    BYTE protocol_code;
    BYTE alternate_setting_number;
    BYTE interface_number;
};

static inline struct usb_interface_descriptor_obj *impl_from_IUsbInterfaceDescriptor( IUsbInterfaceDescriptor *iface )
{
    return CONTAINING_RECORD( iface, struct usb_interface_descriptor_obj, IUsbInterfaceDescriptor_iface );
}

static HRESULT WINAPI usb_interface_descriptor_QueryInterface( IUsbInterfaceDescriptor *iface, REFIID iid, void **out )
{
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IUsbInterfaceDescriptor ))
    {
        *out = iface;
        IUsbInterfaceDescriptor_AddRef( iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}
static ULONG WINAPI usb_interface_descriptor_AddRef( IUsbInterfaceDescriptor *iface )
{
    return InterlockedIncrement( &impl_from_IUsbInterfaceDescriptor( iface )->ref );
}
static ULONG WINAPI usb_interface_descriptor_Release( IUsbInterfaceDescriptor *iface )
{
    struct usb_interface_descriptor_obj *impl = impl_from_IUsbInterfaceDescriptor( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref) free( impl );
    return ref;
}
static HRESULT WINAPI usb_interface_descriptor_GetIids( IUsbInterfaceDescriptor *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IUsbInterfaceDescriptor };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}
static HRESULT WINAPI usb_interface_descriptor_GetRuntimeClassName( IUsbInterfaceDescriptor *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbInterfaceDescriptor";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI usb_interface_descriptor_GetTrustLevel( IUsbInterfaceDescriptor *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI usb_interface_descriptor_get_ClassCode( IUsbInterfaceDescriptor *iface, BYTE *value )
{
    if (!value) return E_INVALIDARG;
    *value = impl_from_IUsbInterfaceDescriptor( iface )->class_code;
    return S_OK;
}
static HRESULT WINAPI usb_interface_descriptor_get_SubclassCode( IUsbInterfaceDescriptor *iface, BYTE *value )
{
    if (!value) return E_INVALIDARG;
    *value = impl_from_IUsbInterfaceDescriptor( iface )->subclass_code;
    return S_OK;
}
static HRESULT WINAPI usb_interface_descriptor_get_ProtocolCode( IUsbInterfaceDescriptor *iface, BYTE *value )
{
    if (!value) return E_INVALIDARG;
    *value = impl_from_IUsbInterfaceDescriptor( iface )->protocol_code;
    return S_OK;
}
static HRESULT WINAPI usb_interface_descriptor_get_AlternateSettingNumber( IUsbInterfaceDescriptor *iface, BYTE *value )
{
    if (!value) return E_INVALIDARG;
    *value = impl_from_IUsbInterfaceDescriptor( iface )->alternate_setting_number;
    return S_OK;
}
static HRESULT WINAPI usb_interface_descriptor_get_InterfaceNumber( IUsbInterfaceDescriptor *iface, BYTE *value )
{
    if (!value) return E_INVALIDARG;
    *value = impl_from_IUsbInterfaceDescriptor( iface )->interface_number;
    return S_OK;
}

static const IUsbInterfaceDescriptorVtbl usb_interface_descriptor_vtbl = {
    usb_interface_descriptor_QueryInterface,
    usb_interface_descriptor_AddRef,
    usb_interface_descriptor_Release,
    usb_interface_descriptor_GetIids,
    usb_interface_descriptor_GetRuntimeClassName,
    usb_interface_descriptor_GetTrustLevel,
    usb_interface_descriptor_get_ClassCode,
    usb_interface_descriptor_get_SubclassCode,
    usb_interface_descriptor_get_ProtocolCode,
    usb_interface_descriptor_get_AlternateSettingNumber,
    usb_interface_descriptor_get_InterfaceNumber,
};

static HRESULT usb_interface_descriptor_create( const USB_INTERFACE_DESCRIPTOR *raw, IUsbInterfaceDescriptor **out )
{
    struct usb_interface_descriptor_obj *impl;
    if (!out || !raw) return E_INVALIDARG;
    *out = NULL;
    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IUsbInterfaceDescriptor_iface.lpVtbl = &usb_interface_descriptor_vtbl;
    impl->ref = 1;
    impl->class_code = raw->bInterfaceClass;
    impl->subclass_code = raw->bInterfaceSubClass;
    impl->protocol_code = raw->bInterfaceProtocol;
    impl->alternate_setting_number = raw->bAlternateSetting;
    impl->interface_number = raw->bInterfaceNumber;
    *out = &impl->IUsbInterfaceDescriptor_iface;
    return S_OK;
}

/* Vector views for endpoint descriptors (used by UsbInterfaceSetting) */
struct usb_bulk_in_endpoint_descriptors_view
{
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor IVectorView_iface;
    LONG ref;
    UINT32 size;
    IUsbBulkInEndpointDescriptor **items;
};
static inline struct usb_bulk_in_endpoint_descriptors_view *impl_from_bulk_in_ed_view(
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor *iface )
{
    return CONTAINING_RECORD( iface, struct usb_bulk_in_endpoint_descriptors_view, IVectorView_iface );
}
static HRESULT WINAPI bulk_in_ed_view_QueryInterface( __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor *iface, REFIID iid, void **out )
{
    if (IsEqualGUID(iid,&IID_IUnknown)||IsEqualGUID(iid,&IID_IInspectable)||IsEqualGUID(iid,&IID___FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor))
    { *out=iface; __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor_AddRef(iface); return S_OK; }
    *out=NULL; return E_NOINTERFACE;
}
static ULONG WINAPI bulk_in_ed_view_AddRef( __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor *iface )
{ return InterlockedIncrement( &impl_from_bulk_in_ed_view(iface)->ref ); }
static ULONG WINAPI bulk_in_ed_view_Release( __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor *iface )
{
    struct usb_bulk_in_endpoint_descriptors_view *impl = impl_from_bulk_in_ed_view(iface);
    ULONG ref = InterlockedDecrement(&impl->ref);
    if (!ref) { UINT32 i; if (impl->items) { for (i=0;i<impl->size;i++) if (impl->items[i]) IUsbBulkInEndpointDescriptor_Release(impl->items[i]); free(impl->items); } free(impl); }
    return ref;
}
static HRESULT WINAPI bulk_in_ed_view_GetIids( __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor *iface, ULONG *c, IID **i )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IVectorView_UsbBulkInEndpointDescriptor };
    IID *out;
    ULONG k;
    if (!c || !i) return E_INVALIDARG;
    *c = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (k = 0; k < 2; k++) out[k] = *ids[k];
    *i = out;
    return S_OK;
}
static HRESULT WINAPI bulk_in_ed_view_GetRuntimeClassName( __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor *iface, HSTRING *n )
{
    static const WCHAR name[] = L"Windows.Foundation.Collections.IVectorView`1<Windows.Devices.Usb.UsbBulkInEndpointDescriptor>";
    if (!n) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, n );
}
static HRESULT WINAPI bulk_in_ed_view_GetTrustLevel( __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor *iface, TrustLevel *t )
{
    if (!t) return E_INVALIDARG;
    *t = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI bulk_in_ed_view_GetAt( __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor *iface, UINT32 idx, IUsbBulkInEndpointDescriptor **val )
{
    struct usb_bulk_in_endpoint_descriptors_view *impl = impl_from_bulk_in_ed_view(iface);
    if (!val) return E_INVALIDARG; *val=NULL; if (idx>=impl->size) return E_BOUNDS;
    *val=impl->items[idx]; if (*val) IUsbBulkInEndpointDescriptor_AddRef(*val); return S_OK;
}
static HRESULT WINAPI bulk_in_ed_view_get_Size( __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor *iface, UINT32 *val )
{ if (!val) return E_INVALIDARG; *val=impl_from_bulk_in_ed_view(iface)->size; return S_OK; }
static HRESULT WINAPI bulk_in_ed_view_IndexOf( __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor *iface, IUsbBulkInEndpointDescriptor *el, UINT32 *idx, BOOLEAN *found )
{
    struct usb_bulk_in_endpoint_descriptors_view *impl = impl_from_bulk_in_ed_view(iface); UINT32 i;
    if (idx)*idx=0; if (found)*found=FALSE; if (!el||!found) return E_INVALIDARG;
    for (i=0;i<impl->size;i++) if (impl->items[i]==el) { if (idx)*idx=i; *found=TRUE; break; } return S_OK;
}
static HRESULT WINAPI bulk_in_ed_view_GetMany( __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor *iface, UINT32 start, UINT32 cap, IUsbBulkInEndpointDescriptor **items, UINT32 *val )
{
    struct usb_bulk_in_endpoint_descriptors_view *impl = impl_from_bulk_in_ed_view(iface); UINT32 i, avail;
    if (!val||!items) return E_INVALIDARG; *val=0; if (start>=impl->size) return E_BOUNDS;
    avail=impl->size-start; if (cap>avail) cap=avail;
    for (i=0;i<cap;i++) { items[i]=impl->items[start+i]; if (items[i]) IUsbBulkInEndpointDescriptor_AddRef(items[i]); } *val=cap; return S_OK;
}
static const __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptorVtbl bulk_in_ed_view_vtbl = {
    bulk_in_ed_view_QueryInterface, bulk_in_ed_view_AddRef, bulk_in_ed_view_Release,
    bulk_in_ed_view_GetIids, bulk_in_ed_view_GetRuntimeClassName, bulk_in_ed_view_GetTrustLevel,
    bulk_in_ed_view_GetAt, bulk_in_ed_view_get_Size, bulk_in_ed_view_IndexOf, bulk_in_ed_view_GetMany,
};
static HRESULT usb_bulk_in_endpoint_descriptors_view_create( IUsbBulkInEndpointDescriptor **items, UINT32 count,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor **out )
{
    struct usb_bulk_in_endpoint_descriptors_view *impl;
    UINT32 i;
    if (!out) return E_INVALIDARG; *out=NULL;
    if (!(impl = calloc(1,sizeof(*impl)))) return E_OUTOFMEMORY;
    impl->IVectorView_iface.lpVtbl = &bulk_in_ed_view_vtbl; impl->ref=1;
    if (count && (impl->items = calloc(count,sizeof(*impl->items)))) {
        impl->size=count;
        for (i=0;i<count;i++) { impl->items[i]=items[i]; if (impl->items[i]) IUsbBulkInEndpointDescriptor_AddRef(impl->items[i]); }
    }
    *out=&impl->IVectorView_iface; return S_OK;
}

/* BulkOut endpoint descriptors view */
struct usb_bulk_out_endpoint_descriptors_view {
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor IVectorView_iface;
    LONG ref; UINT32 size; IUsbBulkOutEndpointDescriptor **items;
};
static inline struct usb_bulk_out_endpoint_descriptors_view *impl_from_bulk_out_ed_view(
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor *iface )
{ return CONTAINING_RECORD(iface, struct usb_bulk_out_endpoint_descriptors_view, IVectorView_iface); }
static HRESULT WINAPI bulk_out_ed_view_QueryInterface(__FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor *iface, REFIID iid, void **out) {
    if (IsEqualGUID(iid,&IID_IUnknown)||IsEqualGUID(iid,&IID_IInspectable)||IsEqualGUID(iid,&IID___FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor))
    { *out=iface; __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor_AddRef(iface); return S_OK; }
    *out=NULL; return E_NOINTERFACE; }
static ULONG WINAPI bulk_out_ed_view_AddRef(__FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor *iface)
{ return InterlockedIncrement(&impl_from_bulk_out_ed_view(iface)->ref); }
static ULONG WINAPI bulk_out_ed_view_Release(__FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor *iface) {
    struct usb_bulk_out_endpoint_descriptors_view *impl = impl_from_bulk_out_ed_view(iface);
    ULONG ref = InterlockedDecrement(&impl->ref);
    if (!ref) { UINT32 i; if (impl->items) { for (i=0;i<impl->size;i++) if (impl->items[i]) IUsbBulkOutEndpointDescriptor_Release(impl->items[i]); free(impl->items); } free(impl); }
    return ref; }
static HRESULT WINAPI bulk_out_ed_view_GetIids( __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor *iface, ULONG *c, IID **i )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IVectorView_UsbBulkOutEndpointDescriptor };
    IID *out;
    ULONG k;
    if (!c || !i) return E_INVALIDARG;
    *c = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (k = 0; k < 2; k++) out[k] = *ids[k];
    *i = out;
    return S_OK;
}
static HRESULT WINAPI bulk_out_ed_view_GetRuntimeClassName( __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor *iface, HSTRING *n )
{
    static const WCHAR name[] = L"Windows.Foundation.Collections.IVectorView`1<Windows.Devices.Usb.UsbBulkOutEndpointDescriptor>";
    if (!n) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, n );
}
static HRESULT WINAPI bulk_out_ed_view_GetTrustLevel( __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor *iface, TrustLevel *t )
{
    if (!t) return E_INVALIDARG;
    *t = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI bulk_out_ed_view_GetAt( __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor *iface, UINT32 idx, IUsbBulkOutEndpointDescriptor **val ) {
    struct usb_bulk_out_endpoint_descriptors_view *impl = impl_from_bulk_out_ed_view(iface);
    if (!val) return E_INVALIDARG; *val=NULL; if (idx>=impl->size) return E_BOUNDS;
    *val=impl->items[idx]; if (*val) IUsbBulkOutEndpointDescriptor_AddRef(*val); return S_OK; }
static HRESULT WINAPI bulk_out_ed_view_get_Size( __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor *iface, UINT32 *val )
{ if (!val) return E_INVALIDARG; *val=impl_from_bulk_out_ed_view(iface)->size; return S_OK; }
static HRESULT WINAPI bulk_out_ed_view_IndexOf( __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor *iface, IUsbBulkOutEndpointDescriptor *el, UINT32 *idx, BOOLEAN *found ) {
    struct usb_bulk_out_endpoint_descriptors_view *impl = impl_from_bulk_out_ed_view(iface); UINT32 i;
    if (idx)*idx=0; if (found)*found=FALSE; if (!el||!found) return E_INVALIDARG;
    for (i=0;i<impl->size;i++) if (impl->items[i]==el) { if (idx)*idx=i; *found=TRUE; break; } return S_OK; }
static HRESULT WINAPI bulk_out_ed_view_GetMany( __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor *iface, UINT32 start, UINT32 cap, IUsbBulkOutEndpointDescriptor **items, UINT32 *val ) {
    struct usb_bulk_out_endpoint_descriptors_view *impl = impl_from_bulk_out_ed_view(iface); UINT32 i, avail;
    if (!val||!items) return E_INVALIDARG; *val=0; if (start>=impl->size) return E_BOUNDS;
    avail=impl->size-start; if (cap>avail) cap=avail;
    for (i=0;i<cap;i++) { items[i]=impl->items[start+i]; if (items[i]) IUsbBulkOutEndpointDescriptor_AddRef(items[i]); } *val=cap; return S_OK; }
static const __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptorVtbl bulk_out_ed_view_vtbl = {
    bulk_out_ed_view_QueryInterface, bulk_out_ed_view_AddRef, bulk_out_ed_view_Release,
    bulk_out_ed_view_GetIids, bulk_out_ed_view_GetRuntimeClassName, bulk_out_ed_view_GetTrustLevel,
    bulk_out_ed_view_GetAt, bulk_out_ed_view_get_Size, bulk_out_ed_view_IndexOf, bulk_out_ed_view_GetMany, };
static HRESULT usb_bulk_out_endpoint_descriptors_view_create( IUsbBulkOutEndpointDescriptor **items, UINT32 count,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor **out )
{
    struct usb_bulk_out_endpoint_descriptors_view *impl; UINT32 i;
    if (!out) return E_INVALIDARG; *out=NULL;
    if (!(impl = calloc(1,sizeof(*impl)))) return E_OUTOFMEMORY;
    impl->IVectorView_iface.lpVtbl = &bulk_out_ed_view_vtbl; impl->ref=1;
    if (count && (impl->items = calloc(count,sizeof(*impl->items)))) {
        impl->size=count;
        for (i=0;i<count;i++) { impl->items[i]=items[i]; if (impl->items[i]) IUsbBulkOutEndpointDescriptor_AddRef(impl->items[i]); }
    }
    *out=&impl->IVectorView_iface; return S_OK;
}

/* InterruptIn endpoint descriptors view */
struct usb_interrupt_in_endpoint_descriptors_view {
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor IVectorView_iface;
    LONG ref; UINT32 size; IUsbInterruptInEndpointDescriptor **items;
};
static inline struct usb_interrupt_in_endpoint_descriptors_view *impl_from_int_in_ed_view(
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor *iface )
{ return CONTAINING_RECORD(iface, struct usb_interrupt_in_endpoint_descriptors_view, IVectorView_iface); }
static HRESULT WINAPI int_in_ed_view_QueryInterface(__FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor *iface, REFIID iid, void **out) {
    if (IsEqualGUID(iid,&IID_IUnknown)||IsEqualGUID(iid,&IID_IInspectable)||IsEqualGUID(iid,&IID___FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor))
    { *out=iface; __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor_AddRef(iface); return S_OK; }
    *out=NULL; return E_NOINTERFACE; }
static ULONG WINAPI int_in_ed_view_AddRef(__FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor *iface)
{ return InterlockedIncrement(&impl_from_int_in_ed_view(iface)->ref); }
static ULONG WINAPI int_in_ed_view_Release(__FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor *iface) {
    struct usb_interrupt_in_endpoint_descriptors_view *impl = impl_from_int_in_ed_view(iface);
    ULONG ref = InterlockedDecrement(&impl->ref);
    if (!ref) { UINT32 i; if (impl->items) { for (i=0;i<impl->size;i++) if (impl->items[i]) IUsbInterruptInEndpointDescriptor_Release(impl->items[i]); free(impl->items); } free(impl); }
    return ref; }
static HRESULT WINAPI int_in_ed_view_GetIids( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor *iface, ULONG *c, IID **i )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IVectorView_UsbInterruptInEndpointDescriptor };
    IID *out;
    ULONG k;
    if (!c || !i) return E_INVALIDARG;
    *c = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (k = 0; k < 2; k++) out[k] = *ids[k];
    *i = out;
    return S_OK;
}
static HRESULT WINAPI int_in_ed_view_GetRuntimeClassName( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor *iface, HSTRING *n )
{
    static const WCHAR name[] = L"Windows.Foundation.Collections.IVectorView`1<Windows.Devices.Usb.UsbInterruptInEndpointDescriptor>";
    if (!n) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, n );
}
static HRESULT WINAPI int_in_ed_view_GetTrustLevel( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor *iface, TrustLevel *t )
{
    if (!t) return E_INVALIDARG;
    *t = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI int_in_ed_view_GetAt( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor *iface, UINT32 idx, IUsbInterruptInEndpointDescriptor **val ) {
    struct usb_interrupt_in_endpoint_descriptors_view *impl = impl_from_int_in_ed_view(iface);
    if (!val) return E_INVALIDARG; *val=NULL; if (idx>=impl->size) return E_BOUNDS;
    *val=impl->items[idx]; if (*val) IUsbInterruptInEndpointDescriptor_AddRef(*val); return S_OK; }
static HRESULT WINAPI int_in_ed_view_get_Size( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor *iface, UINT32 *val )
{ if (!val) return E_INVALIDARG; *val=impl_from_int_in_ed_view(iface)->size; return S_OK; }
static HRESULT WINAPI int_in_ed_view_IndexOf( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor *iface, IUsbInterruptInEndpointDescriptor *el, UINT32 *idx, BOOLEAN *found ) {
    struct usb_interrupt_in_endpoint_descriptors_view *impl = impl_from_int_in_ed_view(iface); UINT32 i;
    if (idx)*idx=0; if (found)*found=FALSE; if (!el||!found) return E_INVALIDARG;
    for (i=0;i<impl->size;i++) if (impl->items[i]==el) { if (idx)*idx=i; *found=TRUE; break; } return S_OK; }
static HRESULT WINAPI int_in_ed_view_GetMany( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor *iface, UINT32 start, UINT32 cap, IUsbInterruptInEndpointDescriptor **items, UINT32 *val ) {
    struct usb_interrupt_in_endpoint_descriptors_view *impl = impl_from_int_in_ed_view(iface); UINT32 i, avail;
    if (!val||!items) return E_INVALIDARG; *val=0; if (start>=impl->size) return E_BOUNDS;
    avail=impl->size-start; if (cap>avail) cap=avail;
    for (i=0;i<cap;i++) { items[i]=impl->items[start+i]; if (items[i]) IUsbInterruptInEndpointDescriptor_AddRef(items[i]); } *val=cap; return S_OK; }
static const __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptorVtbl int_in_ed_view_vtbl = {
    int_in_ed_view_QueryInterface, int_in_ed_view_AddRef, int_in_ed_view_Release,
    int_in_ed_view_GetIids, int_in_ed_view_GetRuntimeClassName, int_in_ed_view_GetTrustLevel,
    int_in_ed_view_GetAt, int_in_ed_view_get_Size, int_in_ed_view_IndexOf, int_in_ed_view_GetMany, };
static HRESULT usb_interrupt_in_endpoint_descriptors_view_create( IUsbInterruptInEndpointDescriptor **items, UINT32 count,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor **out )
{
    struct usb_interrupt_in_endpoint_descriptors_view *impl; UINT32 i;
    if (!out) return E_INVALIDARG; *out=NULL;
    if (!(impl = calloc(1,sizeof(*impl)))) return E_OUTOFMEMORY;
    impl->IVectorView_iface.lpVtbl = &int_in_ed_view_vtbl; impl->ref=1;
    if (count && (impl->items = calloc(count,sizeof(*impl->items)))) {
        impl->size=count;
        for (i=0;i<count;i++) { impl->items[i]=items[i]; if (impl->items[i]) IUsbInterruptInEndpointDescriptor_AddRef(impl->items[i]); }
    }
    *out=&impl->IVectorView_iface; return S_OK;
}

/* InterruptOut endpoint descriptors view */
struct usb_interrupt_out_endpoint_descriptors_view {
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor IVectorView_iface;
    LONG ref; UINT32 size; IUsbInterruptOutEndpointDescriptor **items;
};
static inline struct usb_interrupt_out_endpoint_descriptors_view *impl_from_int_out_ed_view(
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor *iface )
{ return CONTAINING_RECORD(iface, struct usb_interrupt_out_endpoint_descriptors_view, IVectorView_iface); }
static HRESULT WINAPI int_out_ed_view_QueryInterface(__FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor *iface, REFIID iid, void **out) {
    if (IsEqualGUID(iid,&IID_IUnknown)||IsEqualGUID(iid,&IID_IInspectable)||IsEqualGUID(iid,&IID___FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor))
    { *out=iface; __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor_AddRef(iface); return S_OK; }
    *out=NULL; return E_NOINTERFACE; }
static ULONG WINAPI int_out_ed_view_AddRef(__FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor *iface)
{ return InterlockedIncrement(&impl_from_int_out_ed_view(iface)->ref); }
static ULONG WINAPI int_out_ed_view_Release(__FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor *iface) {
    struct usb_interrupt_out_endpoint_descriptors_view *impl = impl_from_int_out_ed_view(iface);
    ULONG ref = InterlockedDecrement(&impl->ref);
    if (!ref) { UINT32 i; if (impl->items) { for (i=0;i<impl->size;i++) if (impl->items[i]) IUsbInterruptOutEndpointDescriptor_Release(impl->items[i]); free(impl->items); } free(impl); }
    return ref; }
static HRESULT WINAPI int_out_ed_view_GetIids( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor *iface, ULONG *c, IID **i )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IVectorView_UsbInterruptOutEndpointDescriptor };
    IID *out;
    ULONG k;
    if (!c || !i) return E_INVALIDARG;
    *c = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (k = 0; k < 2; k++) out[k] = *ids[k];
    *i = out;
    return S_OK;
}
static HRESULT WINAPI int_out_ed_view_GetRuntimeClassName( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor *iface, HSTRING *n )
{
    static const WCHAR name[] = L"Windows.Foundation.Collections.IVectorView`1<Windows.Devices.Usb.UsbInterruptOutEndpointDescriptor>";
    if (!n) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, n );
}
static HRESULT WINAPI int_out_ed_view_GetTrustLevel( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor *iface, TrustLevel *t )
{
    if (!t) return E_INVALIDARG;
    *t = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI int_out_ed_view_GetAt( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor *iface, UINT32 idx, IUsbInterruptOutEndpointDescriptor **val ) {
    struct usb_interrupt_out_endpoint_descriptors_view *impl = impl_from_int_out_ed_view(iface);
    if (!val) return E_INVALIDARG; *val=NULL; if (idx>=impl->size) return E_BOUNDS;
    *val=impl->items[idx]; if (*val) IUsbInterruptOutEndpointDescriptor_AddRef(*val); return S_OK; }
static HRESULT WINAPI int_out_ed_view_get_Size( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor *iface, UINT32 *val )
{ if (!val) return E_INVALIDARG; *val=impl_from_int_out_ed_view(iface)->size; return S_OK; }
static HRESULT WINAPI int_out_ed_view_IndexOf( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor *iface, IUsbInterruptOutEndpointDescriptor *el, UINT32 *idx, BOOLEAN *found ) {
    struct usb_interrupt_out_endpoint_descriptors_view *impl = impl_from_int_out_ed_view(iface); UINT32 i;
    if (idx)*idx=0; if (found)*found=FALSE; if (!el||!found) return E_INVALIDARG;
    for (i=0;i<impl->size;i++) if (impl->items[i]==el) { if (idx)*idx=i; *found=TRUE; break; } return S_OK; }
static HRESULT WINAPI int_out_ed_view_GetMany( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor *iface, UINT32 start, UINT32 cap, IUsbInterruptOutEndpointDescriptor **items, UINT32 *val ) {
    struct usb_interrupt_out_endpoint_descriptors_view *impl = impl_from_int_out_ed_view(iface); UINT32 i, avail;
    if (!val||!items) return E_INVALIDARG; *val=0; if (start>=impl->size) return E_BOUNDS;
    avail=impl->size-start; if (cap>avail) cap=avail;
    for (i=0;i<cap;i++) { items[i]=impl->items[start+i]; if (items[i]) IUsbInterruptOutEndpointDescriptor_AddRef(items[i]); } *val=cap; return S_OK; }
static const __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptorVtbl int_out_ed_view_vtbl = {
    int_out_ed_view_QueryInterface, int_out_ed_view_AddRef, int_out_ed_view_Release,
    int_out_ed_view_GetIids, int_out_ed_view_GetRuntimeClassName, int_out_ed_view_GetTrustLevel,
    int_out_ed_view_GetAt, int_out_ed_view_get_Size, int_out_ed_view_IndexOf, int_out_ed_view_GetMany, };
static HRESULT usb_interrupt_out_endpoint_descriptors_view_create( IUsbInterruptOutEndpointDescriptor **items, UINT32 count,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor **out )
{
    struct usb_interrupt_out_endpoint_descriptors_view *impl; UINT32 i;
    if (!out) return E_INVALIDARG; *out=NULL;
    if (!(impl = calloc(1,sizeof(*impl)))) return E_OUTOFMEMORY;
    impl->IVectorView_iface.lpVtbl = &int_out_ed_view_vtbl; impl->ref=1;
    if (count && (impl->items = calloc(count,sizeof(*impl->items)))) {
        impl->size=count;
        for (i=0;i<count;i++) { impl->items[i]=items[i]; if (impl->items[i]) IUsbInterruptOutEndpointDescriptor_AddRef(impl->items[i]); }
    }
    *out=&impl->IVectorView_iface; return S_OK;
}

static HRESULT usb_input_stream_create( struct usb_bulk_in_pipe *pipe, IInputStream **out );
static HRESULT usb_output_stream_create( struct usb_bulk_out_pipe *pipe, IOutputStream **out );
static HRESULT usb_output_stream_create_ex( struct usb_device *device, UCHAR endpoint_address,
    IUnknown *ref_holder, IOutputStream **out );

static HRESULT WINAPI usb_bulk_out_pipe_QueryInterface( IUsbBulkOutPipe *iface, REFIID iid, void **out )
{
    TRACE( "iface %p, iid %s, out %p.\n", iface, debugstr_guid( iid ), out );

    if (IsEqualGUID( iid, &IID_IUnknown ) ||
        IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAgileObject ) ||
        IsEqualGUID( iid, &IID_IUsbBulkOutPipe ))
    {
        IUsbBulkOutPipe_AddRef( iface );
        *out = iface;
        return S_OK;
    }

    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_bulk_out_pipe_AddRef( IUsbBulkOutPipe *iface )
{
    struct usb_bulk_out_pipe *impl = impl_from_IUsbBulkOutPipe( iface );
    return InterlockedIncrement( &impl->ref );
}

static ULONG WINAPI usb_bulk_out_pipe_Release( IUsbBulkOutPipe *iface )
{
    struct usb_bulk_out_pipe *impl = impl_from_IUsbBulkOutPipe( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );

    if (!ref) free( impl );
    return ref;
}

static HRESULT WINAPI usb_bulk_out_pipe_GetIids( IUsbBulkOutPipe *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IUsbBulkOutPipe };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}

static HRESULT WINAPI usb_bulk_out_pipe_GetRuntimeClassName( IUsbBulkOutPipe *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbBulkOutPipe";

    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}

static HRESULT WINAPI usb_bulk_out_pipe_GetTrustLevel( IUsbBulkOutPipe *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI usb_bulk_out_pipe_get_EndpointDescriptor( IUsbBulkOutPipe *iface,
        IUsbBulkOutEndpointDescriptor **value )
{
    struct usb_bulk_out_pipe *impl = impl_from_IUsbBulkOutPipe( iface );
    if (!value) return E_INVALIDARG;
    *value = NULL;
    return usb_bulk_out_endpoint_descriptor_create( impl, value );
}

static HRESULT WINAPI usb_bulk_out_pipe_ClearStallAsync( IUsbBulkOutPipe *iface, IAsyncAction **operation )
{
    struct usb_bulk_out_pipe *impl = impl_from_IUsbBulkOutPipe( iface );
    HRESULT hr;
    if (!operation) return E_INVALIDARG;
    *operation = NULL;
    hr = usb_clear_endpoint_stall( impl->device, impl->endpoint_address );
    return async_action_completed_create( hr, operation );
}

static HRESULT WINAPI usb_bulk_out_pipe_put_WriteOptions( IUsbBulkOutPipe *iface, UsbWriteOptions value )
{
    struct usb_bulk_out_pipe *impl = impl_from_IUsbBulkOutPipe( iface );
    impl->write_options = value;
    return S_OK;
}

static HRESULT WINAPI usb_bulk_out_pipe_get_WriteOptions( IUsbBulkOutPipe *iface, UsbWriteOptions *value )
{
    struct usb_bulk_out_pipe *impl = impl_from_IUsbBulkOutPipe( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->write_options;
    return S_OK;
}

static HRESULT WINAPI usb_bulk_out_pipe_get_OutputStream( IUsbBulkOutPipe *iface, IOutputStream **value )
{
    struct usb_bulk_out_pipe *impl = impl_from_IUsbBulkOutPipe( iface );
    if (!value) return E_INVALIDARG;
    *value = NULL;
    return usb_output_stream_create( impl, value );
}

static const IUsbBulkOutPipeVtbl usb_bulk_out_pipe_vtbl =
{
    usb_bulk_out_pipe_QueryInterface,
    usb_bulk_out_pipe_AddRef,
    usb_bulk_out_pipe_Release,
    usb_bulk_out_pipe_GetIids,
    usb_bulk_out_pipe_GetRuntimeClassName,
    usb_bulk_out_pipe_GetTrustLevel,
    usb_bulk_out_pipe_get_EndpointDescriptor,
    usb_bulk_out_pipe_ClearStallAsync,
    usb_bulk_out_pipe_put_WriteOptions,
    usb_bulk_out_pipe_get_WriteOptions,
    usb_bulk_out_pipe_get_OutputStream,
};

static HRESULT usb_bulk_out_pipe_create( struct usb_device *device, const USB_ENDPOINT_DESCRIPTOR *ep,
        IUsbBulkOutPipe **out )
{
    struct usb_bulk_out_pipe *impl;

    if (!out) return E_INVALIDARG;
    *out = NULL;

    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IUsbBulkOutPipe_iface.lpVtbl = &usb_bulk_out_pipe_vtbl;
    impl->ref = 1;
    impl->device = device;
    impl->endpoint_address = ep->bEndpointAddress;
    impl->max_packet_size = ep->wMaxPacketSize;
    impl->write_options = UsbWriteOptions_None;

    *out = &impl->IUsbBulkOutPipe_iface;
    return S_OK;
}

static HRESULT usb_bulk_out_pipe_create( struct usb_device *device, const USB_ENDPOINT_DESCRIPTOR *ep,
        IUsbBulkOutPipe **out );

static HRESULT WINAPI usb_bulk_in_pipes_QueryInterface(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe *iface, REFIID iid, void **out )
{
    TRACE( "iface %p, iid %s, out %p.\n", iface, debugstr_guid( iid ), out );

    if (IsEqualGUID( iid, &IID_IUnknown ) ||
        IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAgileObject ) ||
        IsEqualGUID( iid, &IID___FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe ))
    {
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe_AddRef( iface );
        *out = iface;
        return S_OK;
    }

    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_bulk_in_pipes_AddRef(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe *iface )
{
    struct usb_bulk_in_pipes *impl = impl_from_usb_bulk_in_pipes( iface );
    return InterlockedIncrement( &impl->ref );
}

static ULONG WINAPI usb_bulk_in_pipes_Release(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe *iface )
{
    struct usb_bulk_in_pipes *impl = impl_from_usb_bulk_in_pipes( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    UINT32 i;

    if (!ref)
    {
        if (impl->items)
        {
            for (i = 0; i < impl->size; ++i)
            {
                if (impl->items[i]) IUsbBulkInPipe_Release( impl->items[i] );
            }
            free( impl->items );
        }
        free( impl );
    }
    return ref;
}

static HRESULT WINAPI usb_bulk_in_pipes_GetIids(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IVectorView_UsbBulkInPipe };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}

static HRESULT WINAPI usb_bulk_in_pipes_GetRuntimeClassName(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Foundation.Collections.IVectorView`1<Windows.Devices.Usb.UsbBulkInPipe>";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}

static HRESULT WINAPI usb_bulk_in_pipes_GetTrustLevel(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI usb_bulk_in_pipes_GetAt(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe *iface, UINT32 index,
        IUsbBulkInPipe **value )
{
    struct usb_bulk_in_pipes *impl = impl_from_usb_bulk_in_pipes( iface );

    if (!value) return E_INVALIDARG;
    *value = NULL;
    if (index >= impl->size) return E_BOUNDS;

    *value = impl->items[index];
    if (*value) IUsbBulkInPipe_AddRef( *value );
    return S_OK;
}

static HRESULT WINAPI usb_bulk_in_pipes_get_Size(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe *iface, UINT32 *value )
{
    struct usb_bulk_in_pipes *impl = impl_from_usb_bulk_in_pipes( iface );

    if (!value) return E_INVALIDARG;
    *value = impl->size;
    return S_OK;
}

static HRESULT WINAPI usb_bulk_in_pipes_IndexOf(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe *iface, IUsbBulkInPipe *element,
        UINT32 *index, BOOLEAN *found )
{
    struct usb_bulk_in_pipes *impl = impl_from_usb_bulk_in_pipes( iface );
    UINT32 i;

    if (index) *index = 0;
    if (found) *found = FALSE;

    if (!element || !found) return E_INVALIDARG;

    for (i = 0; i < impl->size; ++i)
    {
        if (impl->items[i] == element)
        {
            if (index) *index = i;
            *found = TRUE;
            break;
        }
    }

    return S_OK;
}

static HRESULT WINAPI usb_bulk_in_pipes_GetMany(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe *iface, UINT32 start_index,
        UINT32 items_size, IUsbBulkInPipe **items, UINT32 *value )
{
    struct usb_bulk_in_pipes *impl = impl_from_usb_bulk_in_pipes( iface );
    UINT32 i, available;

    if (!value || !items) return E_INVALIDARG;
    *value = 0;

    if (start_index >= impl->size) return E_BOUNDS;

    available = impl->size - start_index;
    if (items_size > available) items_size = available;

    for (i = 0; i < items_size; ++i)
    {
        items[i] = impl->items[start_index + i];
        if (items[i]) IUsbBulkInPipe_AddRef( items[i] );
    }

    *value = items_size;
    return S_OK;
}

static const __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipeVtbl usb_bulk_in_pipes_vtbl =
{
    usb_bulk_in_pipes_QueryInterface,
    usb_bulk_in_pipes_AddRef,
    usb_bulk_in_pipes_Release,
    usb_bulk_in_pipes_GetIids,
    usb_bulk_in_pipes_GetRuntimeClassName,
    usb_bulk_in_pipes_GetTrustLevel,
    usb_bulk_in_pipes_GetAt,
    usb_bulk_in_pipes_get_Size,
    usb_bulk_in_pipes_IndexOf,
    usb_bulk_in_pipes_GetMany,
};

static HRESULT usb_bulk_in_pipes_create(
        IUsbBulkInPipe **items, UINT32 count,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe **out )
{
    struct usb_bulk_in_pipes *impl;
    UINT32 i;

    if (!out) return E_INVALIDARG;
    *out = NULL;

    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IVectorView_iface.lpVtbl = &usb_bulk_in_pipes_vtbl;
    impl->ref = 1;

    if (count)
    {
        if (!(impl->items = calloc( count, sizeof(*impl->items) )))
        {
            free( impl );
            return E_OUTOFMEMORY;
        }

        impl->size = count;
        for (i = 0; i < count; ++i)
        {
            impl->items[i] = items[i];
            if (impl->items[i]) IUsbBulkInPipe_AddRef( impl->items[i] );
        }
    }

    *out = &impl->IVectorView_iface;
    return S_OK;
}

static HRESULT WINAPI usb_bulk_out_pipes_QueryInterface(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe *iface, REFIID iid, void **out )
{
    TRACE( "iface %p, iid %s, out %p.\n", iface, debugstr_guid( iid ), out );

    if (IsEqualGUID( iid, &IID_IUnknown ) ||
        IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAgileObject ) ||
        IsEqualGUID( iid, &IID___FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe ))
    {
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe_AddRef( iface );
        *out = iface;
        return S_OK;
    }

    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_bulk_out_pipes_AddRef(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe *iface )
{
    struct usb_bulk_out_pipes *impl = impl_from_usb_bulk_out_pipes( iface );
    return InterlockedIncrement( &impl->ref );
}

static ULONG WINAPI usb_bulk_out_pipes_Release(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe *iface )
{
    struct usb_bulk_out_pipes *impl = impl_from_usb_bulk_out_pipes( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    UINT32 i;

    if (!ref)
    {
        if (impl->items)
        {
            for (i = 0; i < impl->size; ++i)
                if (impl->items[i]) IUsbBulkOutPipe_Release( impl->items[i] );
            free( impl->items );
        }
        free( impl );
    }

    return ref;
}

static HRESULT WINAPI usb_bulk_out_pipes_GetIids(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IVectorView_UsbBulkOutPipe };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}

static HRESULT WINAPI usb_bulk_out_pipes_GetRuntimeClassName(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Foundation.Collections.IVectorView`1<Windows.Devices.Usb.UsbBulkOutPipe>";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}

static HRESULT WINAPI usb_bulk_out_pipes_GetTrustLevel(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI usb_bulk_out_pipes_GetAt(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe *iface, UINT32 index,
        IUsbBulkOutPipe **value )
{
    struct usb_bulk_out_pipes *impl = impl_from_usb_bulk_out_pipes( iface );

    if (!value) return E_INVALIDARG;
    *value = NULL;
    if (index >= impl->size) return E_BOUNDS;

    *value = impl->items[index];
    if (*value) IUsbBulkOutPipe_AddRef( *value );
    return S_OK;
}

static HRESULT WINAPI usb_bulk_out_pipes_get_Size(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe *iface, UINT32 *value )
{
    struct usb_bulk_out_pipes *impl = impl_from_usb_bulk_out_pipes( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->size;
    return S_OK;
}

static HRESULT WINAPI usb_bulk_out_pipes_IndexOf(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe *iface, IUsbBulkOutPipe *element,
        UINT32 *index, BOOLEAN *found )
{
    struct usb_bulk_out_pipes *impl = impl_from_usb_bulk_out_pipes( iface );
    UINT32 i;

    if (index) *index = 0;
    if (found) *found = FALSE;

    if (!element || !found) return E_INVALIDARG;

    for (i = 0; i < impl->size; ++i)
    {
        if (impl->items[i] == element)
        {
            if (index) *index = i;
            *found = TRUE;
            break;
        }
    }

    return S_OK;
}

static HRESULT WINAPI usb_bulk_out_pipes_GetMany(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe *iface, UINT32 start_index,
        UINT32 items_size, IUsbBulkOutPipe **items, UINT32 *value )
{
    struct usb_bulk_out_pipes *impl = impl_from_usb_bulk_out_pipes( iface );
    UINT32 i, available;

    if (!value || !items) return E_INVALIDARG;
    *value = 0;

    if (start_index >= impl->size) return E_BOUNDS;

    available = impl->size - start_index;
    if (items_size > available) items_size = available;

    for (i = 0; i < items_size; ++i)
    {
        items[i] = impl->items[start_index + i];
        if (items[i]) IUsbBulkOutPipe_AddRef( items[i] );
    }

    *value = items_size;
    return S_OK;
}

static const __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipeVtbl usb_bulk_out_pipes_vtbl =
{
    usb_bulk_out_pipes_QueryInterface,
    usb_bulk_out_pipes_AddRef,
    usb_bulk_out_pipes_Release,
    usb_bulk_out_pipes_GetIids,
    usb_bulk_out_pipes_GetRuntimeClassName,
    usb_bulk_out_pipes_GetTrustLevel,
    usb_bulk_out_pipes_GetAt,
    usb_bulk_out_pipes_get_Size,
    usb_bulk_out_pipes_IndexOf,
    usb_bulk_out_pipes_GetMany,
};

static HRESULT usb_bulk_out_pipes_create(
        IUsbBulkOutPipe **items, UINT32 count,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe **out )
{
    struct usb_bulk_out_pipes *impl;
    UINT32 i;

    if (!out) return E_INVALIDARG;
    *out = NULL;

    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IVectorView_iface.lpVtbl = &usb_bulk_out_pipes_vtbl;
    impl->ref = 1;

    if (count)
    {
        if (!(impl->items = calloc( count, sizeof(*impl->items) )))
        {
            free( impl );
            return E_OUTOFMEMORY;
        }

        impl->size = count;
        for (i = 0; i < count; ++i)
        {
            impl->items[i] = items[i];
            if (impl->items[i]) IUsbBulkOutPipe_AddRef( impl->items[i] );
        }
    }

    *out = &impl->IVectorView_iface;
    return S_OK;
}

/* UsbInterruptInEventArgs */
struct usb_interrupt_in_event_args
{
    IUsbInterruptInEventArgs IUsbInterruptInEventArgs_iface;
    LONG ref;
    IBuffer *interrupt_data;
};

static inline struct usb_interrupt_in_event_args *impl_from_IUsbInterruptInEventArgs( IUsbInterruptInEventArgs *iface )
{
    return CONTAINING_RECORD( iface, struct usb_interrupt_in_event_args, IUsbInterruptInEventArgs_iface );
}

static HRESULT WINAPI usb_interrupt_in_event_args_QueryInterface( IUsbInterruptInEventArgs *iface, REFIID iid, void **out )
{
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IUsbInterruptInEventArgs ))
    {
        *out = iface;
        IUsbInterruptInEventArgs_AddRef( iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}
static ULONG WINAPI usb_interrupt_in_event_args_AddRef( IUsbInterruptInEventArgs *iface )
{
    return InterlockedIncrement( &impl_from_IUsbInterruptInEventArgs( iface )->ref );
}
static ULONG WINAPI usb_interrupt_in_event_args_Release( IUsbInterruptInEventArgs *iface )
{
    struct usb_interrupt_in_event_args *impl = impl_from_IUsbInterruptInEventArgs( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref)
    {
        if (impl->interrupt_data) IBuffer_Release( impl->interrupt_data );
        free( impl );
    }
    return ref;
}
static HRESULT WINAPI usb_interrupt_in_event_args_GetIids( IUsbInterruptInEventArgs *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IUsbInterruptInEventArgs };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_in_event_args_GetRuntimeClassName( IUsbInterruptInEventArgs *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbInterruptInEventArgs";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI usb_interrupt_in_event_args_GetTrustLevel( IUsbInterruptInEventArgs *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_in_event_args_get_InterruptData( IUsbInterruptInEventArgs *iface, IBuffer **value )
{
    struct usb_interrupt_in_event_args *impl = impl_from_IUsbInterruptInEventArgs( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->interrupt_data;
    if (impl->interrupt_data) IBuffer_AddRef( impl->interrupt_data );
    return S_OK;
}

static const IUsbInterruptInEventArgsVtbl usb_interrupt_in_event_args_vtbl = {
    usb_interrupt_in_event_args_QueryInterface,
    usb_interrupt_in_event_args_AddRef,
    usb_interrupt_in_event_args_Release,
    usb_interrupt_in_event_args_GetIids,
    usb_interrupt_in_event_args_GetRuntimeClassName,
    usb_interrupt_in_event_args_GetTrustLevel,
    usb_interrupt_in_event_args_get_InterruptData,
};

static HRESULT usb_interrupt_in_event_args_create( IBuffer *buffer, IUsbInterruptInEventArgs **out )
{
    struct usb_interrupt_in_event_args *impl;
    if (!out || !buffer) return E_INVALIDARG;
    *out = NULL;
    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IUsbInterruptInEventArgs_iface.lpVtbl = &usb_interrupt_in_event_args_vtbl;
    impl->ref = 1;
    impl->interrupt_data = buffer;
    IBuffer_AddRef( buffer );
    *out = &impl->IUsbInterruptInEventArgs_iface;
    return S_OK;
}

/* UsbInterruptInPipe */
struct data_received_handler
{
    struct data_received_handler *next;
    EventRegistrationToken token;
    __FITypedEventHandler_2_Windows__CDevices__CUsb__CUsbInterruptInPipe_Windows__CDevices__CUsb__CUsbInterruptInEventArgs *handler;
};

struct usb_interrupt_in_pipe
{
    IUsbInterruptInPipe IUsbInterruptInPipe_iface;
    LONG ref;
    struct usb_device *device;
    UCHAR endpoint_address;
    UINT32 max_packet_size;
    BYTE interval;
    CRITICAL_SECTION handler_cs;
    struct data_received_handler *data_received_handlers;
    LONG next_token;
    HANDLE thread;
    HANDLE stop_event;
};

static inline struct usb_interrupt_in_pipe *impl_from_IUsbInterruptInPipe( IUsbInterruptInPipe *iface )
{
    return CONTAINING_RECORD( iface, struct usb_interrupt_in_pipe, IUsbInterruptInPipe_iface );
}

static HRESULT WINAPI usb_interrupt_in_pipe_QueryInterface( IUsbInterruptInPipe *iface, REFIID iid, void **out )
{
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IUsbInterruptInPipe ))
    {
        *out = iface;
        IUsbInterruptInPipe_AddRef( iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_interrupt_in_pipe_AddRef( IUsbInterruptInPipe *iface )
{
    return InterlockedIncrement( &impl_from_IUsbInterruptInPipe( iface )->ref );
}

static ULONG WINAPI usb_interrupt_in_pipe_Release( IUsbInterruptInPipe *iface )
{
    struct usb_interrupt_in_pipe *impl = impl_from_IUsbInterruptInPipe( iface );
    struct data_received_handler *h, *next;
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref)
    {
        if (impl->thread)
        {
            SetEvent( impl->stop_event );
            WaitForSingleObject( impl->thread, INFINITE );
            CloseHandle( impl->thread );
            CloseHandle( impl->stop_event );
        }
        for (h = impl->data_received_handlers; h; h = next)
        {
            next = h->next;
            if (h->handler)
                __FITypedEventHandler_2_Windows__CDevices__CUsb__CUsbInterruptInPipe_Windows__CDevices__CUsb__CUsbInterruptInEventArgs_Release( h->handler );
            free( h );
        }
        DeleteCriticalSection( &impl->handler_cs );
        free( impl );
    }
    return ref;
}

static HRESULT WINAPI usb_interrupt_in_pipe_GetIids( IUsbInterruptInPipe *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IUsbInterruptInPipe };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_in_pipe_GetRuntimeClassName( IUsbInterruptInPipe *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbInterruptInPipe";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI usb_interrupt_in_pipe_GetTrustLevel( IUsbInterruptInPipe *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_in_pipe_get_EndpointDescriptor( IUsbInterruptInPipe *iface,
    IUsbInterruptInEndpointDescriptor **value )
{
    struct usb_interrupt_in_pipe *impl = impl_from_IUsbInterruptInPipe( iface );
    if (!value) return E_INVALIDARG;
    *value = NULL;
    return usb_interrupt_in_endpoint_descriptor_create( impl, value );
}
static HRESULT WINAPI usb_interrupt_in_pipe_ClearStallAsync( IUsbInterruptInPipe *iface, IAsyncAction **operation )
{
    struct usb_interrupt_in_pipe *impl = impl_from_IUsbInterruptInPipe( iface );
    HRESULT hr;
    if (!operation) return E_INVALIDARG;
    *operation = NULL;
    hr = usb_clear_endpoint_stall( impl->device, impl->endpoint_address );
    return async_action_completed_create( hr, operation );
}
static DWORD WINAPI data_received_thread_proc( void *param )
{
    struct usb_interrupt_in_pipe *pipe = param;
    IBuffer *buffer = NULL;
    IBufferByteAccess *byte_access = NULL;
    BYTE *data;
    ULONG transferred;
    DWORD interval_ms = 10;
    struct data_received_handler *h;
    IUsbInterruptInEventArgs *args = NULL;
    HRESULT hr;

    if (pipe->interval > 0)
        interval_ms = (DWORD)pipe->interval;

    while (WaitForSingleObject( pipe->stop_event, interval_ms ) == WAIT_TIMEOUT)
    {
        if (!pipe->device || !pipe->device->winusb)
            break;
        if (!buffer)
        {
            hr = Buffer_Create( pipe->max_packet_size, &buffer );
            if (FAILED( hr )) continue;
        }
        hr = IBuffer_QueryInterface( buffer, &IID_IBufferByteAccess, (void **)&byte_access );
        if (FAILED( hr )) continue;
        hr = IBufferByteAccess_Buffer( byte_access, &data );
        IBufferByteAccess_Release( byte_access );
        if (FAILED( hr )) continue;

        if (!WinUsb_ReadPipe( pipe->device->winusb, pipe->endpoint_address, data, pipe->max_packet_size, &transferred, NULL ))
            continue;
        if (transferred == 0)
            continue;

        hr = IBuffer_put_Length( buffer, (UINT32)transferred );
        if (FAILED( hr )) continue;
        hr = usb_interrupt_in_event_args_create( buffer, &args );
        if (FAILED( hr )) continue;

        EnterCriticalSection( &pipe->handler_cs );
        for (h = pipe->data_received_handlers; h; h = h->next)
        {
            if (h->handler)
                __FITypedEventHandler_2_Windows__CDevices__CUsb__CUsbInterruptInPipe_Windows__CDevices__CUsb__CUsbInterruptInEventArgs_Invoke(
                    h->handler, &pipe->IUsbInterruptInPipe_iface, args );
        }
        LeaveCriticalSection( &pipe->handler_cs );

        IUsbInterruptInEventArgs_Release( args );
        args = NULL;
    }

    if (buffer) IBuffer_Release( buffer );
    IUsbInterruptInPipe_Release( &pipe->IUsbInterruptInPipe_iface );
    return 0;
}

static HRESULT WINAPI usb_interrupt_in_pipe_add_DataReceived( IUsbInterruptInPipe *iface,
    __FITypedEventHandler_2_Windows__CDevices__CUsb__CUsbInterruptInPipe_Windows__CDevices__CUsb__CUsbInterruptInEventArgs *handler,
    EventRegistrationToken *token )
{
    struct usb_interrupt_in_pipe *impl = impl_from_IUsbInterruptInPipe( iface );
    struct data_received_handler *node;
    BOOL first = FALSE;

    if (!handler || !token) return E_INVALIDARG;

    node = calloc( 1, sizeof(*node) );
    if (!node) return E_OUTOFMEMORY;

    EnterCriticalSection( &impl->handler_cs );
    node->token.value = impl->next_token++;
    node->handler = handler;
    __FITypedEventHandler_2_Windows__CDevices__CUsb__CUsbInterruptInPipe_Windows__CDevices__CUsb__CUsbInterruptInEventArgs_AddRef( handler );
    node->next = impl->data_received_handlers;
    impl->data_received_handlers = node;
    first = (impl->data_received_handlers->next == NULL && impl->thread == NULL);
    LeaveCriticalSection( &impl->handler_cs );

    *token = node->token;

    if (first)
    {
        impl->stop_event = CreateEventW( NULL, TRUE, FALSE, NULL );
        if (impl->stop_event)
        {
            IUsbInterruptInPipe_AddRef( iface );
            impl->thread = CreateThread( NULL, 0, data_received_thread_proc, impl, 0, NULL );
            if (!impl->thread)
            {
                CloseHandle( impl->stop_event );
                impl->stop_event = NULL;
                IUsbInterruptInPipe_Release( iface );
            }
        }
    }
    return S_OK;
}

static HRESULT WINAPI usb_interrupt_in_pipe_remove_DataReceived( IUsbInterruptInPipe *iface, EventRegistrationToken token )
{
    struct usb_interrupt_in_pipe *impl = impl_from_IUsbInterruptInPipe( iface );
    struct data_received_handler **p, *cur;
    BOOL last = FALSE;

    EnterCriticalSection( &impl->handler_cs );
    for (p = &impl->data_received_handlers; *p; p = &(*p)->next)
    {
        if ((*p)->token.value == token.value)
        {
            cur = *p;
            *p = cur->next;
            if (cur->handler)
                __FITypedEventHandler_2_Windows__CDevices__CUsb__CUsbInterruptInPipe_Windows__CDevices__CUsb__CUsbInterruptInEventArgs_Release( cur->handler );
            free( cur );
            last = (impl->data_received_handlers == NULL);
            break;
        }
    }
    LeaveCriticalSection( &impl->handler_cs );

    if (last && impl->thread)
    {
        SetEvent( impl->stop_event );
        WaitForSingleObject( impl->thread, INFINITE );
        CloseHandle( impl->thread );
        CloseHandle( impl->stop_event );
        impl->thread = NULL;
        impl->stop_event = NULL;
    }
    return S_OK;
}

static const IUsbInterruptInPipeVtbl usb_interrupt_in_pipe_vtbl = {
    usb_interrupt_in_pipe_QueryInterface,
    usb_interrupt_in_pipe_AddRef,
    usb_interrupt_in_pipe_Release,
    usb_interrupt_in_pipe_GetIids,
    usb_interrupt_in_pipe_GetRuntimeClassName,
    usb_interrupt_in_pipe_GetTrustLevel,
    usb_interrupt_in_pipe_get_EndpointDescriptor,
    usb_interrupt_in_pipe_ClearStallAsync,
    usb_interrupt_in_pipe_add_DataReceived,
    usb_interrupt_in_pipe_remove_DataReceived,
};

static HRESULT usb_interrupt_in_pipe_create( struct usb_device *device, const USB_ENDPOINT_DESCRIPTOR *ep,
    IUsbInterruptInPipe **out )
{
    struct usb_interrupt_in_pipe *impl;
    if (!out) return E_INVALIDARG;
    *out = NULL;
    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IUsbInterruptInPipe_iface.lpVtbl = &usb_interrupt_in_pipe_vtbl;
    impl->ref = 1;
    impl->device = device;
    impl->endpoint_address = ep->bEndpointAddress;
    impl->max_packet_size = ep->wMaxPacketSize;
    impl->interval = ep->bInterval;
    InitializeCriticalSection( &impl->handler_cs );
    impl->data_received_handlers = NULL;
    impl->next_token = 1;
    impl->thread = NULL;
    impl->stop_event = NULL;
    *out = &impl->IUsbInterruptInPipe_iface;
    return S_OK;
}

/* UsbInterruptOutPipe */
struct usb_interrupt_out_pipe
{
    IUsbInterruptOutPipe IUsbInterruptOutPipe_iface;
    LONG ref;
    struct usb_device *device;
    UCHAR endpoint_address;
    UINT32 max_packet_size;
    BYTE interval;
    UsbWriteOptions write_options;
};

static inline struct usb_interrupt_out_pipe *impl_from_IUsbInterruptOutPipe( IUsbInterruptOutPipe *iface )
{
    return CONTAINING_RECORD( iface, struct usb_interrupt_out_pipe, IUsbInterruptOutPipe_iface );
}

static HRESULT WINAPI usb_interrupt_out_pipe_QueryInterface( IUsbInterruptOutPipe *iface, REFIID iid, void **out )
{
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IUsbInterruptOutPipe ))
    {
        *out = iface;
        IUsbInterruptOutPipe_AddRef( iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_interrupt_out_pipe_AddRef( IUsbInterruptOutPipe *iface )
{
    return InterlockedIncrement( &impl_from_IUsbInterruptOutPipe( iface )->ref );
}

static ULONG WINAPI usb_interrupt_out_pipe_Release( IUsbInterruptOutPipe *iface )
{
    struct usb_interrupt_out_pipe *impl = impl_from_IUsbInterruptOutPipe( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref) free( impl );
    return ref;
}

static HRESULT WINAPI usb_interrupt_out_pipe_GetIids( IUsbInterruptOutPipe *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IUsbInterruptOutPipe };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_out_pipe_GetRuntimeClassName( IUsbInterruptOutPipe *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbInterruptOutPipe";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI usb_interrupt_out_pipe_GetTrustLevel( IUsbInterruptOutPipe *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_out_pipe_get_EndpointDescriptor( IUsbInterruptOutPipe *iface,
    IUsbInterruptOutEndpointDescriptor **value )
{
    struct usb_interrupt_out_pipe *impl = impl_from_IUsbInterruptOutPipe( iface );
    if (!value) return E_INVALIDARG;
    *value = NULL;
    return usb_interrupt_out_endpoint_descriptor_create( impl, value );
}
static HRESULT WINAPI usb_interrupt_out_pipe_ClearStallAsync( IUsbInterruptOutPipe *iface, IAsyncAction **operation )
{
    struct usb_interrupt_out_pipe *impl = impl_from_IUsbInterruptOutPipe( iface );
    HRESULT hr;
    if (!operation) return E_INVALIDARG;
    *operation = NULL;
    hr = usb_clear_endpoint_stall( impl->device, impl->endpoint_address );
    return async_action_completed_create( hr, operation );
}
static HRESULT WINAPI usb_interrupt_out_pipe_put_WriteOptions( IUsbInterruptOutPipe *iface, UsbWriteOptions value )
{
    impl_from_IUsbInterruptOutPipe( iface )->write_options = value;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_out_pipe_get_WriteOptions( IUsbInterruptOutPipe *iface, UsbWriteOptions *value )
{
    if (!value) return E_INVALIDARG;
    *value = impl_from_IUsbInterruptOutPipe( iface )->write_options;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_out_pipe_get_OutputStream( IUsbInterruptOutPipe *iface, IOutputStream **value )
{
    struct usb_interrupt_out_pipe *impl = impl_from_IUsbInterruptOutPipe( iface );
    if (!value) return E_INVALIDARG;
    *value = NULL;
    return usb_output_stream_create_ex( impl->device, impl->endpoint_address,
        (IUnknown *)&impl->IUsbInterruptOutPipe_iface, value );
}

static const IUsbInterruptOutPipeVtbl usb_interrupt_out_pipe_vtbl = {
    usb_interrupt_out_pipe_QueryInterface,
    usb_interrupt_out_pipe_AddRef,
    usb_interrupt_out_pipe_Release,
    usb_interrupt_out_pipe_GetIids,
    usb_interrupt_out_pipe_GetRuntimeClassName,
    usb_interrupt_out_pipe_GetTrustLevel,
    usb_interrupt_out_pipe_get_EndpointDescriptor,
    usb_interrupt_out_pipe_ClearStallAsync,
    usb_interrupt_out_pipe_put_WriteOptions,
    usb_interrupt_out_pipe_get_WriteOptions,
    usb_interrupt_out_pipe_get_OutputStream,
};

static HRESULT usb_interrupt_out_pipe_create( struct usb_device *device, const USB_ENDPOINT_DESCRIPTOR *ep,
    IUsbInterruptOutPipe **out )
{
    struct usb_interrupt_out_pipe *impl;
    if (!out) return E_INVALIDARG;
    *out = NULL;
    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IUsbInterruptOutPipe_iface.lpVtbl = &usb_interrupt_out_pipe_vtbl;
    impl->ref = 1;
    impl->device = device;
    impl->endpoint_address = ep->bEndpointAddress;
    impl->max_packet_size = ep->wMaxPacketSize;
    impl->interval = ep->bInterval;
    impl->write_options = UsbWriteOptions_None;
    *out = &impl->IUsbInterruptOutPipe_iface;
    return S_OK;
}

/* UsbInterruptInEndpointDescriptor */
struct usb_interrupt_in_endpoint_descriptor
{
    IUsbInterruptInEndpointDescriptor IUsbInterruptInEndpointDescriptor_iface;
    LONG ref;
    IUsbInterruptInPipe *pipe;
    UINT32 max_packet_size;
    BYTE endpoint_number;
    BYTE interval;
};

static inline struct usb_interrupt_in_endpoint_descriptor *impl_from_IUsbInterruptInEndpointDescriptor(
    IUsbInterruptInEndpointDescriptor *iface )
{
    return CONTAINING_RECORD( iface, struct usb_interrupt_in_endpoint_descriptor, IUsbInterruptInEndpointDescriptor_iface );
}

static HRESULT WINAPI usb_interrupt_in_endpoint_descriptor_QueryInterface( IUsbInterruptInEndpointDescriptor *iface, REFIID iid, void **out )
{
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IUsbInterruptInEndpointDescriptor ))
    {
        *out = iface;
        IUsbInterruptInEndpointDescriptor_AddRef( iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}
static ULONG WINAPI usb_interrupt_in_endpoint_descriptor_AddRef( IUsbInterruptInEndpointDescriptor *iface )
{
    return InterlockedIncrement( &impl_from_IUsbInterruptInEndpointDescriptor( iface )->ref );
}
static ULONG WINAPI usb_interrupt_in_endpoint_descriptor_Release( IUsbInterruptInEndpointDescriptor *iface )
{
    struct usb_interrupt_in_endpoint_descriptor *impl = impl_from_IUsbInterruptInEndpointDescriptor( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref) { if (impl->pipe) IUsbInterruptInPipe_Release( impl->pipe ); free( impl ); }
    return ref;
}
static HRESULT WINAPI usb_interrupt_in_endpoint_descriptor_GetIids( IUsbInterruptInEndpointDescriptor *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IUsbInterruptInEndpointDescriptor };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_in_endpoint_descriptor_GetRuntimeClassName( IUsbInterruptInEndpointDescriptor *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbInterruptInEndpointDescriptor";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI usb_interrupt_in_endpoint_descriptor_GetTrustLevel( IUsbInterruptInEndpointDescriptor *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_in_endpoint_descriptor_get_MaxPacketSize( IUsbInterruptInEndpointDescriptor *iface, UINT32 *value )
{
    if (!value) return E_INVALIDARG;
    *value = impl_from_IUsbInterruptInEndpointDescriptor( iface )->max_packet_size;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_in_endpoint_descriptor_get_EndpointNumber( IUsbInterruptInEndpointDescriptor *iface, BYTE *value )
{
    if (!value) return E_INVALIDARG;
    *value = impl_from_IUsbInterruptInEndpointDescriptor( iface )->endpoint_number;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_in_endpoint_descriptor_get_Interval( IUsbInterruptInEndpointDescriptor *iface, TimeSpan *value )
{
    struct usb_interrupt_in_endpoint_descriptor *impl = impl_from_IUsbInterruptInEndpointDescriptor( iface );
    if (!value) return E_INVALIDARG;
    /* USB bInterval: full-speed interrupt in ms (1-255); report as 100-ns units (1 ms = 10000) */
    value->Duration = (INT64)impl->interval * 10000;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_in_endpoint_descriptor_get_Pipe( IUsbInterruptInEndpointDescriptor *iface, IUsbInterruptInPipe **value )
{
    struct usb_interrupt_in_endpoint_descriptor *impl = impl_from_IUsbInterruptInEndpointDescriptor( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->pipe;
    if (impl->pipe) IUsbInterruptInPipe_AddRef( impl->pipe );
    return S_OK;
}

static const IUsbInterruptInEndpointDescriptorVtbl usb_interrupt_in_endpoint_descriptor_vtbl = {
    usb_interrupt_in_endpoint_descriptor_QueryInterface,
    usb_interrupt_in_endpoint_descriptor_AddRef,
    usb_interrupt_in_endpoint_descriptor_Release,
    usb_interrupt_in_endpoint_descriptor_GetIids,
    usb_interrupt_in_endpoint_descriptor_GetRuntimeClassName,
    usb_interrupt_in_endpoint_descriptor_GetTrustLevel,
    usb_interrupt_in_endpoint_descriptor_get_MaxPacketSize,
    usb_interrupt_in_endpoint_descriptor_get_EndpointNumber,
    usb_interrupt_in_endpoint_descriptor_get_Interval,
    usb_interrupt_in_endpoint_descriptor_get_Pipe,
};

static HRESULT usb_interrupt_in_endpoint_descriptor_create( struct usb_interrupt_in_pipe *pipe,
    IUsbInterruptInEndpointDescriptor **out )
{
    struct usb_interrupt_in_endpoint_descriptor *impl;
    if (!out || !pipe) return E_INVALIDARG;
    *out = NULL;
    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IUsbInterruptInEndpointDescriptor_iface.lpVtbl = &usb_interrupt_in_endpoint_descriptor_vtbl;
    impl->ref = 1;
    impl->pipe = &pipe->IUsbInterruptInPipe_iface;
    IUsbInterruptInPipe_AddRef( impl->pipe );
    impl->max_packet_size = pipe->max_packet_size;
    impl->endpoint_number = pipe->endpoint_address & 0x0f;
    impl->interval = pipe->interval;
    *out = &impl->IUsbInterruptInEndpointDescriptor_iface;
    return S_OK;
}

/* UsbInterruptOutEndpointDescriptor */
struct usb_interrupt_out_endpoint_descriptor
{
    IUsbInterruptOutEndpointDescriptor IUsbInterruptOutEndpointDescriptor_iface;
    LONG ref;
    IUsbInterruptOutPipe *pipe;
    UINT32 max_packet_size;
    BYTE endpoint_number;
    BYTE interval;
};

static inline struct usb_interrupt_out_endpoint_descriptor *impl_from_IUsbInterruptOutEndpointDescriptor(
    IUsbInterruptOutEndpointDescriptor *iface )
{
    return CONTAINING_RECORD( iface, struct usb_interrupt_out_endpoint_descriptor, IUsbInterruptOutEndpointDescriptor_iface );
}

static HRESULT WINAPI usb_interrupt_out_endpoint_descriptor_QueryInterface( IUsbInterruptOutEndpointDescriptor *iface, REFIID iid, void **out )
{
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IUsbInterruptOutEndpointDescriptor ))
    {
        *out = iface;
        IUsbInterruptOutEndpointDescriptor_AddRef( iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}
static ULONG WINAPI usb_interrupt_out_endpoint_descriptor_AddRef( IUsbInterruptOutEndpointDescriptor *iface )
{
    return InterlockedIncrement( &impl_from_IUsbInterruptOutEndpointDescriptor( iface )->ref );
}
static ULONG WINAPI usb_interrupt_out_endpoint_descriptor_Release( IUsbInterruptOutEndpointDescriptor *iface )
{
    struct usb_interrupt_out_endpoint_descriptor *impl = impl_from_IUsbInterruptOutEndpointDescriptor( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref) { if (impl->pipe) IUsbInterruptOutPipe_Release( impl->pipe ); free( impl ); }
    return ref;
}
static HRESULT WINAPI usb_interrupt_out_endpoint_descriptor_GetIids( IUsbInterruptOutEndpointDescriptor *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IUsbInterruptOutEndpointDescriptor };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_out_endpoint_descriptor_GetRuntimeClassName( IUsbInterruptOutEndpointDescriptor *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbInterruptOutEndpointDescriptor";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI usb_interrupt_out_endpoint_descriptor_GetTrustLevel( IUsbInterruptOutEndpointDescriptor *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_out_endpoint_descriptor_get_MaxPacketSize( IUsbInterruptOutEndpointDescriptor *iface, UINT32 *value )
{
    if (!value) return E_INVALIDARG;
    *value = impl_from_IUsbInterruptOutEndpointDescriptor( iface )->max_packet_size;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_out_endpoint_descriptor_get_EndpointNumber( IUsbInterruptOutEndpointDescriptor *iface, BYTE *value )
{
    if (!value) return E_INVALIDARG;
    *value = impl_from_IUsbInterruptOutEndpointDescriptor( iface )->endpoint_number;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_out_endpoint_descriptor_get_Interval( IUsbInterruptOutEndpointDescriptor *iface, TimeSpan *value )
{
    struct usb_interrupt_out_endpoint_descriptor *impl = impl_from_IUsbInterruptOutEndpointDescriptor( iface );
    if (!value) return E_INVALIDARG;
    value->Duration = (INT64)impl->interval * 10000;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_out_endpoint_descriptor_get_Pipe( IUsbInterruptOutEndpointDescriptor *iface, IUsbInterruptOutPipe **value )
{
    struct usb_interrupt_out_endpoint_descriptor *impl = impl_from_IUsbInterruptOutEndpointDescriptor( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->pipe;
    if (impl->pipe) IUsbInterruptOutPipe_AddRef( impl->pipe );
    return S_OK;
}

static const IUsbInterruptOutEndpointDescriptorVtbl usb_interrupt_out_endpoint_descriptor_vtbl = {
    usb_interrupt_out_endpoint_descriptor_QueryInterface,
    usb_interrupt_out_endpoint_descriptor_AddRef,
    usb_interrupt_out_endpoint_descriptor_Release,
    usb_interrupt_out_endpoint_descriptor_GetIids,
    usb_interrupt_out_endpoint_descriptor_GetRuntimeClassName,
    usb_interrupt_out_endpoint_descriptor_GetTrustLevel,
    usb_interrupt_out_endpoint_descriptor_get_MaxPacketSize,
    usb_interrupt_out_endpoint_descriptor_get_EndpointNumber,
    usb_interrupt_out_endpoint_descriptor_get_Interval,
    usb_interrupt_out_endpoint_descriptor_get_Pipe,
};

static HRESULT usb_interrupt_out_endpoint_descriptor_create( struct usb_interrupt_out_pipe *pipe,
    IUsbInterruptOutEndpointDescriptor **out )
{
    struct usb_interrupt_out_endpoint_descriptor *impl;
    if (!out || !pipe) return E_INVALIDARG;
    *out = NULL;
    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IUsbInterruptOutEndpointDescriptor_iface.lpVtbl = &usb_interrupt_out_endpoint_descriptor_vtbl;
    impl->ref = 1;
    impl->pipe = &pipe->IUsbInterruptOutPipe_iface;
    IUsbInterruptOutPipe_AddRef( impl->pipe );
    impl->max_packet_size = pipe->max_packet_size;
    impl->endpoint_number = pipe->endpoint_address & 0x0f;
    impl->interval = pipe->interval;
    *out = &impl->IUsbInterruptOutEndpointDescriptor_iface;
    return S_OK;
}

/* IVectorView<UsbInterruptInPipe> */
struct usb_interrupt_in_pipes
{
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe IVectorView_iface;
    LONG ref;
    UINT32 size;
    IUsbInterruptInPipe **items;
};

static inline struct usb_interrupt_in_pipes *impl_from_usb_interrupt_in_pipes(
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe *iface )
{
    return CONTAINING_RECORD( iface, struct usb_interrupt_in_pipes, IVectorView_iface );
}

static HRESULT WINAPI usb_interrupt_in_pipes_QueryInterface(
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe *iface, REFIID iid, void **out )
{
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID___FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe ))
    {
        *out = iface;
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe_AddRef( iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_interrupt_in_pipes_AddRef( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe *iface )
{
    return InterlockedIncrement( &impl_from_usb_interrupt_in_pipes( iface )->ref );
}

static ULONG WINAPI usb_interrupt_in_pipes_Release( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe *iface )
{
    struct usb_interrupt_in_pipes *impl = impl_from_usb_interrupt_in_pipes( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref)
    {
        if (impl->items)
        {
            UINT32 i;
            for (i = 0; i < impl->size; ++i)
                if (impl->items[i]) IUsbInterruptInPipe_Release( impl->items[i] );
            free( impl->items );
        }
        free( impl );
    }
    return ref;
}

static HRESULT WINAPI usb_interrupt_in_pipes_GetIids( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IVectorView_UsbInterruptInPipe };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_in_pipes_GetRuntimeClassName( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Foundation.Collections.IVectorView`1<Windows.Devices.Usb.UsbInterruptInPipe>";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI usb_interrupt_in_pipes_GetTrustLevel( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI usb_interrupt_in_pipes_GetAt( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe *iface,
    UINT32 index, IUsbInterruptInPipe **value )
{
    struct usb_interrupt_in_pipes *impl = impl_from_usb_interrupt_in_pipes( iface );
    if (!value) return E_INVALIDARG;
    *value = NULL;
    if (index >= impl->size) return E_BOUNDS;
    *value = impl->items[index];
    if (*value) IUsbInterruptInPipe_AddRef( *value );
    return S_OK;
}

static HRESULT WINAPI usb_interrupt_in_pipes_get_Size( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe *iface, UINT32 *value )
{
    struct usb_interrupt_in_pipes *impl = impl_from_usb_interrupt_in_pipes( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->size;
    return S_OK;
}

static HRESULT WINAPI usb_interrupt_in_pipes_IndexOf( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe *iface,
    IUsbInterruptInPipe *element, UINT32 *index, BOOLEAN *found )
{
    struct usb_interrupt_in_pipes *impl = impl_from_usb_interrupt_in_pipes( iface );
    UINT32 i;
    if (index) *index = 0;
    if (found) *found = FALSE;
    if (!element || !found) return E_INVALIDARG;
    for (i = 0; i < impl->size; ++i)
        if (impl->items[i] == element) { if (index) *index = i; *found = TRUE; break; }
    return S_OK;
}

static HRESULT WINAPI usb_interrupt_in_pipes_GetMany( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe *iface,
    UINT32 start_index, UINT32 items_size, IUsbInterruptInPipe **items, UINT32 *value )
{
    struct usb_interrupt_in_pipes *impl = impl_from_usb_interrupt_in_pipes( iface );
    UINT32 i, available;
    if (!value || !items) return E_INVALIDARG;
    *value = 0;
    if (start_index >= impl->size) return E_BOUNDS;
    available = impl->size - start_index;
    if (items_size > available) items_size = available;
    for (i = 0; i < items_size; ++i)
    {
        items[i] = impl->items[start_index + i];
        if (items[i]) IUsbInterruptInPipe_AddRef( items[i] );
    }
    *value = items_size;
    return S_OK;
}

static const __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipeVtbl usb_interrupt_in_pipes_vtbl = {
    usb_interrupt_in_pipes_QueryInterface,
    usb_interrupt_in_pipes_AddRef,
    usb_interrupt_in_pipes_Release,
    usb_interrupt_in_pipes_GetIids,
    usb_interrupt_in_pipes_GetRuntimeClassName,
    usb_interrupt_in_pipes_GetTrustLevel,
    usb_interrupt_in_pipes_GetAt,
    usb_interrupt_in_pipes_get_Size,
    usb_interrupt_in_pipes_IndexOf,
    usb_interrupt_in_pipes_GetMany,
};

static HRESULT usb_interrupt_in_pipes_create( IUsbInterruptInPipe **items, UINT32 count,
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe **out )
{
    struct usb_interrupt_in_pipes *impl;
    UINT32 i;
    if (!out) return E_INVALIDARG;
    *out = NULL;
    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IVectorView_iface.lpVtbl = &usb_interrupt_in_pipes_vtbl;
    impl->ref = 1;
    if (count)
    {
        if (!(impl->items = calloc( count, sizeof(*impl->items) ))) { free( impl ); return E_OUTOFMEMORY; }
        impl->size = count;
        for (i = 0; i < count; ++i)
        {
            impl->items[i] = items[i];
            if (impl->items[i]) IUsbInterruptInPipe_AddRef( impl->items[i] );
        }
    }
    *out = &impl->IVectorView_iface;
    return S_OK;
}

/* IVectorView<UsbInterruptOutPipe> */
struct usb_interrupt_out_pipes
{
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe IVectorView_iface;
    LONG ref;
    UINT32 size;
    IUsbInterruptOutPipe **items;
};

static inline struct usb_interrupt_out_pipes *impl_from_usb_interrupt_out_pipes(
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe *iface )
{
    return CONTAINING_RECORD( iface, struct usb_interrupt_out_pipes, IVectorView_iface );
}

static HRESULT WINAPI usb_interrupt_out_pipes_QueryInterface(
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe *iface, REFIID iid, void **out )
{
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID___FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe ))
    {
        *out = iface;
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe_AddRef( iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_interrupt_out_pipes_AddRef( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe *iface )
{
    return InterlockedIncrement( &impl_from_usb_interrupt_out_pipes( iface )->ref );
}

static ULONG WINAPI usb_interrupt_out_pipes_Release( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe *iface )
{
    struct usb_interrupt_out_pipes *impl = impl_from_usb_interrupt_out_pipes( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref)
    {
        if (impl->items)
        {
            UINT32 i;
            for (i = 0; i < impl->size; ++i)
                if (impl->items[i]) IUsbInterruptOutPipe_Release( impl->items[i] );
            free( impl->items );
        }
        free( impl );
    }
    return ref;
}

static HRESULT WINAPI usb_interrupt_out_pipes_GetIids( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IVectorView_UsbInterruptOutPipe };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}
static HRESULT WINAPI usb_interrupt_out_pipes_GetRuntimeClassName( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Foundation.Collections.IVectorView`1<Windows.Devices.Usb.UsbInterruptOutPipe>";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI usb_interrupt_out_pipes_GetTrustLevel( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI usb_interrupt_out_pipes_GetAt( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe *iface,
    UINT32 index, IUsbInterruptOutPipe **value )
{
    struct usb_interrupt_out_pipes *impl = impl_from_usb_interrupt_out_pipes( iface );
    if (!value) return E_INVALIDARG;
    *value = NULL;
    if (index >= impl->size) return E_BOUNDS;
    *value = impl->items[index];
    if (*value) IUsbInterruptOutPipe_AddRef( *value );
    return S_OK;
}

static HRESULT WINAPI usb_interrupt_out_pipes_get_Size( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe *iface, UINT32 *value )
{
    struct usb_interrupt_out_pipes *impl = impl_from_usb_interrupt_out_pipes( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->size;
    return S_OK;
}

static HRESULT WINAPI usb_interrupt_out_pipes_IndexOf( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe *iface,
    IUsbInterruptOutPipe *element, UINT32 *index, BOOLEAN *found )
{
    struct usb_interrupt_out_pipes *impl = impl_from_usb_interrupt_out_pipes( iface );
    UINT32 i;
    if (index) *index = 0;
    if (found) *found = FALSE;
    if (!element || !found) return E_INVALIDARG;
    for (i = 0; i < impl->size; ++i)
        if (impl->items[i] == element) { if (index) *index = i; *found = TRUE; break; }
    return S_OK;
}

static HRESULT WINAPI usb_interrupt_out_pipes_GetMany( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe *iface,
    UINT32 start_index, UINT32 items_size, IUsbInterruptOutPipe **items, UINT32 *value )
{
    struct usb_interrupt_out_pipes *impl = impl_from_usb_interrupt_out_pipes( iface );
    UINT32 i, available;
    if (!value || !items) return E_INVALIDARG;
    *value = 0;
    if (start_index >= impl->size) return E_BOUNDS;
    available = impl->size - start_index;
    if (items_size > available) items_size = available;
    for (i = 0; i < items_size; ++i)
    {
        items[i] = impl->items[start_index + i];
        if (items[i]) IUsbInterruptOutPipe_AddRef( items[i] );
    }
    *value = items_size;
    return S_OK;
}

static const __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipeVtbl usb_interrupt_out_pipes_vtbl = {
    usb_interrupt_out_pipes_QueryInterface,
    usb_interrupt_out_pipes_AddRef,
    usb_interrupt_out_pipes_Release,
    usb_interrupt_out_pipes_GetIids,
    usb_interrupt_out_pipes_GetRuntimeClassName,
    usb_interrupt_out_pipes_GetTrustLevel,
    usb_interrupt_out_pipes_GetAt,
    usb_interrupt_out_pipes_get_Size,
    usb_interrupt_out_pipes_IndexOf,
    usb_interrupt_out_pipes_GetMany,
};

static HRESULT usb_interrupt_out_pipes_create( IUsbInterruptOutPipe **items, UINT32 count,
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe **out )
{
    struct usb_interrupt_out_pipes *impl;
    UINT32 i;
    if (!out) return E_INVALIDARG;
    *out = NULL;
    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IVectorView_iface.lpVtbl = &usb_interrupt_out_pipes_vtbl;
    impl->ref = 1;
    if (count)
    {
        if (!(impl->items = calloc( count, sizeof(*impl->items) ))) { free( impl ); return E_OUTOFMEMORY; }
        impl->size = count;
        for (i = 0; i < count; ++i)
        {
            impl->items[i] = items[i];
            if (impl->items[i]) IUsbInterruptOutPipe_AddRef( impl->items[i] );
        }
    }
    *out = &impl->IVectorView_iface;
    return S_OK;
}

static HRESULT WINAPI usb_bulk_in_pipe_QueryInterface( IUsbBulkInPipe *iface, REFIID iid, void **out )
{
    TRACE( "iface %p, iid %s, out %p.\n", iface, debugstr_guid( iid ), out );

    if (IsEqualGUID( iid, &IID_IUnknown ) ||
        IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAgileObject ) ||
        IsEqualGUID( iid, &IID_IUsbBulkInPipe ))
    {
        IUsbBulkInPipe_AddRef( iface );
        *out = iface;
        return S_OK;
    }

    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_bulk_in_pipe_AddRef( IUsbBulkInPipe *iface )
{
    struct usb_bulk_in_pipe *impl = impl_from_IUsbBulkInPipe( iface );
    return InterlockedIncrement( &impl->ref );
}

static ULONG WINAPI usb_bulk_in_pipe_Release( IUsbBulkInPipe *iface )
{
    struct usb_bulk_in_pipe *impl = impl_from_IUsbBulkInPipe( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );

    if (!ref) free( impl );
    return ref;
}

static HRESULT WINAPI usb_bulk_in_pipe_GetIids( IUsbBulkInPipe *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IUsbBulkInPipe };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}

static HRESULT WINAPI usb_bulk_in_pipe_GetRuntimeClassName( IUsbBulkInPipe *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbBulkInPipe";

    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}

static HRESULT WINAPI usb_bulk_in_pipe_GetTrustLevel( IUsbBulkInPipe *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI usb_bulk_in_pipe_get_MaxTransferSizeBytes( IUsbBulkInPipe *iface, UINT32 *value )
{
    struct usb_bulk_in_pipe *impl = impl_from_IUsbBulkInPipe( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->max_transfer_size;
    return S_OK;
}

static HRESULT WINAPI usb_bulk_in_pipe_get_EndpointDescriptor( IUsbBulkInPipe *iface,
        IUsbBulkInEndpointDescriptor **value )
{
    struct usb_bulk_in_pipe *impl = impl_from_IUsbBulkInPipe( iface );
    if (!value) return E_INVALIDARG;
    *value = NULL;
    return usb_bulk_in_endpoint_descriptor_create( impl, value );
}

static HRESULT WINAPI usb_bulk_in_pipe_ClearStallAsync( IUsbBulkInPipe *iface, IAsyncAction **operation )
{
    struct usb_bulk_in_pipe *impl = impl_from_IUsbBulkInPipe( iface );
    HRESULT hr;
    if (!operation) return E_INVALIDARG;
    *operation = NULL;
    hr = usb_clear_endpoint_stall( impl->device, impl->endpoint_address );
    return async_action_completed_create( hr, operation );
}

static HRESULT WINAPI usb_bulk_in_pipe_put_ReadOptions( IUsbBulkInPipe *iface, UsbReadOptions value )
{
    struct usb_bulk_in_pipe *impl = impl_from_IUsbBulkInPipe( iface );
    impl->read_options = value;
    return S_OK;
}

static HRESULT WINAPI usb_bulk_in_pipe_get_ReadOptions( IUsbBulkInPipe *iface, UsbReadOptions *value )
{
    struct usb_bulk_in_pipe *impl = impl_from_IUsbBulkInPipe( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->read_options;
    return S_OK;
}

static HRESULT WINAPI usb_bulk_in_pipe_FlushBuffer( IUsbBulkInPipe *iface )
{
    TRACE( "iface %p.\n", iface );
    return S_OK;
}

static HRESULT WINAPI usb_bulk_in_pipe_get_InputStream( IUsbBulkInPipe *iface, IInputStream **value )
{
    struct usb_bulk_in_pipe *impl = impl_from_IUsbBulkInPipe( iface );
    if (!value) return E_INVALIDARG;
    *value = NULL;
    return usb_input_stream_create( impl, value );
}

static const IUsbBulkInPipeVtbl usb_bulk_in_pipe_vtbl =
{
    usb_bulk_in_pipe_QueryInterface,
    usb_bulk_in_pipe_AddRef,
    usb_bulk_in_pipe_Release,
    usb_bulk_in_pipe_GetIids,
    usb_bulk_in_pipe_GetRuntimeClassName,
    usb_bulk_in_pipe_GetTrustLevel,
    usb_bulk_in_pipe_get_MaxTransferSizeBytes,
    usb_bulk_in_pipe_get_EndpointDescriptor,
    usb_bulk_in_pipe_ClearStallAsync,
    usb_bulk_in_pipe_put_ReadOptions,
    usb_bulk_in_pipe_get_ReadOptions,
    usb_bulk_in_pipe_FlushBuffer,
    usb_bulk_in_pipe_get_InputStream,
};

static HRESULT usb_bulk_in_pipe_create( struct usb_device *device, const USB_ENDPOINT_DESCRIPTOR *ep,
        IUsbBulkInPipe **out )
{
    struct usb_bulk_in_pipe *impl;

    if (!out) return E_INVALIDARG;
    *out = NULL;

    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IUsbBulkInPipe_iface.lpVtbl = &usb_bulk_in_pipe_vtbl;
    impl->ref = 1;
    impl->device = device;
    impl->endpoint_address = ep->bEndpointAddress;
    impl->max_transfer_size = ep->wMaxPacketSize;
    impl->read_options = UsbReadOptions_None;

    *out = &impl->IUsbBulkInPipe_iface;
    return S_OK;
}

/* USB input stream (IInputStream over WinUsb_ReadPipe) */
struct usb_input_stream
{
    IInputStream IInputStream_iface;
    IClosable IClosable_iface;
    LONG ref;
    IUsbBulkInPipe *pipe;
};

static inline struct usb_input_stream *impl_from_usb_input_stream_IInputStream( IInputStream *iface )
{
    return CONTAINING_RECORD( iface, struct usb_input_stream, IInputStream_iface );
}

static inline struct usb_input_stream *impl_from_usb_input_stream_IClosable( IClosable *iface )
{
    return CONTAINING_RECORD( iface, struct usb_input_stream, IClosable_iface );
}

/* Async read result: IAsyncOperationWithProgress<IBuffer*, UINT32> */
struct usb_async_read
{
    __FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32 iface;
    LONG ref;
    IBuffer *buffer;
};

static inline struct usb_async_read *impl_from_async_read( __FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32 *iface )
{
    return CONTAINING_RECORD( iface, struct usb_async_read, iface );
}

static HRESULT WINAPI usb_async_read_QueryInterface( __FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32 *iface, REFIID iid, void **out )
{
    struct usb_async_read *impl = impl_from_async_read( iface );
    (void)impl;
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID___FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32 ))
    {
        *out = iface;
        __FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32_AddRef( iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_async_read_AddRef( __FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32 *iface )
{
    struct usb_async_read *impl = impl_from_async_read( iface );
    return InterlockedIncrement( &impl->ref );
}

static ULONG WINAPI usb_async_read_Release( __FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32 *iface )
{
    struct usb_async_read *impl = impl_from_async_read( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref) { if (impl->buffer) IBuffer_Release( impl->buffer ); free( impl ); }
    return ref;
}

static HRESULT WINAPI usb_async_read_GetIids( __FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32 *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IAsyncOperationWithProgress_IBuffer_UINT32 };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}
static HRESULT WINAPI usb_async_read_GetRuntimeClassName( __FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32 *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Foundation.IAsyncOperationWithProgress`2<Windows.Storage.Streams.IBuffer,UInt32>";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI usb_async_read_GetTrustLevel( __FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32 *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI usb_async_read_put_Progress( __FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32 *iface,
    __FIAsyncOperationProgressHandler_2_Windows__CStorage__CStreams__CIBuffer_UINT32 *handler )
{ return S_OK; }
static HRESULT WINAPI usb_async_read_get_Progress( __FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32 *iface,
    __FIAsyncOperationProgressHandler_2_Windows__CStorage__CStreams__CIBuffer_UINT32 **handler )
{ if (handler) *handler = NULL; return S_OK; }
static HRESULT WINAPI usb_async_read_put_Completed( __FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32 *iface,
    __FIAsyncOperationWithProgressCompletedHandler_2_Windows__CStorage__CStreams__CIBuffer_UINT32 *handler )
{ return S_OK; }
static HRESULT WINAPI usb_async_read_get_Completed( __FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32 *iface,
    __FIAsyncOperationWithProgressCompletedHandler_2_Windows__CStorage__CStreams__CIBuffer_UINT32 **handler )
{ if (handler) *handler = NULL; return S_OK; }
static HRESULT WINAPI usb_async_read_GetResults( __FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32 *iface, IBuffer **result )
{
    struct usb_async_read *impl = impl_from_async_read( iface );
    if (!result) return E_INVALIDARG;
    *result = impl->buffer;
    if (impl->buffer) IBuffer_AddRef( impl->buffer );
    return S_OK;
}

static const __FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32Vtbl usb_async_read_vtbl = {
    usb_async_read_QueryInterface,
    usb_async_read_AddRef,
    usb_async_read_Release,
    usb_async_read_GetIids,
    usb_async_read_GetRuntimeClassName,
    usb_async_read_GetTrustLevel,
    usb_async_read_put_Progress,
    usb_async_read_get_Progress,
    usb_async_read_put_Completed,
    usb_async_read_get_Completed,
    usb_async_read_GetResults,
};

struct usb_async_write
{
    __FIAsyncOperationWithProgress_2_UINT32_UINT32 iface;
    LONG ref;
    UINT32 bytes_written;
};

static inline struct usb_async_write *impl_from_async_write( __FIAsyncOperationWithProgress_2_UINT32_UINT32 *iface )
{
    return CONTAINING_RECORD( iface, struct usb_async_write, iface );
}

static HRESULT WINAPI usb_async_write_QueryInterface( __FIAsyncOperationWithProgress_2_UINT32_UINT32 *iface, REFIID iid, void **out )
{
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID___FIAsyncOperationWithProgress_2_UINT32_UINT32 ))
    {
        *out = iface;
        __FIAsyncOperationWithProgress_2_UINT32_UINT32_AddRef( iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_async_write_AddRef( __FIAsyncOperationWithProgress_2_UINT32_UINT32 *iface )
{
    return InterlockedIncrement( &impl_from_async_write( iface )->ref );
}

static ULONG WINAPI usb_async_write_Release( __FIAsyncOperationWithProgress_2_UINT32_UINT32 *iface )
{
    struct usb_async_write *impl = impl_from_async_write( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref) free( impl );
    return ref;
}

static HRESULT WINAPI usb_async_write_GetIids( __FIAsyncOperationWithProgress_2_UINT32_UINT32 *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID___FIAsyncOperationWithProgress_2_UINT32_UINT32 };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}
static HRESULT WINAPI usb_async_write_GetRuntimeClassName( __FIAsyncOperationWithProgress_2_UINT32_UINT32 *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Foundation.IAsyncOperationWithProgress`2<UInt32,UInt32>";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI usb_async_write_GetTrustLevel( __FIAsyncOperationWithProgress_2_UINT32_UINT32 *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI usb_async_write_put_Progress( __FIAsyncOperationWithProgress_2_UINT32_UINT32 *iface,
    __FIAsyncOperationProgressHandler_2_UINT32_UINT32 *handler )
{ return S_OK; }
static HRESULT WINAPI usb_async_write_get_Progress( __FIAsyncOperationWithProgress_2_UINT32_UINT32 *iface,
    __FIAsyncOperationProgressHandler_2_UINT32_UINT32 **handler )
{ if (handler) *handler = NULL; return S_OK; }
static HRESULT WINAPI usb_async_write_put_Completed( __FIAsyncOperationWithProgress_2_UINT32_UINT32 *iface,
    __FIAsyncOperationWithProgressCompletedHandler_2_UINT32_UINT32 *handler )
{ return S_OK; }
static HRESULT WINAPI usb_async_write_get_Completed( __FIAsyncOperationWithProgress_2_UINT32_UINT32 *iface,
    __FIAsyncOperationWithProgressCompletedHandler_2_UINT32_UINT32 **handler )
{ if (handler) *handler = NULL; return S_OK; }
static HRESULT WINAPI usb_async_write_GetResults( __FIAsyncOperationWithProgress_2_UINT32_UINT32 *iface, UINT32 *result )
{
    struct usb_async_write *impl = impl_from_async_write( iface );
    if (!result) return E_INVALIDARG;
    *result = impl->bytes_written;
    return S_OK;
}

static const __FIAsyncOperationWithProgress_2_UINT32_UINT32Vtbl usb_async_write_vtbl = {
    usb_async_write_QueryInterface,
    usb_async_write_AddRef,
    usb_async_write_Release,
    usb_async_write_GetIids,
    usb_async_write_GetRuntimeClassName,
    usb_async_write_GetTrustLevel,
    usb_async_write_put_Progress,
    usb_async_write_get_Progress,
    usb_async_write_put_Completed,
    usb_async_write_get_Completed,
    usb_async_write_GetResults,
};

static HRESULT WINAPI usb_input_stream_QueryInterface( IInputStream *iface, REFIID iid, void **out )
{
    struct usb_input_stream *impl = impl_from_usb_input_stream_IInputStream( iface );
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IInputStream ))
    {
        *out = &impl->IInputStream_iface;
        IInputStream_AddRef( iface );
        return S_OK;
    }
    if (IsEqualGUID( iid, &IID_IClosable ))
    {
        *out = &impl->IClosable_iface;
        IClosable_AddRef( (IClosable *)&impl->IClosable_iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static HRESULT WINAPI usb_input_stream_closable_QueryInterface( IClosable *iface, REFIID iid, void **out )
{
    struct usb_input_stream *impl = impl_from_usb_input_stream_IClosable( iface );
    return usb_input_stream_QueryInterface( &impl->IInputStream_iface, iid, out );
}

static ULONG WINAPI usb_input_stream_closable_AddRef( IClosable *iface )
{
    struct usb_input_stream *impl = impl_from_usb_input_stream_IClosable( iface );
    return InterlockedIncrement( &impl->ref );
}

static ULONG WINAPI usb_input_stream_closable_Release( IClosable *iface )
{
    struct usb_input_stream *impl = impl_from_usb_input_stream_IClosable( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref)
    {
        if (impl->pipe) IUsbBulkInPipe_Release( impl->pipe );
        free( impl );
    }
    return ref;
}

static ULONG WINAPI usb_input_stream_AddRef( IInputStream *iface )
{
    struct usb_input_stream *impl = impl_from_usb_input_stream_IInputStream( iface );
    return InterlockedIncrement( &impl->ref );
}

static ULONG WINAPI usb_input_stream_Release( IInputStream *iface )
{
    struct usb_input_stream *impl = impl_from_usb_input_stream_IInputStream( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref)
    {
        if (impl->pipe) IUsbBulkInPipe_Release( impl->pipe );
        free( impl );
    }
    return ref;
}

static HRESULT WINAPI usb_input_stream_GetIids( IInputStream *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IInputStream };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}
static HRESULT WINAPI usb_input_stream_GetRuntimeClassName( IInputStream *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Storage.Streams.IInputStream";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI usb_input_stream_GetTrustLevel( IInputStream *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI usb_input_stream_ReadAsync( IInputStream *iface, IBuffer *buffer, UINT32 count,
    InputStreamOptions options, __FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32 **operation )
{
    struct usb_input_stream *impl = impl_from_usb_input_stream_IInputStream( iface );
    struct usb_bulk_in_pipe *pipe_impl = impl_from_IUsbBulkInPipe( impl->pipe );
    struct usb_async_read *op = NULL;
    IBufferByteAccess *byte_access = NULL;
    UINT32 capacity;
    BYTE *data;
    ULONG transferred = 0;
    HRESULT hr;

    if (!buffer || !operation) return E_INVALIDARG;
    *operation = NULL;

    hr = IBuffer_get_Capacity( buffer, &capacity );
    if (FAILED( hr )) return hr;
    if (count > capacity) count = capacity;
    if (!count) { hr = IBuffer_put_Length( buffer, 0 ); if (FAILED(hr)) return hr; goto done_read; }

    hr = IBuffer_QueryInterface( buffer, &IID_IBufferByteAccess, (void **)&byte_access );
    if (FAILED( hr )) return hr;
    hr = IBufferByteAccess_Buffer( byte_access, &data );
    IBufferByteAccess_Release( byte_access );
    if (FAILED( hr )) return hr;

    if (!WinUsb_ReadPipe( pipe_impl->device->winusb, pipe_impl->endpoint_address, data, count, &transferred, NULL ))
    {
        return HRESULT_FROM_WIN32( GetLastError() );
    }
    hr = IBuffer_put_Length( buffer, (UINT32)transferred );
    if (FAILED( hr )) return hr;

done_read:
    if (!(op = calloc( 1, sizeof(*op) ))) return E_OUTOFMEMORY;
    op->iface.lpVtbl = &usb_async_read_vtbl;
    op->ref = 1;
    op->buffer = buffer;
    IBuffer_AddRef( buffer );
    *operation = &op->iface;
    return S_OK;
}

static const IInputStreamVtbl usb_input_stream_vtbl = {
    usb_input_stream_QueryInterface,
    usb_input_stream_AddRef,
    usb_input_stream_Release,
    usb_input_stream_GetIids,
    usb_input_stream_GetRuntimeClassName,
    usb_input_stream_GetTrustLevel,
    usb_input_stream_ReadAsync,
};

static HRESULT WINAPI usb_input_stream_Close( IClosable *iface )
{
    (void)iface;
    return S_OK;
}

static HRESULT WINAPI usb_input_stream_closable_GetIids( IClosable *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IClosable };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}
static HRESULT WINAPI usb_input_stream_closable_GetRuntimeClassName( IClosable *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Foundation.IClosable";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI usb_input_stream_closable_GetTrustLevel( IClosable *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static const IClosableVtbl usb_input_stream_closable_vtbl = {
    usb_input_stream_closable_QueryInterface,
    usb_input_stream_closable_AddRef,
    usb_input_stream_closable_Release,
    usb_input_stream_closable_GetIids,
    usb_input_stream_closable_GetRuntimeClassName,
    usb_input_stream_closable_GetTrustLevel,
    usb_input_stream_Close,
};

static HRESULT usb_input_stream_create( struct usb_bulk_in_pipe *pipe, IInputStream **out )
{
    struct usb_input_stream *impl;
    if (!out) return E_INVALIDARG;
    *out = NULL;
    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IInputStream_iface.lpVtbl = &usb_input_stream_vtbl;
    impl->IClosable_iface.lpVtbl = &usb_input_stream_closable_vtbl;
    impl->ref = 1;
    impl->pipe = (IUsbBulkInPipe *)&pipe->IUsbBulkInPipe_iface;
    IUsbBulkInPipe_AddRef( impl->pipe );
    *out = &impl->IInputStream_iface;
    return S_OK;
}

/* USB output stream (IOutputStream over WinUsb_WritePipe) */
struct usb_output_stream
{
    IOutputStream IOutputStream_iface;
    IClosable IClosable_iface;
    LONG ref;
    struct usb_device *device;
    UCHAR endpoint_address;
    IUnknown *ref_holder;
};

static inline struct usb_output_stream *impl_from_usb_output_stream_IOutputStream( IOutputStream *iface )
{
    return CONTAINING_RECORD( iface, struct usb_output_stream, IOutputStream_iface );
}

static HRESULT WINAPI usb_output_stream_QueryInterface( IOutputStream *iface, REFIID iid, void **out )
{
    struct usb_output_stream *impl = impl_from_usb_output_stream_IOutputStream( iface );
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IOutputStream ))
    {
        *out = &impl->IOutputStream_iface;
        IOutputStream_AddRef( iface );
        return S_OK;
    }
    if (IsEqualGUID( iid, &IID_IClosable ))
    {
        *out = &impl->IClosable_iface;
        IClosable_AddRef( (IClosable *)&impl->IClosable_iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static inline struct usb_output_stream *impl_from_usb_output_stream_IClosable( IClosable *iface )
{
    return CONTAINING_RECORD( iface, struct usb_output_stream, IClosable_iface );
}

static HRESULT WINAPI usb_output_stream_closable_QueryInterface( IClosable *iface, REFIID iid, void **out )
{
    struct usb_output_stream *impl = impl_from_usb_output_stream_IClosable( iface );
    return usb_output_stream_QueryInterface( &impl->IOutputStream_iface, iid, out );
}

static ULONG WINAPI usb_output_stream_closable_AddRef( IClosable *iface )
{
    return InterlockedIncrement( &impl_from_usb_output_stream_IClosable( iface )->ref );
}

static ULONG WINAPI usb_output_stream_closable_Release( IClosable *iface )
{
    struct usb_output_stream *impl = impl_from_usb_output_stream_IClosable( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref) { if (impl->ref_holder) IUnknown_Release( impl->ref_holder ); free( impl ); }
    return ref;
}

static HRESULT WINAPI usb_output_stream_closable_GetIids( IClosable *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IClosable };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}
static HRESULT WINAPI usb_output_stream_closable_GetRuntimeClassName( IClosable *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Foundation.IClosable";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI usb_output_stream_closable_GetTrustLevel( IClosable *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static ULONG WINAPI usb_output_stream_AddRef( IOutputStream *iface )
{
    return InterlockedIncrement( &impl_from_usb_output_stream_IOutputStream( iface )->ref );
}

static ULONG WINAPI usb_output_stream_Release( IOutputStream *iface )
{
    struct usb_output_stream *impl = impl_from_usb_output_stream_IOutputStream( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref) { if (impl->ref_holder) IUnknown_Release( impl->ref_holder ); free( impl ); }
    return ref;
}

static HRESULT WINAPI usb_output_stream_GetIids( IOutputStream *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IOutputStream };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}
static HRESULT WINAPI usb_output_stream_GetRuntimeClassName( IOutputStream *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Storage.Streams.IOutputStream";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI usb_output_stream_GetTrustLevel( IOutputStream *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI usb_output_stream_WriteAsync( IOutputStream *iface, IBuffer *buffer,
    __FIAsyncOperationWithProgress_2_UINT32_UINT32 **operation )
{
    struct usb_output_stream *impl = impl_from_usb_output_stream_IOutputStream( iface );
    struct usb_async_write *op = NULL;
    IBufferByteAccess *byte_access = NULL;
    UINT32 length;
    BYTE *data;
    ULONG written = 0;

    if (!buffer || !operation) return E_INVALIDARG;
    *operation = NULL;

    if (FAILED( IBuffer_get_Length( buffer, &length ) ) || !length)
    {
        if (!(op = calloc( 1, sizeof(*op) ))) return E_OUTOFMEMORY;
        op->iface.lpVtbl = &usb_async_write_vtbl;
        op->ref = 1;
        op->bytes_written = 0;
        *operation = &op->iface;
        return S_OK;
    }
    if (FAILED( IBuffer_QueryInterface( buffer, &IID_IBufferByteAccess, (void **)&byte_access ) ))
        return E_FAIL;
    if (FAILED( IBufferByteAccess_Buffer( byte_access, &data ) ))
    {
        IBufferByteAccess_Release( byte_access );
        return E_FAIL;
    }
    if (!WinUsb_WritePipe( impl->device->winusb, impl->endpoint_address, data, length, &written, NULL ))
    {
        IBufferByteAccess_Release( byte_access );
        return HRESULT_FROM_WIN32( GetLastError() );
    }
    IBufferByteAccess_Release( byte_access );

    if (!(op = calloc( 1, sizeof(*op) ))) return E_OUTOFMEMORY;
    op->iface.lpVtbl = &usb_async_write_vtbl;
    op->ref = 1;
    op->bytes_written = (UINT32)written;
    *operation = &op->iface;
    return S_OK;
}

static HRESULT WINAPI usb_output_stream_FlushAsync( IOutputStream *iface, IAsyncOperation_boolean **operation )
{
    if (!operation) return E_INVALIDARG;
    *operation = NULL;
    return async_boolean_create( TRUE, operation );
}

static const IOutputStreamVtbl usb_output_stream_vtbl = {
    usb_output_stream_QueryInterface,
    usb_output_stream_AddRef,
    usb_output_stream_Release,
    usb_output_stream_GetIids,
    usb_output_stream_GetRuntimeClassName,
    usb_output_stream_GetTrustLevel,
    usb_output_stream_WriteAsync,
    usb_output_stream_FlushAsync,
};

static HRESULT WINAPI usb_output_stream_Close( IClosable *iface )
{
    (void)iface;
    return S_OK;
}

static const IClosableVtbl usb_output_stream_closable_vtbl = {
    usb_output_stream_closable_QueryInterface,
    usb_output_stream_closable_AddRef,
    usb_output_stream_closable_Release,
    usb_output_stream_closable_GetIids,
    usb_output_stream_closable_GetRuntimeClassName,
    usb_output_stream_closable_GetTrustLevel,
    usb_output_stream_Close,
};

static HRESULT usb_output_stream_create_ex( struct usb_device *device, UCHAR endpoint_address,
    IUnknown *ref_holder, IOutputStream **out )
{
    struct usb_output_stream *impl;
    if (!out || !device || !ref_holder) return E_INVALIDARG;
    *out = NULL;
    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IOutputStream_iface.lpVtbl = &usb_output_stream_vtbl;
    impl->IClosable_iface.lpVtbl = &usb_output_stream_closable_vtbl;
    impl->ref = 1;
    impl->device = device;
    impl->endpoint_address = endpoint_address;
    impl->ref_holder = ref_holder;
    IUnknown_AddRef( ref_holder );
    *out = &impl->IOutputStream_iface;
    return S_OK;
}

static HRESULT usb_output_stream_create( struct usb_bulk_out_pipe *pipe, IOutputStream **out )
{
    return usb_output_stream_create_ex( pipe->device, pipe->endpoint_address,
        (IUnknown *)&pipe->IUsbBulkOutPipe_iface, out );
}

struct usb_interface_obj
{
    IUsbInterface IUsbInterface_iface;
    LONG ref;
    struct usb_device *device;
    BYTE interface_number;
    BYTE alternate_setting_number;
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor *descriptors;
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe *bulk_in_pipes;
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe *bulk_out_pipes;
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe *interrupt_in_pipes;
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe *interrupt_out_pipes;
    USB_ENDPOINT_DESCRIPTOR *endpoints;
    UINT32 endpoint_count;
};

static inline struct usb_interface_obj *impl_from_IUsbInterface( IUsbInterface *iface )
{
    return CONTAINING_RECORD( iface, struct usb_interface_obj, IUsbInterface_iface );
}

static HRESULT WINAPI usb_interface_QueryInterface( IUsbInterface *iface, REFIID iid, void **out )
{
    TRACE( "iface %p, iid %s, out %p.\n", iface, debugstr_guid( iid ), out );

    if (IsEqualGUID( iid, &IID_IUnknown ) ||
        IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAgileObject ) ||
        IsEqualGUID( iid, &IID_IUsbInterface ))
    {
        IUsbInterface_AddRef( iface );
        *out = iface;
        return S_OK;
    }

    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_interface_AddRef( IUsbInterface *iface )
{
    struct usb_interface_obj *impl = impl_from_IUsbInterface( iface );
    return InterlockedIncrement( &impl->ref );
}

static ULONG WINAPI usb_interface_Release( IUsbInterface *iface )
{
    struct usb_interface_obj *impl = impl_from_IUsbInterface( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );

    if (!ref)
    {
        if (impl->descriptors)
            __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor_Release( impl->descriptors );
        if (impl->bulk_in_pipes)
            __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe_Release( impl->bulk_in_pipes );
        if (impl->bulk_out_pipes)
            __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe_Release( impl->bulk_out_pipes );
        if (impl->interrupt_in_pipes)
            __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe_Release( impl->interrupt_in_pipes );
        if (impl->interrupt_out_pipes)
            __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe_Release( impl->interrupt_out_pipes );
        free( impl->endpoints );
        free( impl );
    }

    return ref;
}

static HRESULT WINAPI usb_interface_GetIids( IUsbInterface *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IUsbInterface };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}

static HRESULT WINAPI usb_interface_GetRuntimeClassName( IUsbInterface *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbInterface";

    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}

static HRESULT WINAPI usb_interface_GetTrustLevel( IUsbInterface *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI usb_interface_get_BulkInPipes( IUsbInterface *iface,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe **value )
{
    struct usb_interface_obj *impl = impl_from_IUsbInterface( iface );

    TRACE( "iface %p, value %p.\n", iface, value );

    if (!value) return E_INVALIDARG;
    *value = NULL;

    if (impl->bulk_in_pipes)
    {
        *value = impl->bulk_in_pipes;
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInPipe_AddRef( *value );
        return S_OK;
    }

    /* Пока пайпы не строим — возвращаем пустой список,
       чтобы API работало без E_NOTIMPL. */
    return usb_bulk_in_pipes_create( NULL, 0, value );
}

static HRESULT WINAPI usb_interface_get_InterruptInPipes( IUsbInterface *iface,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe **value )
{
    struct usb_interface_obj *impl = impl_from_IUsbInterface( iface );
    if (!value) return E_INVALIDARG;
    *value = NULL;
    if (impl->interrupt_in_pipes)
    {
        *value = impl->interrupt_in_pipes;
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInPipe_AddRef( *value );
        return S_OK;
    }
    return usb_interrupt_in_pipes_create( NULL, 0, value );
}

static HRESULT WINAPI usb_interface_get_BulkOutPipes( IUsbInterface *iface,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe **value )
{
    struct usb_interface_obj *impl = impl_from_IUsbInterface( iface );

    TRACE( "iface %p, value %p.\n", iface, value );

    if (!value) return E_INVALIDARG;
    *value = NULL;

    if (impl->bulk_out_pipes)
    {
        *value = impl->bulk_out_pipes;
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutPipe_AddRef( *value );
        return S_OK;
    }

    return usb_bulk_out_pipes_create( NULL, 0, value );
}

static HRESULT WINAPI usb_interface_get_InterruptOutPipes( IUsbInterface *iface,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe **value )
{
    struct usb_interface_obj *impl = impl_from_IUsbInterface( iface );
    if (!value) return E_INVALIDARG;
    *value = NULL;
    if (impl->interrupt_out_pipes)
    {
        *value = impl->interrupt_out_pipes;
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutPipe_AddRef( *value );
        return S_OK;
    }
    return usb_interrupt_out_pipes_create( NULL, 0, value );
}

static HRESULT WINAPI usb_interface_get_InterfaceSettings( IUsbInterface *iface,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSetting **value )
{
    struct usb_interface_obj *impl = impl_from_IUsbInterface( iface );
    IUsbConfiguration *config = NULL;
    struct usb_configuration *config_impl;
    BYTE *ptr, *end;
    IUsbInterfaceSetting **settings = NULL;
    UINT32 count = 0, capacity = 0;
    HRESULT hr;

    if (!value) return E_INVALIDARG;
    *value = NULL;

    if (!impl->device || !impl->device->configuration) return S_OK;
    config = impl->device->configuration;
    config_impl = impl_from_IUsbConfiguration( config );
    hr = usb_configuration_ensure_raw_descriptor( config_impl );
    if (FAILED( hr )) return hr;
    if (!config_impl->raw_config) return S_OK;

    ptr = config_impl->raw_config + config_impl->raw_config[0];
    end = config_impl->raw_config + config_impl->raw_config_len;

    while (ptr + sizeof(USB_INTERFACE_DESCRIPTOR) <= end)
    {
        const USB_INTERFACE_DESCRIPTOR *idesc = (const USB_INTERFACE_DESCRIPTOR *)ptr;
        BYTE *start, *next, *scan;
        if (idesc->bLength < sizeof(USB_INTERFACE_DESCRIPTOR) || idesc->bDescriptorType != USB_INTERFACE_DESCRIPTOR_TYPE)
            break;
        start = ptr;
        next = ptr + idesc->bLength;
        scan = next;
        while (scan + 2 <= end)
        {
            BYTE l = scan[0];
            if (!l || scan + l > end) { next = end; break; }
            if (scan[1] == USB_INTERFACE_DESCRIPTOR_TYPE || scan[1] == USB_CONFIGURATION_DESCRIPTOR_TYPE)
            { next = scan; break; }
            scan += l;
        }
        if (idesc->bInterfaceNumber != impl->interface_number)
        {
            ptr = next;
            continue;
        }
        {
            if (count >= capacity)
            {
                UINT32 new_cap = capacity ? capacity * 2 : 4;
                IUsbInterfaceSetting **new_arr = realloc( settings, new_cap * sizeof(*new_arr) );
                if (!new_arr) { hr = E_OUTOFMEMORY; goto cleanup; }
                settings = new_arr;
                capacity = new_cap;
            }
            hr = usb_interface_setting_create( impl->device, start, next, &settings[count] );
            if (FAILED( hr )) goto cleanup;
            count++;
            ptr = next;
        }
    }

    hr = usb_interface_settings_view_create( settings, count, value );
cleanup:
    if (settings)
    {
        while (count--) if (settings[count]) IUsbInterfaceSetting_Release( settings[count] );
        free( settings );
    }
    return hr;
}

static HRESULT WINAPI usb_interface_get_InterfaceNumber( IUsbInterface *iface, BYTE *value )
{
    struct usb_interface_obj *impl = impl_from_IUsbInterface( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->interface_number;
    return S_OK;
}

static HRESULT WINAPI usb_interface_get_Descriptors( IUsbInterface *iface,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor **value )
{
    struct usb_interface_obj *impl = impl_from_IUsbInterface( iface );

    if (!value) return E_INVALIDARG;
    *value = NULL;

    if (!impl->descriptors) return S_OK;

    *value = impl->descriptors;
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor_AddRef( *value );
    return S_OK;
}

static const IUsbInterfaceVtbl usb_interface_vtbl =
{
    usb_interface_QueryInterface,
    usb_interface_AddRef,
    usb_interface_Release,
    usb_interface_GetIids,
    usb_interface_GetRuntimeClassName,
    usb_interface_GetTrustLevel,
    usb_interface_get_BulkInPipes,
    usb_interface_get_InterruptInPipes,
    usb_interface_get_BulkOutPipes,
    usb_interface_get_InterruptOutPipes,
    usb_interface_get_InterfaceSettings,
    usb_interface_get_InterfaceNumber,
    usb_interface_get_Descriptors,
};

static HRESULT usb_interface_create( struct usb_device *device, const BYTE *start, const BYTE *end, IUsbInterface **out )
{
    const USB_INTERFACE_DESCRIPTOR *desc;
    IUsbDescriptor **items = NULL;
    UINT32 count = 0;
    const BYTE *ptr;
    USB_ENDPOINT_DESCRIPTOR *eps = NULL;
    UINT32 ep_count = 0, ep_index = 0;
    IUsbBulkInPipe **bulk_in_pipes = NULL;
    UINT32 bulk_in_count = 0, bulk_in_index = 0;
    IUsbBulkOutPipe **bulk_out_pipes = NULL;
    UINT32 bulk_out_count = 0, bulk_out_index = 0;
    IUsbInterruptInPipe **interrupt_in_pipes = NULL;
    UINT32 interrupt_in_count = 0, interrupt_in_index = 0;
    IUsbInterruptOutPipe **interrupt_out_pipes = NULL;
    UINT32 interrupt_out_count = 0, interrupt_out_index = 0;
    HRESULT hr;
    struct usb_interface_obj *impl;

    if (!out) return E_INVALIDARG;
    *out = NULL;

    if (start + sizeof(USB_INTERFACE_DESCRIPTOR) > end) return E_FAIL;
    desc = (const USB_INTERFACE_DESCRIPTOR *)start;
    if (desc->bLength < sizeof(USB_INTERFACE_DESCRIPTOR) ||
        desc->bDescriptorType != USB_INTERFACE_DESCRIPTOR_TYPE)
        return E_INVALIDARG;

    ptr = start;
    while (ptr + 2 <= end)
    {
        BYTE len = ptr[0];
        if (!len || ptr + len > end) break;

        if (ptr[1] == USB_ENDPOINT_DESCRIPTOR_TYPE && len >= sizeof(USB_ENDPOINT_DESCRIPTOR))
            ep_count++;

        count++;
        ptr += len;
    }

    if (!(items = calloc( count, sizeof(*items) )))
        return E_OUTOFMEMORY;

    if (ep_count && !(eps = calloc( ep_count, sizeof(*eps) )))
    {
        free( items );
        return E_OUTOFMEMORY;
    }

    ptr = start;
    count = 0;
    while (ptr + 2 <= end)
    {
        BYTE len = ptr[0];
        HRESULT hr2;

        if (!len || ptr + len > end) break;

        if (ptr[1] == USB_ENDPOINT_DESCRIPTOR_TYPE && len >= sizeof(USB_ENDPOINT_DESCRIPTOR) && eps)
        {
            memcpy( &eps[ep_index], ptr, sizeof(USB_ENDPOINT_DESCRIPTOR) );
            ep_index++;
        }

        hr2 = usb_descriptor_create( ptr, len, &items[count] );
        if (FAILED( hr2 ))
        {
            UINT32 i;
            for (i = 0; i < count; ++i)
                if (items[i]) IUsbDescriptor_Release( items[i] );
            free( items );
            free( eps );
            return hr2;
        }

        count++;
        ptr += len;
    }

    /* Build bulk-in / bulk-out / interrupt-in / interrupt-out pipes from endpoints */
    for (ep_index = 0; ep_index < ep_count; ++ep_index)
    {
        UCHAR addr = eps[ep_index].bEndpointAddress;
        UCHAR attrs = eps[ep_index].bmAttributes;
        if ((addr & 0x80) && ((attrs & 0x03) == USB_ENDPOINT_TYPE_BULK))
            bulk_in_count++;
        else if (!(addr & 0x80) && ((attrs & 0x03) == USB_ENDPOINT_TYPE_BULK))
            bulk_out_count++;
        else if ((addr & 0x80) && ((attrs & 0x03) == USB_ENDPOINT_TYPE_INTERRUPT))
            interrupt_in_count++;
        else if (!(addr & 0x80) && ((attrs & 0x03) == USB_ENDPOINT_TYPE_INTERRUPT))
            interrupt_out_count++;
    }

    if (bulk_in_count && !(bulk_in_pipes = calloc( bulk_in_count, sizeof(*bulk_in_pipes) )))
    {
        UINT32 i;
        for (i = 0; i < count; ++i)
            if (items[i]) IUsbDescriptor_Release( items[i] );
        free( items );
        free( eps );
        return E_OUTOFMEMORY;
    }

    if (bulk_out_count && !(bulk_out_pipes = calloc( bulk_out_count, sizeof(*bulk_out_pipes) )))
    {
        UINT32 i;
        for (i = 0; i < count; ++i)
            if (items[i]) IUsbDescriptor_Release( items[i] );
        if (bulk_in_pipes)
        {
            for (i = 0; i < bulk_in_count; ++i)
                if (bulk_in_pipes[i]) IUsbBulkInPipe_Release( bulk_in_pipes[i] );
            free( bulk_in_pipes );
        }
        free( items );
        free( eps );
        return E_OUTOFMEMORY;
    }

    if (interrupt_in_count && !(interrupt_in_pipes = calloc( interrupt_in_count, sizeof(*interrupt_in_pipes) )))
    {
        UINT32 i;
        for (i = 0; i < count; ++i)
            if (items[i]) IUsbDescriptor_Release( items[i] );
        if (bulk_in_pipes)
        {
            for (i = 0; i < bulk_in_count; ++i)
                if (bulk_in_pipes[i]) IUsbBulkInPipe_Release( bulk_in_pipes[i] );
            free( bulk_in_pipes );
        }
        if (bulk_out_pipes)
        {
            for (i = 0; i < bulk_out_count; ++i)
                if (bulk_out_pipes[i]) IUsbBulkOutPipe_Release( bulk_out_pipes[i] );
            free( bulk_out_pipes );
        }
        free( items );
        free( eps );
        return E_OUTOFMEMORY;
    }

    if (interrupt_out_count && !(interrupt_out_pipes = calloc( interrupt_out_count, sizeof(*interrupt_out_pipes) )))
    {
        UINT32 i;
        for (i = 0; i < count; ++i)
            if (items[i]) IUsbDescriptor_Release( items[i] );
        if (bulk_in_pipes)
        {
            for (i = 0; i < bulk_in_count; ++i)
                if (bulk_in_pipes[i]) IUsbBulkInPipe_Release( bulk_in_pipes[i] );
            free( bulk_in_pipes );
        }
        if (bulk_out_pipes)
        {
            for (i = 0; i < bulk_out_count; ++i)
                if (bulk_out_pipes[i]) IUsbBulkOutPipe_Release( bulk_out_pipes[i] );
            free( bulk_out_pipes );
        }
        if (interrupt_in_pipes) free( interrupt_in_pipes );
        free( items );
        free( eps );
        return E_OUTOFMEMORY;
    }

    for (ep_index = 0; ep_index < ep_count; ++ep_index)
    {
        UCHAR addr = eps[ep_index].bEndpointAddress;
        UCHAR attrs = eps[ep_index].bmAttributes;

        if ((addr & 0x80) && ((attrs & 0x03) == USB_ENDPOINT_TYPE_BULK))
        {
            HRESULT hr2 = usb_bulk_in_pipe_create( device, &eps[ep_index], &bulk_in_pipes[bulk_in_index] );
            if (FAILED( hr2 ))
            {
                UINT32 i;
                for (i = 0; i < bulk_in_index; ++i)
                    if (bulk_in_pipes[i]) IUsbBulkInPipe_Release( bulk_in_pipes[i] );
                if (bulk_out_pipes)
                {
                    for (i = 0; i < bulk_out_index; ++i)
                        if (bulk_out_pipes[i]) IUsbBulkOutPipe_Release( bulk_out_pipes[i] );
                    free( bulk_out_pipes );
                }
                for (i = 0; i < count; ++i)
                    if (items[i]) IUsbDescriptor_Release( items[i] );
                free( bulk_in_pipes );
                free( items );
                free( eps );
                return hr2;
            }
            bulk_in_index++;
        }
        else if (!(addr & 0x80) && ((attrs & 0x03) == USB_ENDPOINT_TYPE_BULK))
        {
            HRESULT hr2 = usb_bulk_out_pipe_create( device, &eps[ep_index], &bulk_out_pipes[bulk_out_index] );
            if (FAILED( hr2 ))
            {
                UINT32 i;
                for (i = 0; i < bulk_in_index; ++i)
                    if (bulk_in_pipes[i]) IUsbBulkInPipe_Release( bulk_in_pipes[i] );
                if (bulk_out_pipes)
                {
                    for (i = 0; i < bulk_out_index; ++i)
                        if (bulk_out_pipes[i]) IUsbBulkOutPipe_Release( bulk_out_pipes[i] );
                    free( bulk_out_pipes );
                }
                for (i = 0; i < count; ++i)
                    if (items[i]) IUsbDescriptor_Release( items[i] );
                free( bulk_in_pipes );
                free( items );
                free( eps );
                return hr2;
            }
            bulk_out_index++;
        }
        else if ((addr & 0x80) && ((attrs & 0x03) == USB_ENDPOINT_TYPE_INTERRUPT))
        {
            HRESULT hr2 = usb_interrupt_in_pipe_create( device, &eps[ep_index], &interrupt_in_pipes[interrupt_in_index] );
            if (FAILED( hr2 ))
            {
                UINT32 i;
                for (i = 0; i < bulk_in_index; ++i)
                    if (bulk_in_pipes[i]) IUsbBulkInPipe_Release( bulk_in_pipes[i] );
                if (bulk_out_pipes)
                {
                    for (i = 0; i < bulk_out_index; ++i)
                        if (bulk_out_pipes[i]) IUsbBulkOutPipe_Release( bulk_out_pipes[i] );
                    free( bulk_out_pipes );
                }
                for (i = 0; i < interrupt_in_index; ++i)
                    if (interrupt_in_pipes[i]) IUsbInterruptInPipe_Release( interrupt_in_pipes[i] );
                for (i = 0; i < count; ++i)
                    if (items[i]) IUsbDescriptor_Release( items[i] );
                free( bulk_in_pipes );
                if (interrupt_in_pipes) free( interrupt_in_pipes );
                if (interrupt_out_pipes) free( interrupt_out_pipes );
                free( items );
                free( eps );
                return hr2;
            }
            interrupt_in_index++;
        }
        else if (!(addr & 0x80) && ((attrs & 0x03) == USB_ENDPOINT_TYPE_INTERRUPT))
        {
            HRESULT hr2 = usb_interrupt_out_pipe_create( device, &eps[ep_index], &interrupt_out_pipes[interrupt_out_index] );
            if (FAILED( hr2 ))
            {
                UINT32 i;
                for (i = 0; i < bulk_in_index; ++i)
                    if (bulk_in_pipes[i]) IUsbBulkInPipe_Release( bulk_in_pipes[i] );
                if (bulk_out_pipes)
                {
                    for (i = 0; i < bulk_out_index; ++i)
                        if (bulk_out_pipes[i]) IUsbBulkOutPipe_Release( bulk_out_pipes[i] );
                    free( bulk_out_pipes );
                }
                for (i = 0; i < interrupt_in_index; ++i)
                    if (interrupt_in_pipes[i]) IUsbInterruptInPipe_Release( interrupt_in_pipes[i] );
                for (i = 0; i < interrupt_out_index; ++i)
                    if (interrupt_out_pipes[i]) IUsbInterruptOutPipe_Release( interrupt_out_pipes[i] );
                for (i = 0; i < count; ++i)
                    if (items[i]) IUsbDescriptor_Release( items[i] );
                free( bulk_in_pipes );
                if (interrupt_in_pipes) free( interrupt_in_pipes );
                if (interrupt_out_pipes) free( interrupt_out_pipes );
                free( items );
                free( eps );
                return hr2;
            }
            interrupt_out_index++;
        }
    }

    if (!(impl = calloc( 1, sizeof(*impl) )))
    {
        UINT32 i;
        for (i = 0; i < count; ++i)
            if (items[i]) IUsbDescriptor_Release( items[i] );
        if (bulk_in_pipes)
        {
            for (i = 0; i < bulk_in_index; ++i)
                if (bulk_in_pipes[i]) IUsbBulkInPipe_Release( bulk_in_pipes[i] );
            free( bulk_in_pipes );
        }
        if (bulk_out_pipes)
        {
            for (i = 0; i < bulk_out_index; ++i)
                if (bulk_out_pipes[i]) IUsbBulkOutPipe_Release( bulk_out_pipes[i] );
            free( bulk_out_pipes );
        }
        if (interrupt_in_pipes)
        {
            for (i = 0; i < interrupt_in_index; ++i)
                if (interrupt_in_pipes[i]) IUsbInterruptInPipe_Release( interrupt_in_pipes[i] );
            free( interrupt_in_pipes );
        }
        if (interrupt_out_pipes)
        {
            for (i = 0; i < interrupt_out_index; ++i)
                if (interrupt_out_pipes[i]) IUsbInterruptOutPipe_Release( interrupt_out_pipes[i] );
            free( interrupt_out_pipes );
        }
        free( items );
        free( eps );
        return E_OUTOFMEMORY;
    }

    impl->IUsbInterface_iface.lpVtbl = &usb_interface_vtbl;
    impl->ref = 1;
    impl->device = device;
    impl->interface_number = desc->bInterfaceNumber;
    impl->alternate_setting_number = desc->bAlternateSetting;
    impl->endpoints = eps;
    impl->endpoint_count = ep_index;
    eps = NULL;

    hr = usb_descriptor_vector_view_create( items, count, &impl->descriptors );
    if (FAILED( hr ))
    {
        IUsbInterface_Release( &impl->IUsbInterface_iface );
        {
            UINT32 i;
            for (i = 0; i < count; ++i)
                if (items[i]) IUsbDescriptor_Release( items[i] );
        }
        if (bulk_in_pipes)
        {
            UINT32 i;
            for (i = 0; i < bulk_in_index; ++i)
                if (bulk_in_pipes[i]) IUsbBulkInPipe_Release( bulk_in_pipes[i] );
            free( bulk_in_pipes );
        }
        if (bulk_out_pipes)
        {
            UINT32 i;
            for (i = 0; i < bulk_out_index; ++i)
                if (bulk_out_pipes[i]) IUsbBulkOutPipe_Release( bulk_out_pipes[i] );
            free( bulk_out_pipes );
        }
        if (interrupt_in_pipes)
        {
            UINT32 i;
            for (i = 0; i < interrupt_in_index; ++i)
                if (interrupt_in_pipes[i]) IUsbInterruptInPipe_Release( interrupt_in_pipes[i] );
            free( interrupt_in_pipes );
        }
        if (interrupt_out_pipes)
        {
            UINT32 i;
            for (i = 0; i < interrupt_out_index; ++i)
                if (interrupt_out_pipes[i]) IUsbInterruptOutPipe_Release( interrupt_out_pipes[i] );
            free( interrupt_out_pipes );
        }
        free( items );
        free( eps );
        return hr;
    }

    if (bulk_in_pipes && bulk_in_index)
    {
        hr = usb_bulk_in_pipes_create( bulk_in_pipes, bulk_in_index, &impl->bulk_in_pipes );
        if (FAILED( hr ))
        {
            UINT32 i;
            for (i = 0; i < bulk_in_index; ++i)
                if (bulk_in_pipes[i]) IUsbBulkInPipe_Release( bulk_in_pipes[i] );
            free( bulk_in_pipes );
            if (bulk_out_pipes) { for (i = 0; i < bulk_out_index; ++i) if (bulk_out_pipes[i]) IUsbBulkOutPipe_Release( bulk_out_pipes[i] ); free( bulk_out_pipes ); }
            if (interrupt_in_pipes) { for (i = 0; i < interrupt_in_index; ++i) if (interrupt_in_pipes[i]) IUsbInterruptInPipe_Release( interrupt_in_pipes[i] ); free( interrupt_in_pipes ); }
            if (interrupt_out_pipes) { for (i = 0; i < interrupt_out_index; ++i) if (interrupt_out_pipes[i]) IUsbInterruptOutPipe_Release( interrupt_out_pipes[i] ); free( interrupt_out_pipes ); }
            free( items );
            free( eps );
            IUsbInterface_Release( &impl->IUsbInterface_iface );
            return hr;
        }
    }

    if (bulk_out_pipes && bulk_out_index)
    {
        hr = usb_bulk_out_pipes_create( bulk_out_pipes, bulk_out_index, &impl->bulk_out_pipes );
        if (FAILED( hr ))
        {
            UINT32 i;
            for (i = 0; i < bulk_out_index; ++i)
                if (bulk_out_pipes[i]) IUsbBulkOutPipe_Release( bulk_out_pipes[i] );
            free( bulk_out_pipes );
            if (interrupt_in_pipes) { for (i = 0; i < interrupt_in_index; ++i) if (interrupt_in_pipes[i]) IUsbInterruptInPipe_Release( interrupt_in_pipes[i] ); free( interrupt_in_pipes ); }
            if (interrupt_out_pipes) { for (i = 0; i < interrupt_out_index; ++i) if (interrupt_out_pipes[i]) IUsbInterruptOutPipe_Release( interrupt_out_pipes[i] ); free( interrupt_out_pipes ); }
            free( items );
            free( eps );
            IUsbInterface_Release( &impl->IUsbInterface_iface );
            return hr;
        }
    }

    if (interrupt_in_pipes && interrupt_in_index)
    {
        hr = usb_interrupt_in_pipes_create( interrupt_in_pipes, interrupt_in_index, &impl->interrupt_in_pipes );
        if (FAILED( hr ))
        {
            UINT32 i;
            for (i = 0; i < interrupt_in_index; ++i)
                if (interrupt_in_pipes[i]) IUsbInterruptInPipe_Release( interrupt_in_pipes[i] );
            free( interrupt_in_pipes );
            if (interrupt_out_pipes) { for (i = 0; i < interrupt_out_index; ++i) if (interrupt_out_pipes[i]) IUsbInterruptOutPipe_Release( interrupt_out_pipes[i] ); free( interrupt_out_pipes ); }
            free( items );
            free( eps );
            IUsbInterface_Release( &impl->IUsbInterface_iface );
            return hr;
        }
    }

    if (interrupt_out_pipes && interrupt_out_index)
    {
        hr = usb_interrupt_out_pipes_create( interrupt_out_pipes, interrupt_out_index, &impl->interrupt_out_pipes );
        if (FAILED( hr ))
        {
            UINT32 i;
            for (i = 0; i < interrupt_out_index; ++i)
                if (interrupt_out_pipes[i]) IUsbInterruptOutPipe_Release( interrupt_out_pipes[i] );
            free( interrupt_out_pipes );
            free( items );
            free( eps );
            IUsbInterface_Release( &impl->IUsbInterface_iface );
            return hr;
        }
    }

    if (bulk_in_pipes)
    {
        UINT32 i;
        for (i = 0; i < bulk_in_index; ++i)
            if (bulk_in_pipes[i]) IUsbBulkInPipe_Release( bulk_in_pipes[i] );
        free( bulk_in_pipes );
    }

    if (bulk_out_pipes)
    {
        UINT32 i;
        for (i = 0; i < bulk_out_index; ++i)
            if (bulk_out_pipes[i]) IUsbBulkOutPipe_Release( bulk_out_pipes[i] );
        free( bulk_out_pipes );
    }

    if (interrupt_in_pipes)
    {
        UINT32 i;
        for (i = 0; i < interrupt_in_index; ++i)
            if (interrupt_in_pipes[i]) IUsbInterruptInPipe_Release( interrupt_in_pipes[i] );
        free( interrupt_in_pipes );
    }

    if (interrupt_out_pipes)
    {
        UINT32 i;
        for (i = 0; i < interrupt_out_index; ++i)
            if (interrupt_out_pipes[i]) IUsbInterruptOutPipe_Release( interrupt_out_pipes[i] );
        free( interrupt_out_pipes );
    }

    free( items );
    *out = &impl->IUsbInterface_iface;
    return S_OK;
}

static HRESULT WINAPI usb_interface_vector_view_QueryInterface(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface *iface, REFIID iid, void **out )
{
    struct usb_interface_vector_view *impl = impl_from_usb_interface_vector_view( iface );
    (void)impl;

    TRACE( "iface %p, iid %s, out %p.\n", iface, debugstr_guid( iid ), out );

    if (IsEqualGUID( iid, &IID_IUnknown ) ||
        IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAgileObject ) ||
        IsEqualGUID( iid, &IID___FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface ))
    {
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface_AddRef( iface );
        *out = iface;
        return S_OK;
    }

    WARN( "%s not implemented, returning E_NOINTERFACE.\n", debugstr_guid( iid ) );
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_interface_vector_view_AddRef(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface *iface )
{
    struct usb_interface_vector_view *impl = impl_from_usb_interface_vector_view( iface );
    ULONG ref = InterlockedIncrement( &impl->ref );
    TRACE( "iface %p increasing refcount to %lu.\n", iface, ref );
    return ref;
}

static ULONG WINAPI usb_interface_vector_view_Release(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface *iface )
{
    struct usb_interface_vector_view *impl = impl_from_usb_interface_vector_view( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    UINT32 i;

    TRACE( "iface %p decreasing refcount to %lu.\n", iface, ref );

    if (!ref)
    {
        if (impl->items)
        {
            for (i = 0; i < impl->size; ++i)
            {
                if (impl->items[i]) IUsbInterface_Release( impl->items[i] );
            }
            free( impl->items );
        }
        free( impl );
    }

    return ref;
}

static HRESULT WINAPI usb_interface_vector_view_GetIids(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IVectorView_UsbInterface };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}

static HRESULT WINAPI usb_interface_vector_view_GetRuntimeClassName(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Foundation.Collections.IVectorView`1<Windows.Devices.Usb.UsbInterface>";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}

static HRESULT WINAPI usb_interface_vector_view_GetTrustLevel(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI usb_interface_vector_view_GetAt(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface *iface, UINT32 index,
        IUsbInterface **value )
{
    struct usb_interface_vector_view *impl = impl_from_usb_interface_vector_view( iface );

    if (!value) return E_INVALIDARG;
    *value = NULL;
    if (index >= impl->size) return E_BOUNDS;

    *value = impl->items[index];
    if (*value) IUsbInterface_AddRef( *value );
    return S_OK;
}

static HRESULT WINAPI usb_interface_vector_view_get_Size(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface *iface, UINT32 *value )
{
    struct usb_interface_vector_view *impl = impl_from_usb_interface_vector_view( iface );

    if (!value) return E_INVALIDARG;
    *value = impl->size;
    return S_OK;
}

static HRESULT WINAPI usb_interface_vector_view_IndexOf(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface *iface, IUsbInterface *element,
        UINT32 *index, BOOLEAN *found )
{
    struct usb_interface_vector_view *impl = impl_from_usb_interface_vector_view( iface );
    UINT32 i;

    if (index) *index = 0;
    if (found) *found = FALSE;

    if (!element || !found) return E_INVALIDARG;

    for (i = 0; i < impl->size; ++i)
    {
        if (impl->items[i] == element)
        {
            if (index) *index = i;
            *found = TRUE;
            break;
        }
    }

    return S_OK;
}

static HRESULT WINAPI usb_interface_vector_view_GetMany(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface *iface, UINT32 start_index,
        UINT32 items_size, IUsbInterface **items, UINT32 *value )
{
    struct usb_interface_vector_view *impl = impl_from_usb_interface_vector_view( iface );
    UINT32 i, available;

    if (!value || !items) return E_INVALIDARG;
    *value = 0;

    if (start_index >= impl->size) return E_BOUNDS;

    available = impl->size - start_index;
    if (items_size > available) items_size = available;

    for (i = 0; i < items_size; ++i)
    {
        items[i] = impl->items[start_index + i];
        if (items[i]) IUsbInterface_AddRef( items[i] );
    }

    *value = items_size;
    return S_OK;
}

static const __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceVtbl usb_interface_vector_view_vtbl =
{
    usb_interface_vector_view_QueryInterface,
    usb_interface_vector_view_AddRef,
    usb_interface_vector_view_Release,
    usb_interface_vector_view_GetIids,
    usb_interface_vector_view_GetRuntimeClassName,
    usb_interface_vector_view_GetTrustLevel,
    usb_interface_vector_view_GetAt,
    usb_interface_vector_view_get_Size,
    usb_interface_vector_view_IndexOf,
    usb_interface_vector_view_GetMany,
};

static HRESULT usb_interface_vector_view_create(
        IUsbInterface **items, UINT32 count,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface **out )
{
    struct usb_interface_vector_view *impl;
    UINT32 i;

    if (!out) return E_INVALIDARG;
    *out = NULL;

    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IVectorView_iface.lpVtbl = &usb_interface_vector_view_vtbl;
    impl->ref = 1;

    if (count)
    {
        if (!(impl->items = calloc( count, sizeof(*impl->items) )))
        {
            free( impl );
            return E_OUTOFMEMORY;
        }

        impl->size = count;
        for (i = 0; i < count; ++i)
        {
            impl->items[i] = items[i];
            if (impl->items[i]) IUsbInterface_AddRef( impl->items[i] );
        }
    }

    *out = &impl->IVectorView_iface;
    return S_OK;
}

/* UsbInterfaceSetting */
struct usb_interface_setting_obj
{
    IUsbInterfaceSetting IUsbInterfaceSetting_iface;
    LONG ref;
    struct usb_device *device;
    IUsbInterfaceDescriptor *interface_descriptor;
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor *descriptors;
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor *bulk_in_endpoints;
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor *bulk_out_endpoints;
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor *interrupt_in_endpoints;
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor *interrupt_out_endpoints;
    BOOLEAN selected;
};

static inline struct usb_interface_setting_obj *impl_from_IUsbInterfaceSetting( IUsbInterfaceSetting *iface )
{
    return CONTAINING_RECORD( iface, struct usb_interface_setting_obj, IUsbInterfaceSetting_iface );
}

static HRESULT WINAPI usb_interface_setting_QueryInterface( IUsbInterfaceSetting *iface, REFIID iid, void **out )
{
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IUsbInterfaceSetting ))
    { *out = iface; IUsbInterfaceSetting_AddRef( iface ); return S_OK; }
    *out = NULL; return E_NOINTERFACE;
}
static ULONG WINAPI usb_interface_setting_AddRef( IUsbInterfaceSetting *iface )
{ return InterlockedIncrement( &impl_from_IUsbInterfaceSetting( iface )->ref ); }
static ULONG WINAPI usb_interface_setting_Release( IUsbInterfaceSetting *iface )
{
    struct usb_interface_setting_obj *impl = impl_from_IUsbInterfaceSetting( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref)
    {
        if (impl->interface_descriptor) IUsbInterfaceDescriptor_Release( impl->interface_descriptor );
        if (impl->descriptors) __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor_Release( impl->descriptors );
        if (impl->bulk_in_endpoints) __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor_Release( impl->bulk_in_endpoints );
        if (impl->bulk_out_endpoints) __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor_Release( impl->bulk_out_endpoints );
        if (impl->interrupt_in_endpoints) __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor_Release( impl->interrupt_in_endpoints );
        if (impl->interrupt_out_endpoints) __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor_Release( impl->interrupt_out_endpoints );
        free( impl );
    }
    return ref;
}
static HRESULT WINAPI usb_interface_setting_GetIids( IUsbInterfaceSetting *iface, ULONG *c, IID **i )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IUsbInterfaceSetting };
    IID *out;
    ULONG k;
    if (!c || !i) return E_INVALIDARG;
    *c = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (k = 0; k < 2; k++) out[k] = *ids[k];
    *i = out;
    return S_OK;
}
static HRESULT WINAPI usb_interface_setting_GetRuntimeClassName( IUsbInterfaceSetting *iface, HSTRING *n )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbInterfaceSetting";
    if (!n) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, n );
}
static HRESULT WINAPI usb_interface_setting_GetTrustLevel( IUsbInterfaceSetting *iface, TrustLevel *t )
{
    if (!t) return E_INVALIDARG;
    *t = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI usb_interface_setting_get_BulkInEndpoints( IUsbInterfaceSetting *iface, __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor **value )
{
    struct usb_interface_setting_obj *impl = impl_from_IUsbInterfaceSetting( iface );
    if (!value) return E_INVALIDARG; *value = NULL;
    if (impl->bulk_in_endpoints) { *value = impl->bulk_in_endpoints; __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor_AddRef( *value ); return S_OK; }
    return usb_bulk_in_endpoint_descriptors_view_create( NULL, 0, value );
}
static HRESULT WINAPI usb_interface_setting_get_InterruptInEndpoints( IUsbInterfaceSetting *iface, __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor **value )
{
    struct usb_interface_setting_obj *impl = impl_from_IUsbInterfaceSetting( iface );
    if (!value) return E_INVALIDARG; *value = NULL;
    if (impl->interrupt_in_endpoints) { *value = impl->interrupt_in_endpoints; __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor_AddRef( *value ); return S_OK; }
    return usb_interrupt_in_endpoint_descriptors_view_create( NULL, 0, value );
}
static HRESULT WINAPI usb_interface_setting_get_BulkOutEndpoints( IUsbInterfaceSetting *iface, __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor **value )
{
    struct usb_interface_setting_obj *impl = impl_from_IUsbInterfaceSetting( iface );
    if (!value) return E_INVALIDARG; *value = NULL;
    if (impl->bulk_out_endpoints) { *value = impl->bulk_out_endpoints; __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor_AddRef( *value ); return S_OK; }
    return usb_bulk_out_endpoint_descriptors_view_create( NULL, 0, value );
}
static HRESULT WINAPI usb_interface_setting_get_InterruptOutEndpoints( IUsbInterfaceSetting *iface, __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor **value )
{
    struct usb_interface_setting_obj *impl = impl_from_IUsbInterfaceSetting( iface );
    if (!value) return E_INVALIDARG; *value = NULL;
    if (impl->interrupt_out_endpoints) { *value = impl->interrupt_out_endpoints; __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptOutEndpointDescriptor_AddRef( *value ); return S_OK; }
    return usb_interrupt_out_endpoint_descriptors_view_create( NULL, 0, value );
}
static HRESULT WINAPI usb_interface_setting_get_Selected( IUsbInterfaceSetting *iface, BOOLEAN *value )
{
    if (!value) return E_INVALIDARG;
    *value = impl_from_IUsbInterfaceSetting( iface )->selected;
    return S_OK;
}
static HRESULT WINAPI usb_interface_setting_SelectSettingAsync( IUsbInterfaceSetting *iface, IAsyncAction **operation )
{
    struct usb_interface_setting_obj *impl = impl_from_IUsbInterfaceSetting( iface );
    struct usb_device *device;
    UCHAR interface_number, alternate_setting;
    UCHAR inbuf[2];
    DWORD bytes_returned;
    HRESULT hr = S_OK;

    if (!operation) return E_INVALIDARG;
    *operation = NULL;
    if (!impl->interface_descriptor) return E_UNEXPECTED;
    device = impl->device;
    if (!device || !device->handle) return E_INVALIDARG;

    IUsbInterfaceDescriptor_get_InterfaceNumber( impl->interface_descriptor, &interface_number );
    IUsbInterfaceDescriptor_get_AlternateSettingNumber( impl->interface_descriptor, &alternate_setting );
    inbuf[0] = interface_number;
    inbuf[1] = alternate_setting;

    if (!DeviceIoControl( device->handle, IOCTL_WINEUSB_SET_INTERFACE, inbuf, sizeof(inbuf), NULL, 0, &bytes_returned, NULL ))
        hr = HRESULT_FROM_WIN32( GetLastError() );

    return async_action_completed_create( hr, operation );
}
static HRESULT WINAPI usb_interface_setting_get_InterfaceDescriptor( IUsbInterfaceSetting *iface, IUsbInterfaceDescriptor **value )
{
    struct usb_interface_setting_obj *impl = impl_from_IUsbInterfaceSetting( iface );
    if (!value) return E_INVALIDARG; *value = NULL;
    if (!impl->interface_descriptor) return S_OK;
    *value = impl->interface_descriptor;
    IUsbInterfaceDescriptor_AddRef( *value );
    return S_OK;
}
static HRESULT WINAPI usb_interface_setting_get_Descriptors( IUsbInterfaceSetting *iface, __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor **value )
{
    struct usb_interface_setting_obj *impl = impl_from_IUsbInterfaceSetting( iface );
    if (!value) return E_INVALIDARG; *value = NULL;
    if (impl->descriptors) { *value = impl->descriptors; __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor_AddRef( *value ); return S_OK; }
    return S_OK;
}

static const IUsbInterfaceSettingVtbl usb_interface_setting_vtbl = {
    usb_interface_setting_QueryInterface,
    usb_interface_setting_AddRef,
    usb_interface_setting_Release,
    usb_interface_setting_GetIids,
    usb_interface_setting_GetRuntimeClassName,
    usb_interface_setting_GetTrustLevel,
    usb_interface_setting_get_BulkInEndpoints,
    usb_interface_setting_get_InterruptInEndpoints,
    usb_interface_setting_get_BulkOutEndpoints,
    usb_interface_setting_get_InterruptOutEndpoints,
    usb_interface_setting_get_Selected,
    usb_interface_setting_SelectSettingAsync,
    usb_interface_setting_get_InterfaceDescriptor,
    usb_interface_setting_get_Descriptors,
};

static HRESULT usb_interface_setting_create( struct usb_device *device, const BYTE *start, const BYTE *end, IUsbInterfaceSetting **out )
{
    const USB_INTERFACE_DESCRIPTOR *desc;
    IUsbDescriptor **desc_items = NULL;
    UINT32 desc_count = 0;
    const BYTE *ptr;
    USB_ENDPOINT_DESCRIPTOR *eps = NULL;
    UINT32 ep_count = 0, ep_index = 0;
    IUsbBulkInPipe **bulk_in_pipes = NULL;
    UINT32 bi_count = 0, bi_idx = 0;
    IUsbBulkOutPipe **bulk_out_pipes = NULL;
    UINT32 bo_count = 0, bo_idx = 0;
    IUsbInterruptInPipe **int_in_pipes = NULL;
    UINT32 ii_count = 0, ii_idx = 0;
    IUsbInterruptOutPipe **int_out_pipes = NULL;
    UINT32 io_count = 0, io_idx = 0;
    IUsbBulkInEndpointDescriptor **bi_eds = NULL;
    IUsbBulkOutEndpointDescriptor **bo_eds = NULL;
    IUsbInterruptInEndpointDescriptor **ii_eds = NULL;
    IUsbInterruptOutEndpointDescriptor **io_eds = NULL;
    struct usb_interface_setting_obj *impl = NULL;
    HRESULT hr;
    UINT32 i;

    if (!out || !device || start + sizeof(USB_INTERFACE_DESCRIPTOR) > end) return E_INVALIDARG;
    *out = NULL;
    desc = (const USB_INTERFACE_DESCRIPTOR *)start;
    if (desc->bLength < sizeof(USB_INTERFACE_DESCRIPTOR) || desc->bDescriptorType != USB_INTERFACE_DESCRIPTOR_TYPE)
        return E_FAIL;

    ptr = start;
    while (ptr + 2 <= end)
    {
        BYTE len = ptr[0];
        if (!len || ptr + len > end) break;
        if (ptr[1] == USB_ENDPOINT_DESCRIPTOR_TYPE && len >= sizeof(USB_ENDPOINT_DESCRIPTOR)) ep_count++;
        desc_count++;
        ptr += len;
    }

    if (desc_count && !(desc_items = calloc( desc_count, sizeof(*desc_items) ))) { hr = E_OUTOFMEMORY; goto fail; }
    if (ep_count && !(eps = calloc( ep_count, sizeof(*eps) ))) { hr = E_OUTOFMEMORY; goto fail; }

    ptr = start; desc_count = 0; ep_index = 0;
    while (ptr + 2 <= end)
    {
        BYTE len = ptr[0];
        if (!len || ptr + len > end) break;
        if (ptr[1] == USB_ENDPOINT_DESCRIPTOR_TYPE && len >= sizeof(USB_ENDPOINT_DESCRIPTOR) && eps)
            memcpy( &eps[ep_index++], ptr, sizeof(USB_ENDPOINT_DESCRIPTOR) );
        hr = usb_descriptor_create( ptr, len, &desc_items[desc_count] );
        if (FAILED( hr )) goto fail;
        desc_count++;
        ptr += len;
    }

    for (ep_index = 0; ep_index < ep_count; ep_index++)
    {
        UCHAR addr = eps[ep_index].bEndpointAddress, attrs = eps[ep_index].bmAttributes;
        if ((addr & 0x80) && ((attrs & 0x03) == USB_ENDPOINT_TYPE_BULK)) bi_count++;
        else if (!(addr & 0x80) && ((attrs & 0x03) == USB_ENDPOINT_TYPE_BULK)) bo_count++;
        else if ((addr & 0x80) && ((attrs & 0x03) == USB_ENDPOINT_TYPE_INTERRUPT)) ii_count++;
        else if (!(addr & 0x80) && ((attrs & 0x03) == USB_ENDPOINT_TYPE_INTERRUPT)) io_count++;
    }

    if (bi_count && !(bulk_in_pipes = calloc( bi_count, sizeof(*bulk_in_pipes) ))) { hr = E_OUTOFMEMORY; goto fail; }
    if (bo_count && !(bulk_out_pipes = calloc( bo_count, sizeof(*bulk_out_pipes) ))) { hr = E_OUTOFMEMORY; goto fail; }
    if (ii_count && !(int_in_pipes = calloc( ii_count, sizeof(*int_in_pipes) ))) { hr = E_OUTOFMEMORY; goto fail; }
    if (io_count && !(int_out_pipes = calloc( io_count, sizeof(*int_out_pipes) ))) { hr = E_OUTOFMEMORY; goto fail; }
    if (bi_count && !(bi_eds = calloc( bi_count, sizeof(*bi_eds) ))) { hr = E_OUTOFMEMORY; goto fail; }
    if (bo_count && !(bo_eds = calloc( bo_count, sizeof(*bo_eds) ))) { hr = E_OUTOFMEMORY; goto fail; }
    if (ii_count && !(ii_eds = calloc( ii_count, sizeof(*ii_eds) ))) { hr = E_OUTOFMEMORY; goto fail; }
    if (io_count && !(io_eds = calloc( io_count, sizeof(*io_eds) ))) { hr = E_OUTOFMEMORY; goto fail; }

    for (ep_index = 0; ep_index < ep_count; ep_index++)
    {
        UCHAR addr = eps[ep_index].bEndpointAddress, attrs = eps[ep_index].bmAttributes;
        if ((addr & 0x80) && ((attrs & 0x03) == USB_ENDPOINT_TYPE_BULK))
        {
            hr = usb_bulk_in_pipe_create( device, &eps[ep_index], &bulk_in_pipes[bi_idx] );
            if (FAILED( hr )) goto fail;
            hr = usb_bulk_in_endpoint_descriptor_create( impl_from_IUsbBulkInPipe( bulk_in_pipes[bi_idx] ), &bi_eds[bi_idx] );
            if (FAILED( hr )) goto fail;
            bi_idx++;
        }
        else if (!(addr & 0x80) && ((attrs & 0x03) == USB_ENDPOINT_TYPE_BULK))
        {
            hr = usb_bulk_out_pipe_create( device, &eps[ep_index], &bulk_out_pipes[bo_idx] );
            if (FAILED( hr )) goto fail;
            hr = usb_bulk_out_endpoint_descriptor_create( impl_from_IUsbBulkOutPipe( bulk_out_pipes[bo_idx] ), &bo_eds[bo_idx] );
            if (FAILED( hr )) goto fail;
            bo_idx++;
        }
        else if ((addr & 0x80) && ((attrs & 0x03) == USB_ENDPOINT_TYPE_INTERRUPT))
        {
            hr = usb_interrupt_in_pipe_create( device, &eps[ep_index], &int_in_pipes[ii_idx] );
            if (FAILED( hr )) goto fail;
            hr = usb_interrupt_in_endpoint_descriptor_create( impl_from_IUsbInterruptInPipe( int_in_pipes[ii_idx] ), &ii_eds[ii_idx] );
            if (FAILED( hr )) goto fail;
            ii_idx++;
        }
        else if (!(addr & 0x80) && ((attrs & 0x03) == USB_ENDPOINT_TYPE_INTERRUPT))
        {
            hr = usb_interrupt_out_pipe_create( device, &eps[ep_index], &int_out_pipes[io_idx] );
            if (FAILED( hr )) goto fail;
            hr = usb_interrupt_out_endpoint_descriptor_create( impl_from_IUsbInterruptOutPipe( int_out_pipes[io_idx] ), &io_eds[io_idx] );
            if (FAILED( hr )) goto fail;
            io_idx++;
        }
    }

    if (!(impl = calloc( 1, sizeof(*impl) ))) { hr = E_OUTOFMEMORY; goto fail; }
    impl->IUsbInterfaceSetting_iface.lpVtbl = &usb_interface_setting_vtbl;
    impl->ref = 1;
    impl->device = device;
    impl->selected = (desc->bAlternateSetting == 0) ? TRUE : FALSE;

    hr = usb_interface_descriptor_create( desc, &impl->interface_descriptor );
    if (FAILED( hr )) { free( impl ); impl = NULL; goto fail; }
    hr = usb_descriptor_vector_view_create( desc_items, desc_count, &impl->descriptors );
    if (FAILED( hr )) { IUsbInterfaceDescriptor_Release( impl->interface_descriptor ); free( impl ); impl = NULL; goto fail; }
    hr = usb_bulk_in_endpoint_descriptors_view_create( bi_eds, bi_count, &impl->bulk_in_endpoints );
    if (FAILED( hr )) { __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor_Release( impl->descriptors ); IUsbInterfaceDescriptor_Release( impl->interface_descriptor ); free( impl ); impl = NULL; goto fail; }
    hr = usb_bulk_out_endpoint_descriptors_view_create( bo_eds, bo_count, &impl->bulk_out_endpoints );
    if (FAILED( hr )) { __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor_Release( impl->bulk_in_endpoints ); __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor_Release( impl->descriptors ); IUsbInterfaceDescriptor_Release( impl->interface_descriptor ); free( impl ); impl = NULL; goto fail; }
    hr = usb_interrupt_in_endpoint_descriptors_view_create( ii_eds, ii_count, &impl->interrupt_in_endpoints );
    if (FAILED( hr )) { __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor_Release( impl->bulk_out_endpoints ); __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor_Release( impl->bulk_in_endpoints ); __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor_Release( impl->descriptors ); IUsbInterfaceDescriptor_Release( impl->interface_descriptor ); free( impl ); impl = NULL; goto fail; }
    hr = usb_interrupt_out_endpoint_descriptors_view_create( io_eds, io_count, &impl->interrupt_out_endpoints );
    if (FAILED( hr )) { __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterruptInEndpointDescriptor_Release( impl->interrupt_in_endpoints ); __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkOutEndpointDescriptor_Release( impl->bulk_out_endpoints ); __FIVectorView_1_Windows__CDevices__CUsb__CUsbBulkInEndpointDescriptor_Release( impl->bulk_in_endpoints ); __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor_Release( impl->descriptors ); IUsbInterfaceDescriptor_Release( impl->interface_descriptor ); free( impl ); impl = NULL; goto fail; }

    *out = &impl->IUsbInterfaceSetting_iface;
    hr = S_OK;
fail:
    for (i = 0; i < desc_count; i++) if (desc_items[i]) IUsbDescriptor_Release( desc_items[i] );
    free( desc_items );
    free( eps );
    for (i = 0; i < bi_idx; i++) { if (bulk_in_pipes && bulk_in_pipes[i]) IUsbBulkInPipe_Release( bulk_in_pipes[i] ); if (bi_eds && bi_eds[i]) IUsbBulkInEndpointDescriptor_Release( bi_eds[i] ); }
    for (i = 0; i < bo_idx; i++) { if (bulk_out_pipes && bulk_out_pipes[i]) IUsbBulkOutPipe_Release( bulk_out_pipes[i] ); if (bo_eds && bo_eds[i]) IUsbBulkOutEndpointDescriptor_Release( bo_eds[i] ); }
    for (i = 0; i < ii_idx; i++) { if (int_in_pipes && int_in_pipes[i]) IUsbInterruptInPipe_Release( int_in_pipes[i] ); if (ii_eds && ii_eds[i]) IUsbInterruptInEndpointDescriptor_Release( ii_eds[i] ); }
    for (i = 0; i < io_idx; i++) { if (int_out_pipes && int_out_pipes[i]) IUsbInterruptOutPipe_Release( int_out_pipes[i] ); if (io_eds && io_eds[i]) IUsbInterruptOutEndpointDescriptor_Release( io_eds[i] ); }
    free( bulk_in_pipes );
    free( bulk_out_pipes );
    free( int_in_pipes );
    free( int_out_pipes );
    free( bi_eds );
    free( bo_eds );
    free( ii_eds );
    free( io_eds );
    return hr;
}

/* Vector view of IUsbInterfaceSetting* for InterfaceSettings */
struct usb_interface_settings_view
{
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSetting IVectorView_iface;
    LONG ref;
    UINT32 size;
    IUsbInterfaceSetting **items;
};

static inline struct usb_interface_settings_view *impl_from_usb_interface_settings_view(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSetting *iface )
{
    return CONTAINING_RECORD( iface, struct usb_interface_settings_view, IVectorView_iface );
}

static HRESULT WINAPI usb_interface_settings_view_QueryInterface(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSetting *iface, REFIID iid, void **out )
{
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID___FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSetting ))
    {
        *out = iface;
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSetting_AddRef( iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}
static ULONG WINAPI usb_interface_settings_view_AddRef(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSetting *iface )
{
    return InterlockedIncrement( &impl_from_usb_interface_settings_view( iface )->ref );
}
static ULONG WINAPI usb_interface_settings_view_Release(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSetting *iface )
{
    struct usb_interface_settings_view *impl = impl_from_usb_interface_settings_view( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    UINT32 i;
    if (!ref)
    {
        if (impl->items) { for (i = 0; i < impl->size; ++i) if (impl->items[i]) IUsbInterfaceSetting_Release( impl->items[i] ); free( impl->items ); }
        free( impl );
    }
    return ref;
}
static HRESULT WINAPI usb_interface_settings_view_GetIids( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSetting *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IVectorView_UsbInterfaceSetting };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}
static HRESULT WINAPI usb_interface_settings_view_GetRuntimeClassName( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSetting *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Foundation.Collections.IVectorView`1<Windows.Devices.Usb.UsbInterfaceSetting>";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI usb_interface_settings_view_GetTrustLevel( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSetting *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI usb_interface_settings_view_GetAt( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSetting *iface, UINT32 index, IUsbInterfaceSetting **value )
{
    struct usb_interface_settings_view *impl = impl_from_usb_interface_settings_view( iface );
    if (!value) return E_INVALIDARG;
    *value = NULL;
    if (index >= impl->size) return E_BOUNDS;
    *value = impl->items[index];
    if (*value) IUsbInterfaceSetting_AddRef( *value );
    return S_OK;
}
static HRESULT WINAPI usb_interface_settings_view_get_Size( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSetting *iface, UINT32 *value )
{
    if (!value) return E_INVALIDARG;
    *value = impl_from_usb_interface_settings_view( iface )->size;
    return S_OK;
}
static HRESULT WINAPI usb_interface_settings_view_IndexOf( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSetting *iface, IUsbInterfaceSetting *element, UINT32 *index, BOOLEAN *found )
{
    struct usb_interface_settings_view *impl = impl_from_usb_interface_settings_view( iface );
    UINT32 i;
    if (index) *index = 0;
    if (found) *found = FALSE;
    if (!element || !found) return E_INVALIDARG;
    for (i = 0; i < impl->size; ++i)
        if (impl->items[i] == element) { if (index) *index = i; *found = TRUE; break; }
    return S_OK;
}
static HRESULT WINAPI usb_interface_settings_view_GetMany( __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSetting *iface, UINT32 start_index, UINT32 items_size, IUsbInterfaceSetting **items, UINT32 *value )
{
    struct usb_interface_settings_view *impl = impl_from_usb_interface_settings_view( iface );
    UINT32 i, available;
    if (!value || !items) return E_INVALIDARG;
    *value = 0;
    if (start_index >= impl->size) return E_BOUNDS;
    available = impl->size - start_index;
    if (items_size > available) items_size = available;
    for (i = 0; i < items_size; ++i) { items[i] = impl->items[start_index + i]; if (items[i]) IUsbInterfaceSetting_AddRef( items[i] ); }
    *value = items_size;
    return S_OK;
}

static const __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSettingVtbl usb_interface_settings_view_vtbl = {
    usb_interface_settings_view_QueryInterface,
    usb_interface_settings_view_AddRef,
    usb_interface_settings_view_Release,
    usb_interface_settings_view_GetIids,
    usb_interface_settings_view_GetRuntimeClassName,
    usb_interface_settings_view_GetTrustLevel,
    usb_interface_settings_view_GetAt,
    usb_interface_settings_view_get_Size,
    usb_interface_settings_view_IndexOf,
    usb_interface_settings_view_GetMany,
};

static HRESULT usb_interface_settings_view_create( IUsbInterfaceSetting **items, UINT32 count,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterfaceSetting **out )
{
    struct usb_interface_settings_view *impl;
    UINT32 i;
    if (!out) return E_INVALIDARG;
    *out = NULL;
    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IVectorView_iface.lpVtbl = &usb_interface_settings_view_vtbl;
    impl->ref = 1;
    if (count && (impl->items = calloc( count, sizeof(*impl->items) )))
    {
        impl->size = count;
        for (i = 0; i < count; ++i) { impl->items[i] = items[i]; if (impl->items[i]) IUsbInterfaceSetting_AddRef( impl->items[i] ); }
    }
    *out = &impl->IVectorView_iface;
    return S_OK;
}

struct usb_descriptor_vector_view
{
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor IVectorView_iface;
    LONG ref;
    UINT32 size;
    IUsbDescriptor **items;
};

static inline struct usb_descriptor_vector_view *impl_from_usb_descriptor_vector_view(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor *iface )
{
    return CONTAINING_RECORD( iface, struct usb_descriptor_vector_view, IVectorView_iface );
}

static HRESULT WINAPI usb_descriptor_vector_view_QueryInterface(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor *iface, REFIID iid, void **out )
{
    struct usb_descriptor_vector_view *impl = impl_from_usb_descriptor_vector_view( iface );
    (void)impl;

    TRACE( "iface %p, iid %s, out %p.\n", iface, debugstr_guid( iid ), out );

    if (IsEqualGUID( iid, &IID_IUnknown ) ||
        IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAgileObject ) ||
        IsEqualGUID( iid, &IID___FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor ))
    {
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor_AddRef( iface );
        *out = iface;
        return S_OK;
    }

    WARN( "%s not implemented, returning E_NOINTERFACE.\n", debugstr_guid( iid ) );
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_descriptor_vector_view_AddRef(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor *iface )
{
    struct usb_descriptor_vector_view *impl = impl_from_usb_descriptor_vector_view( iface );
    return InterlockedIncrement( &impl->ref );
}

static ULONG WINAPI usb_descriptor_vector_view_Release(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor *iface )
{
    struct usb_descriptor_vector_view *impl = impl_from_usb_descriptor_vector_view( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    UINT32 i;

    if (!ref)
    {
        if (impl->items)
        {
            for (i = 0; i < impl->size; ++i)
            {
                if (impl->items[i]) IUsbDescriptor_Release( impl->items[i] );
            }
            free( impl->items );
        }
        free( impl );
    }
    return ref;
}

static HRESULT WINAPI usb_descriptor_vector_view_GetIids(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IVectorView_UsbDescriptor };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}

static HRESULT WINAPI usb_descriptor_vector_view_GetRuntimeClassName(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Foundation.Collections.IVectorView`1<Windows.Devices.Usb.UsbDescriptor>";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}

static HRESULT WINAPI usb_descriptor_vector_view_GetTrustLevel(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI usb_descriptor_vector_view_GetAt(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor *iface, UINT32 index,
        IUsbDescriptor **value )
{
    struct usb_descriptor_vector_view *impl = impl_from_usb_descriptor_vector_view( iface );

    if (!value) return E_INVALIDARG;
    *value = NULL;
    if (index >= impl->size) return E_BOUNDS;

    *value = impl->items[index];
    if (*value) IUsbDescriptor_AddRef( *value );
    return S_OK;
}

static HRESULT WINAPI usb_descriptor_vector_view_get_Size(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor *iface, UINT32 *value )
{
    struct usb_descriptor_vector_view *impl = impl_from_usb_descriptor_vector_view( iface );

    if (!value) return E_INVALIDARG;
    *value = impl->size;
    return S_OK;
}

static HRESULT WINAPI usb_descriptor_vector_view_IndexOf(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor *iface, IUsbDescriptor *element,
        UINT32 *index, BOOLEAN *found )
{
    struct usb_descriptor_vector_view *impl = impl_from_usb_descriptor_vector_view( iface );
    UINT32 i;

    if (index) *index = 0;
    if (found) *found = FALSE;

    if (!element || !found) return E_INVALIDARG;

    for (i = 0; i < impl->size; ++i)
    {
        if (impl->items[i] == element)
        {
            if (index) *index = i;
            *found = TRUE;
            break;
        }
    }

    return S_OK;
}

static HRESULT WINAPI usb_descriptor_vector_view_GetMany(
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor *iface, UINT32 start_index,
        UINT32 items_size, IUsbDescriptor **items, UINT32 *value )
{
    struct usb_descriptor_vector_view *impl = impl_from_usb_descriptor_vector_view( iface );
    UINT32 i, available;

    if (!value || !items) return E_INVALIDARG;
    *value = 0;

    if (start_index >= impl->size) return E_BOUNDS;

    available = impl->size - start_index;
    if (items_size > available) items_size = available;

    for (i = 0; i < items_size; ++i)
    {
        items[i] = impl->items[start_index + i];
        if (items[i]) IUsbDescriptor_AddRef( items[i] );
    }

    *value = items_size;
    return S_OK;
}

static const __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptorVtbl usb_descriptor_vector_view_vtbl =
{
    usb_descriptor_vector_view_QueryInterface,
    usb_descriptor_vector_view_AddRef,
    usb_descriptor_vector_view_Release,
    usb_descriptor_vector_view_GetIids,
    usb_descriptor_vector_view_GetRuntimeClassName,
    usb_descriptor_vector_view_GetTrustLevel,
    usb_descriptor_vector_view_GetAt,
    usb_descriptor_vector_view_get_Size,
    usb_descriptor_vector_view_IndexOf,
    usb_descriptor_vector_view_GetMany,
};

static HRESULT usb_descriptor_vector_view_create(
        IUsbDescriptor **items, UINT32 count,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor **out )
{
    struct usb_descriptor_vector_view *impl;
    UINT32 i;

    if (!out) return E_INVALIDARG;
    *out = NULL;

    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IVectorView_iface.lpVtbl = &usb_descriptor_vector_view_vtbl;
    impl->ref = 1;

    if (count)
    {
        if (!(impl->items = calloc( count, sizeof(*impl->items) )))
        {
            free( impl );
            return E_OUTOFMEMORY;
        }

        impl->size = count;
        for (i = 0; i < count; ++i)
        {
            impl->items[i] = items[i];
            if (impl->items[i]) IUsbDescriptor_AddRef( impl->items[i] );
        }
    }

    *out = &impl->IVectorView_iface;
    return S_OK;
}

static HRESULT WINAPI usb_configuration_QueryInterface( IUsbConfiguration *iface, REFIID iid, void **out )
{
    TRACE( "iface %p, iid %s, out %p.\n", iface, debugstr_guid( iid ), out );

    if (IsEqualGUID( iid, &IID_IUnknown ) ||
        IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAgileObject ) ||
        IsEqualGUID( iid, &IID_IUsbConfiguration ))
    {
        IUsbConfiguration_AddRef( iface );
        *out = iface;
        return S_OK;
    }

    *out = NULL;
    FIXME( "%s not implemented, returning E_NOINTERFACE.\n", debugstr_guid( iid ) );
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_configuration_AddRef( IUsbConfiguration *iface )
{
    struct usb_configuration *impl = impl_from_IUsbConfiguration( iface );
    ULONG ref = InterlockedIncrement( &impl->ref );
    TRACE( "iface %p increasing refcount to %lu.\n", iface, ref );
    return ref;
}

static ULONG WINAPI usb_configuration_Release( IUsbConfiguration *iface )
{
    struct usb_configuration *impl = impl_from_IUsbConfiguration( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );

    TRACE( "iface %p decreasing refcount to %lu.\n", iface, ref );

    if (!ref)
    {
        if (impl->configuration_descriptor)
            IUsbConfigurationDescriptor_Release( impl->configuration_descriptor );
        if (impl->interfaces)
            __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface_Release( impl->interfaces );
        free( impl->raw_config );
        free( impl );
    }

    return ref;
}

static HRESULT WINAPI usb_configuration_GetIids( IUsbConfiguration *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IUsbConfiguration };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}

static HRESULT WINAPI usb_configuration_GetRuntimeClassName( IUsbConfiguration *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbConfiguration";

    TRACE( "iface %p, class_name %p.\n", iface, class_name );

    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}

static HRESULT WINAPI usb_configuration_GetTrustLevel( IUsbConfiguration *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI usb_configuration_get_UsbInterfaces( IUsbConfiguration *iface,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface **value )
{
    struct usb_configuration *impl = impl_from_IUsbConfiguration( iface );
    IUsbInterface **items = NULL;
    UINT32 count = 0;
    BYTE *ptr, *end;
    HRESULT hr;

    TRACE( "iface %p, value %p.\n", iface, value );

    if (!value) return E_INVALIDARG;
    *value = NULL;

    if (impl->interfaces)
    {
        *value = impl->interfaces;
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface_AddRef( *value );
        return S_OK;
    }

    hr = usb_configuration_ensure_raw_descriptor( impl );
    if (FAILED( hr )) return hr;

    ptr = impl->raw_config;
    end = impl->raw_config + impl->raw_config_len;

    /* Skip configuration descriptor */
    if (ptr + 2 > end) return S_OK;
    if (!ptr[0] || ptr + ptr[0] > end) return E_FAIL;
    ptr += ptr[0];

    /* First pass: count interfaces */
    while (ptr + 2 <= end)
    {
        BYTE len = ptr[0];
        if (!len || ptr + len > end) break;
        if (ptr[1] == USB_INTERFACE_DESCRIPTOR_TYPE)
            count++;
        ptr += len;
    }

    if (!count)
        return usb_interface_vector_view_create( NULL, 0, value );

    if (!(items = calloc( count, sizeof(*items) )))
        return E_OUTOFMEMORY;

    /* Second pass: build interfaces */
    ptr = impl->raw_config;
    ptr += impl->raw_config[0]; /* skip config descriptor again */
    count = 0;
    while (ptr + 2 <= end)
    {
        BYTE len = ptr[0];

        if (!len || ptr + len > end) break;

        if (ptr[1] == USB_INTERFACE_DESCRIPTOR_TYPE)
        {
            BYTE *start = ptr;
            BYTE *next = ptr + len;
            BYTE *scan = next;

            while (scan + 2 <= end)
            {
                BYTE l = scan[0];
                if (!l || scan + l > end) { next = end; break; }
                if (scan[1] == USB_INTERFACE_DESCRIPTOR_TYPE ||
                    scan[1] == USB_CONFIGURATION_DESCRIPTOR_TYPE)
                {
                    next = scan;
                    break;
                }
                scan += l;
            }

            hr = usb_interface_create( impl->device, start, next, &items[count] );
            if (FAILED( hr ))
            {
                UINT32 i;
                for (i = 0; i < count; ++i)
                    if (items[i]) IUsbInterface_Release( items[i] );
                free( items );
                return hr;
            }

            count++;
            ptr = next;
            continue;
        }

        ptr += len;
    }

    hr = usb_interface_vector_view_create( items, count, &impl->interfaces );
    if (FAILED( hr ))
    {
        UINT32 i;
        for (i = 0; i < count; ++i)
            if (items[i]) IUsbInterface_Release( items[i] );
        free( items );
        return hr;
    }

    free( items );
    *value = impl->interfaces;
    __FIVectorView_1_Windows__CDevices__CUsb__CUsbInterface_AddRef( *value );
    return S_OK;
}

static HRESULT usb_configuration_ensure_raw_descriptor( struct usb_configuration *impl )
{
    WINUSB_SETUP_PACKET setup;
    USB_CONFIGURATION_DESCRIPTOR header;
    ULONG transferred;
    BOOL ret;
    HRESULT hr;

    if (impl->raw_config) return S_OK;

    setup.RequestType = 0x80;
    setup.Request = USB_REQUEST_GET_DESCRIPTOR;
    setup.Value = (USB_CONFIGURATION_DESCRIPTOR_TYPE << 8) | 0;
    setup.Index = 0;
    setup.Length = sizeof( header );

    ret = WinUsb_ControlTransfer( impl->device->winusb, &setup, (UCHAR *)&header, sizeof( header ), &transferred, NULL );
    if (!ret || transferred < sizeof( header ))
        return ret ? E_FAIL : HRESULT_FROM_WIN32( GetLastError() );

    impl->raw_config_len = header.wTotalLength;
    if (!(impl->raw_config = malloc( impl->raw_config_len )))
    {
        impl->raw_config_len = 0;
        return E_OUTOFMEMORY;
    }

    setup.Length = (USHORT)impl->raw_config_len;
    ret = WinUsb_ControlTransfer( impl->device->winusb, &setup, impl->raw_config, impl->raw_config_len, &transferred, NULL );
    if (!ret)
    {
        hr = HRESULT_FROM_WIN32( GetLastError() );
        free( impl->raw_config );
        impl->raw_config = NULL;
        impl->raw_config_len = 0;
        return hr;
    }

    if (transferred < sizeof( USB_CONFIGURATION_DESCRIPTOR ))
    {
        free( impl->raw_config );
        impl->raw_config = NULL;
        impl->raw_config_len = 0;
        return E_FAIL;
    }

    impl->raw_config_len = transferred;
    return S_OK;
}

static HRESULT WINAPI usb_configuration_get_ConfigurationDescriptor( IUsbConfiguration *iface,
        IUsbConfigurationDescriptor **value )
{
    struct usb_configuration *impl = impl_from_IUsbConfiguration( iface );
    WINUSB_SETUP_PACKET setup;
    USB_CONFIGURATION_DESCRIPTOR raw;
    ULONG transferred;
    BOOL ret;
    HRESULT hr;

    if (!value) return E_INVALIDARG;
    *value = NULL;

    if (impl->configuration_descriptor)
    {
        *value = impl->configuration_descriptor;
        IUsbConfigurationDescriptor_AddRef( *value );
        return S_OK;
    }

    setup.RequestType = 0x80;
    setup.Request = USB_REQUEST_GET_DESCRIPTOR;
    setup.Value = (USB_CONFIGURATION_DESCRIPTOR_TYPE << 8) | 0;
    setup.Index = 0;
    setup.Length = sizeof( raw );

    ret = WinUsb_ControlTransfer( impl->device->winusb, &setup, (UCHAR *)&raw, sizeof( raw ), &transferred, NULL );
    if (!ret || transferred < sizeof( raw ))
        return ret ? E_FAIL : HRESULT_FROM_WIN32( GetLastError() );

    hr = usb_configuration_descriptor_create( &raw, &impl->configuration_descriptor );
    if (FAILED( hr )) return hr;

    *value = impl->configuration_descriptor;
    IUsbConfigurationDescriptor_AddRef( *value );
    return S_OK;
}

static HRESULT WINAPI usb_configuration_get_Descriptors( IUsbConfiguration *iface,
        __FIVectorView_1_Windows__CDevices__CUsb__CUsbDescriptor **value )
{
    struct usb_configuration *impl = impl_from_IUsbConfiguration( iface );
    IUsbDescriptor **items = NULL;
    UINT32 count = 0;
    BYTE *ptr, *end;
    HRESULT hr;

    TRACE( "iface %p, value %p.\n", iface, value );

    if (!value) return E_INVALIDARG;
    *value = NULL;

    hr = usb_configuration_ensure_raw_descriptor( impl );
    if (FAILED( hr )) return hr;

    ptr = impl->raw_config;
    end = impl->raw_config + impl->raw_config_len;

    /* First pass: count descriptors */
    while (ptr + 2 <= end)
    {
        BYTE len = ptr[0];
        if (!len) break;
        if (ptr + len > end) break;
        count++;
        ptr += len;
    }

    if (!count)
        return usb_descriptor_vector_view_create( NULL, 0, value );

    if (!(items = calloc( count, sizeof(*items) )))
        return E_OUTOFMEMORY;

    /* Second pass: create descriptor objects */
    ptr = impl->raw_config;
    count = 0;
    while (ptr + 2 <= end)
    {
        BYTE len = ptr[0];
        HRESULT hr2;

        if (!len || ptr + len > end) break;

        hr2 = usb_descriptor_create( ptr, len, &items[count] );
        if (FAILED( hr2 ))
        {
            UINT32 i;
            for (i = 0; i < count; ++i)
                if (items[i]) IUsbDescriptor_Release( items[i] );
            free( items );
            return hr2;
        }

        count++;
        ptr += len;
    }

    hr = usb_descriptor_vector_view_create( items, count, value );
    free( items );
    return hr;
}

static const IUsbConfigurationVtbl usb_configuration_vtbl =
{
    usb_configuration_QueryInterface,
    usb_configuration_AddRef,
    usb_configuration_Release,
    usb_configuration_GetIids,
    usb_configuration_GetRuntimeClassName,
    usb_configuration_GetTrustLevel,
    usb_configuration_get_UsbInterfaces,
    usb_configuration_get_ConfigurationDescriptor,
    usb_configuration_get_Descriptors,
};

struct usb_configuration_descriptor_obj
{
    IUsbConfigurationDescriptor IUsbConfigurationDescriptor_iface;
    LONG ref;
    BYTE configuration_value;
    UINT32 max_power_milliamps;
    BOOL self_powered;
    BOOL remote_wakeup;
};

struct usb_descriptor_obj
{
    IUsbDescriptor IUsbDescriptor_iface;
    LONG ref;
    BYTE length;
    BYTE type;
    BYTE *data;
};

static inline struct usb_descriptor_obj *impl_from_IUsbDescriptor( IUsbDescriptor *iface )
{
    return CONTAINING_RECORD( iface, struct usb_descriptor_obj, IUsbDescriptor_iface );
}

static HRESULT WINAPI usb_descriptor_QueryInterface( IUsbDescriptor *iface, REFIID iid, void **out )
{
    TRACE( "iface %p, iid %s, out %p.\n", iface, debugstr_guid( iid ), out );

    if (IsEqualGUID( iid, &IID_IUnknown ) ||
        IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAgileObject ) ||
        IsEqualGUID( iid, &IID_IUsbDescriptor ))
    {
        IUsbDescriptor_AddRef( iface );
        *out = iface;
        return S_OK;
    }

    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_descriptor_AddRef( IUsbDescriptor *iface )
{
    struct usb_descriptor_obj *impl = impl_from_IUsbDescriptor( iface );
    return InterlockedIncrement( &impl->ref );
}

static ULONG WINAPI usb_descriptor_Release( IUsbDescriptor *iface )
{
    struct usb_descriptor_obj *impl = impl_from_IUsbDescriptor( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );

    if (!ref)
    {
        free( impl->data );
        free( impl );
    }

    return ref;
}

static HRESULT WINAPI usb_descriptor_GetIids( IUsbDescriptor *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IUsbDescriptor };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}

static HRESULT WINAPI usb_descriptor_GetRuntimeClassName( IUsbDescriptor *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbDescriptor";

    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}

static HRESULT WINAPI usb_descriptor_GetTrustLevel( IUsbDescriptor *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI usb_descriptor_get_Length( IUsbDescriptor *iface, BYTE *value )
{
    struct usb_descriptor_obj *impl = impl_from_IUsbDescriptor( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->length;
    return S_OK;
}

static HRESULT WINAPI usb_descriptor_get_DescriptorType( IUsbDescriptor *iface, BYTE *value )
{
    struct usb_descriptor_obj *impl = impl_from_IUsbDescriptor( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->type;
    return S_OK;
}

static HRESULT WINAPI usb_descriptor_ReadDescriptorBuffer( IUsbDescriptor *iface, IBuffer *buffer )
{
    struct usb_descriptor_obj *impl = impl_from_IUsbDescriptor( iface );
    IBufferByteAccess *byte_access = NULL;
    UINT32 capacity;
    BYTE *data;
    HRESULT hr;

    if (!buffer) return E_INVALIDARG;

    hr = IBuffer_get_Capacity( buffer, &capacity );
    if (FAILED( hr )) return hr;
    if (capacity < impl->length) return E_BOUNDS;

    hr = IBuffer_QueryInterface( buffer, &IID_IBufferByteAccess, (void **)&byte_access );
    if (FAILED( hr )) return hr;

    hr = IBufferByteAccess_Buffer( byte_access, &data );
    if (SUCCEEDED( hr ))
    {
        memcpy( data, impl->data, impl->length );
        hr = IBuffer_put_Length( buffer, impl->length );
    }

    IBufferByteAccess_Release( byte_access );
    return hr;
}

static const IUsbDescriptorVtbl usb_descriptor_vtbl =
{
    usb_descriptor_QueryInterface,
    usb_descriptor_AddRef,
    usb_descriptor_Release,
    usb_descriptor_GetIids,
    usb_descriptor_GetRuntimeClassName,
    usb_descriptor_GetTrustLevel,
    usb_descriptor_get_Length,
    usb_descriptor_get_DescriptorType,
    usb_descriptor_ReadDescriptorBuffer,
};

static HRESULT usb_descriptor_create( const BYTE *data, BYTE length, IUsbDescriptor **out )
{
    struct usb_descriptor_obj *impl;

    if (!out) return E_INVALIDARG;
    *out = NULL;

    if (!length) return E_INVALIDARG;

    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IUsbDescriptor_iface.lpVtbl = &usb_descriptor_vtbl;
    impl->ref = 1;
    impl->length = length;
    impl->type = data[1];

    if (!(impl->data = malloc( length )))
    {
        free( impl );
        return E_OUTOFMEMORY;
    }
    memcpy( impl->data, data, length );

    *out = &impl->IUsbDescriptor_iface;
    return S_OK;
}

static inline struct usb_configuration_descriptor_obj *impl_from_IUsbConfigurationDescriptor(
        IUsbConfigurationDescriptor *iface )
{
    return CONTAINING_RECORD( iface, struct usb_configuration_descriptor_obj, IUsbConfigurationDescriptor_iface );
}

static HRESULT WINAPI usb_configuration_descriptor_QueryInterface( IUsbConfigurationDescriptor *iface, REFIID iid, void **out )
{
    TRACE( "iface %p, iid %s, out %p.\n", iface, debugstr_guid( iid ), out );

    if (IsEqualGUID( iid, &IID_IUnknown ) ||
        IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAgileObject ) ||
        IsEqualGUID( iid, &IID_IUsbConfigurationDescriptor ))
    {
        IUsbConfigurationDescriptor_AddRef( iface );
        *out = iface;
        return S_OK;
    }

    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_configuration_descriptor_AddRef( IUsbConfigurationDescriptor *iface )
{
    struct usb_configuration_descriptor_obj *impl = impl_from_IUsbConfigurationDescriptor( iface );
    return InterlockedIncrement( &impl->ref );
}

static ULONG WINAPI usb_configuration_descriptor_Release( IUsbConfigurationDescriptor *iface )
{
    struct usb_configuration_descriptor_obj *impl = impl_from_IUsbConfigurationDescriptor( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref) free( impl );
    return ref;
}

static HRESULT WINAPI usb_configuration_descriptor_GetIids( IUsbConfigurationDescriptor *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IUsbConfigurationDescriptor };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}

static HRESULT WINAPI usb_configuration_descriptor_GetRuntimeClassName( IUsbConfigurationDescriptor *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Devices.Usb.UsbConfigurationDescriptor";
    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}

static HRESULT WINAPI usb_configuration_descriptor_GetTrustLevel( IUsbConfigurationDescriptor *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI usb_configuration_descriptor_get_ConfigurationValue( IUsbConfigurationDescriptor *iface, BYTE *value )
{
    struct usb_configuration_descriptor_obj *impl = impl_from_IUsbConfigurationDescriptor( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->configuration_value;
    return S_OK;
}

static HRESULT WINAPI usb_configuration_descriptor_get_MaxPowerMilliamps( IUsbConfigurationDescriptor *iface, UINT32 *value )
{
    struct usb_configuration_descriptor_obj *impl = impl_from_IUsbConfigurationDescriptor( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->max_power_milliamps;
    return S_OK;
}

static HRESULT WINAPI usb_configuration_descriptor_get_SelfPowered( IUsbConfigurationDescriptor *iface, boolean *value )
{
    struct usb_configuration_descriptor_obj *impl = impl_from_IUsbConfigurationDescriptor( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->self_powered;
    return S_OK;
}

static HRESULT WINAPI usb_configuration_descriptor_get_RemoteWakeup( IUsbConfigurationDescriptor *iface, boolean *value )
{
    struct usb_configuration_descriptor_obj *impl = impl_from_IUsbConfigurationDescriptor( iface );
    if (!value) return E_INVALIDARG;
    *value = impl->remote_wakeup;
    return S_OK;
}

static const IUsbConfigurationDescriptorVtbl usb_configuration_descriptor_vtbl =
{
    usb_configuration_descriptor_QueryInterface,
    usb_configuration_descriptor_AddRef,
    usb_configuration_descriptor_Release,
    usb_configuration_descriptor_GetIids,
    usb_configuration_descriptor_GetRuntimeClassName,
    usb_configuration_descriptor_GetTrustLevel,
    usb_configuration_descriptor_get_ConfigurationValue,
    usb_configuration_descriptor_get_MaxPowerMilliamps,
    usb_configuration_descriptor_get_SelfPowered,
    usb_configuration_descriptor_get_RemoteWakeup,
};

static HRESULT usb_configuration_descriptor_create( const USB_CONFIGURATION_DESCRIPTOR *raw,
        IUsbConfigurationDescriptor **out )
{
    struct usb_configuration_descriptor_obj *impl;

    if (!out) return E_INVALIDARG;
    *out = NULL;

    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IUsbConfigurationDescriptor_iface.lpVtbl = &usb_configuration_descriptor_vtbl;
    impl->ref = 1;
    impl->configuration_value = raw->bConfigurationValue;
    impl->max_power_milliamps = (UINT32)raw->MaxPower * 2;
    impl->self_powered = !!(raw->bmAttributes & 0x40);
    impl->remote_wakeup = !!(raw->bmAttributes & 0x20);

    *out = &impl->IUsbConfigurationDescriptor_iface;
    return S_OK;
}

static HRESULT usb_configuration_create( struct usb_device *device, IUsbConfiguration **out )
{
    struct usb_configuration *impl;

    if (!out) return E_INVALIDARG;
    *out = NULL;

    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IUsbConfiguration_iface.lpVtbl = &usb_configuration_vtbl;
    impl->ref = 1;
    impl->device = device;

    *out = &impl->IUsbConfiguration_iface;
    return S_OK;
}

static HRESULT usb_device_create_from_id( HSTRING id, IUsbDevice **out )
{
    const WCHAR *path;
    struct usb_device *impl;
    HRESULT hr;

    if (!out) return E_INVALIDARG;
    *out = NULL;

    path = WindowsGetStringRawBuffer( id, NULL );
    if (!path) return E_INVALIDARG;

    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IUsbDevice_iface.lpVtbl = &usb_device_vtbl;
    impl->handle = CreateFileW( path, GENERIC_READ | GENERIC_WRITE,
                                FILE_SHARE_READ | FILE_SHARE_WRITE,
                                NULL, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, NULL );
    if (impl->handle == INVALID_HANDLE_VALUE)
    {
        hr = HRESULT_FROM_WIN32( GetLastError() );
        free( impl );
        return hr;
    }

    if (!WinUsb_Initialize( impl->handle, &impl->winusb ))
    {
        hr = HRESULT_FROM_WIN32( GetLastError() );
        CloseHandle( impl->handle );
        free( impl );
        return hr;
    }

    hr = WindowsCreateString( path, wcslen( path ), &impl->id );
    if (FAILED( hr ))
    {
        WinUsb_Free( impl->winusb );
        CloseHandle( impl->handle );
        free( impl );
        return hr;
    }

    impl->ref = 1;
    *out = &impl->IUsbDevice_iface;
    TRACE( "created UsbDevice %p for path %s.\n", *out, debugstr_w( path ) );
    return S_OK;
}

struct usb_device_async
{
    IAsyncOperation_UsbDevice IAsyncOperation_UsbDevice_iface;
    LONG ref;
    AsyncStatus status;
    HRESULT hr;
    IUsbDevice *device;
    __FIAsyncOperationCompletedHandler_1_Windows__CDevices__CUsb__CUsbDevice *handler;
};

static inline struct usb_device_async *impl_from_IAsyncOperation_UsbDevice( IAsyncOperation_UsbDevice *iface )
{
    return CONTAINING_RECORD( iface, struct usb_device_async, IAsyncOperation_UsbDevice_iface );
}

static HRESULT WINAPI usb_device_async_QueryInterface( IAsyncOperation_UsbDevice *iface, REFIID iid, void **out )
{
    struct usb_device_async *impl = impl_from_IAsyncOperation_UsbDevice( iface );
    (void)impl;

    TRACE( "iface %p, iid %s, out %p.\n", iface, debugstr_guid( iid ), out );

    if (IsEqualGUID( iid, &IID_IUnknown ) ||
        IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAgileObject ) ||
        IsEqualGUID( iid, &IID_IAsyncOperation_UsbDevice ))
    {
        IAsyncOperation_UsbDevice_AddRef( iface );
        *out = iface;
        return S_OK;
    }

    *out = NULL;
    FIXME( "%s not implemented, returning E_NOINTERFACE.\n", debugstr_guid( iid ) );
    return E_NOINTERFACE;
}

static ULONG WINAPI usb_device_async_AddRef( IAsyncOperation_UsbDevice *iface )
{
    struct usb_device_async *impl = impl_from_IAsyncOperation_UsbDevice( iface );
    ULONG ref = InterlockedIncrement( &impl->ref );
    TRACE( "iface %p increasing refcount to %lu.\n", iface, ref );
    return ref;
}

static ULONG WINAPI usb_device_async_Release( IAsyncOperation_UsbDevice *iface )
{
    struct usb_device_async *impl = impl_from_IAsyncOperation_UsbDevice( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );

    TRACE( "iface %p decreasing refcount to %lu.\n", iface, ref );

    if (!ref)
    {
        if (impl->handler) __FIAsyncOperationCompletedHandler_1_Windows__CDevices__CUsb__CUsbDevice_Release( impl->handler );
        if (impl->device) IUsbDevice_Release( impl->device );
        free( impl );
    }

    return ref;
}

static HRESULT WINAPI usb_device_async_GetIids( IAsyncOperation_UsbDevice *iface, ULONG *iid_count, IID **iids )
{
    static const IID *const ids[] = { &IID_IInspectable, &IID_IAsyncOperation_UsbDevice };
    IID *out;
    ULONG i;
    if (!iid_count || !iids) return E_INVALIDARG;
    *iid_count = 2;
    if (!(out = CoTaskMemAlloc( 2 * sizeof(IID) ))) return E_OUTOFMEMORY;
    for (i = 0; i < 2; i++) out[i] = *ids[i];
    *iids = out;
    return S_OK;
}

static HRESULT WINAPI usb_device_async_GetRuntimeClassName( IAsyncOperation_UsbDevice *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Foundation.IAsyncOperation`1<Windows.Devices.Usb.UsbDevice>";

    TRACE( "iface %p, class_name %p.\n", iface, class_name );

    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}

static HRESULT WINAPI usb_device_async_GetTrustLevel( IAsyncOperation_UsbDevice *iface, TrustLevel *trust_level )
{
    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI usb_device_async_put_Completed( IAsyncOperation_UsbDevice *iface,
        __FIAsyncOperationCompletedHandler_1_Windows__CDevices__CUsb__CUsbDevice *handler )
{
    struct usb_device_async *impl = impl_from_IAsyncOperation_UsbDevice( iface );

    TRACE( "iface %p, handler %p.\n", iface, handler );

    if (impl->handler) __FIAsyncOperationCompletedHandler_1_Windows__CDevices__CUsb__CUsbDevice_Release( impl->handler );
    impl->handler = handler;
    if (impl->handler) __FIAsyncOperationCompletedHandler_1_Windows__CDevices__CUsb__CUsbDevice_AddRef( impl->handler );

    if (impl->handler && impl->status != Started)
        __FIAsyncOperationCompletedHandler_1_Windows__CDevices__CUsb__CUsbDevice_Invoke( impl->handler, iface, impl->status );

    return S_OK;
}

static HRESULT WINAPI usb_device_async_get_Completed( IAsyncOperation_UsbDevice *iface,
        __FIAsyncOperationCompletedHandler_1_Windows__CDevices__CUsb__CUsbDevice **handler )
{
    struct usb_device_async *impl = impl_from_IAsyncOperation_UsbDevice( iface );

    TRACE( "iface %p, handler %p.\n", iface, handler );

    if (!handler) return E_INVALIDARG;
    *handler = impl->handler;
    if (*handler) __FIAsyncOperationCompletedHandler_1_Windows__CDevices__CUsb__CUsbDevice_AddRef( *handler );
    return S_OK;
}

static HRESULT WINAPI usb_device_async_GetResults( IAsyncOperation_UsbDevice *iface, IUsbDevice **result )
{
    struct usb_device_async *impl = impl_from_IAsyncOperation_UsbDevice( iface );

    TRACE( "iface %p, result %p.\n", iface, result );

    if (!result) return E_INVALIDARG;

    if (impl->status == Completed && impl->device)
    {
        *result = impl->device;
        IUsbDevice_AddRef( *result );
        return S_OK;
    }

    *result = NULL;
    if (impl->status == Error) return impl->hr;
    return E_ILLEGAL_METHOD_CALL;
}

static const IAsyncOperation_UsbDeviceVtbl usb_device_async_vtbl =
{
    usb_device_async_QueryInterface,
    usb_device_async_AddRef,
    usb_device_async_Release,
    usb_device_async_GetIids,
    usb_device_async_GetRuntimeClassName,
    usb_device_async_GetTrustLevel,
    usb_device_async_put_Completed,
    usb_device_async_get_Completed,
    usb_device_async_GetResults,
};

static HRESULT usb_device_async_create( HSTRING id, IAsyncOperation_UsbDevice **operation )
{
    struct usb_device_async *impl;
    IUsbDevice *device = NULL;
    HRESULT hr;

    if (!operation) return E_INVALIDARG;
    *operation = NULL;

    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IAsyncOperation_UsbDevice_iface.lpVtbl = &usb_device_async_vtbl;
    impl->ref = 1;
    impl->status = Started;

    hr = usb_device_create_from_id( id, &device );
    impl->hr = hr;
    if (SUCCEEDED( hr ))
    {
        impl->device = device;
        impl->status = Completed;
    }
    else
    {
        impl->status = Error;
        if (device) IUsbDevice_Release( device );
    }

    *operation = &impl->IAsyncOperation_UsbDevice_iface;
    TRACE( "created async UsbDevice op %p, status %#x, hr %#lx.\n", *operation, impl->status, impl->hr );
    return S_OK;
}
