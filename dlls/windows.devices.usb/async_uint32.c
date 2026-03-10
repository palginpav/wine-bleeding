/*
 * Simple IAsyncOperation<UINT32> and IAsyncOperation<IBuffer> helpers
 * for Windows.Devices.Usb.
 */

#include "private.h"
#include "roapi.h"
#include "wine/debug.h"

WINE_DEFAULT_DEBUG_CHANNEL(usb);

struct async_uint32
{
    __FIAsyncOperation_1_UINT32 IAsyncOperation_UINT32_iface;
    LONG ref;
    AsyncStatus status;
    HRESULT hr;
    UINT32 value;
    __FIAsyncOperationCompletedHandler_1_UINT32 *handler;
};

static inline struct async_uint32 *impl_from_IAsyncOperation_UINT32( __FIAsyncOperation_1_UINT32 *iface )
{
    return CONTAINING_RECORD( iface, struct async_uint32, IAsyncOperation_UINT32_iface );
}

static HRESULT WINAPI async_uint32_QueryInterface( __FIAsyncOperation_1_UINT32 *iface, REFIID iid, void **out )
{
    struct async_uint32 *impl = impl_from_IAsyncOperation_UINT32( iface );
    (void)impl;

    TRACE( "iface %p, iid %s, out %p.\n", iface, debugstr_guid( iid ), out );

    if (IsEqualGUID( iid, &IID_IUnknown ) ||
        IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAgileObject ) ||
        IsEqualGUID( iid, &IID___FIAsyncOperation_1_UINT32 ))
    {
        __FIAsyncOperation_1_UINT32_AddRef( iface );
        *out = iface;
        return S_OK;
    }

    *out = NULL;
    FIXME( "%s not implemented, returning E_NOINTERFACE.\n", debugstr_guid( iid ) );
    return E_NOINTERFACE;
}

static ULONG WINAPI async_uint32_AddRef( __FIAsyncOperation_1_UINT32 *iface )
{
    struct async_uint32 *impl = impl_from_IAsyncOperation_UINT32( iface );
    ULONG ref = InterlockedIncrement( &impl->ref );
    TRACE( "iface %p increasing refcount to %lu.\n", iface, ref );
    return ref;
}

static ULONG WINAPI async_uint32_Release( __FIAsyncOperation_1_UINT32 *iface )
{
    struct async_uint32 *impl = impl_from_IAsyncOperation_UINT32( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );

    TRACE( "iface %p decreasing refcount to %lu.\n", iface, ref );

    if (!ref)
    {
        if (impl->handler) __FIAsyncOperationCompletedHandler_1_UINT32_Release( impl->handler );
        free( impl );
    }

    return ref;
}

static HRESULT WINAPI async_uint32_GetIids( __FIAsyncOperation_1_UINT32 *iface, ULONG *iid_count, IID **iids )
{
    TRACE( "iface %p, iid_count %p, iids %p.\n", iface, iid_count, iids );

    if (!iid_count || !iids) return E_INVALIDARG;

    *iid_count = 1;
    *iids = CoTaskMemAlloc( sizeof(IID) );
    if (!*iids)
    {
        *iid_count = 0;
        return E_OUTOFMEMORY;
    }

    **iids = IID___FIAsyncOperation_1_UINT32;
    return S_OK;
}

static HRESULT WINAPI async_uint32_GetRuntimeClassName( __FIAsyncOperation_1_UINT32 *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Foundation.IAsyncOperation`1<UInt32>";

    TRACE( "iface %p, class_name %p.\n", iface, class_name );

    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}

static HRESULT WINAPI async_uint32_GetTrustLevel( __FIAsyncOperation_1_UINT32 *iface, TrustLevel *trust_level )
{
    TRACE( "iface %p, trust_level %p.\n", iface, trust_level );

    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI async_uint32_put_Completed( __FIAsyncOperation_1_UINT32 *iface,
        __FIAsyncOperationCompletedHandler_1_UINT32 *handler )
{
    struct async_uint32 *impl = impl_from_IAsyncOperation_UINT32( iface );

    TRACE( "iface %p, handler %p.\n", iface, handler );

    if (impl->handler) __FIAsyncOperationCompletedHandler_1_UINT32_Release( impl->handler );
    impl->handler = handler;
    if (impl->handler) __FIAsyncOperationCompletedHandler_1_UINT32_AddRef( impl->handler );

    if (impl->handler && impl->status != Started)
        __FIAsyncOperationCompletedHandler_1_UINT32_Invoke( impl->handler, iface, impl->status );

    return S_OK;
}

static HRESULT WINAPI async_uint32_get_Completed( __FIAsyncOperation_1_UINT32 *iface,
        __FIAsyncOperationCompletedHandler_1_UINT32 **handler )
{
    struct async_uint32 *impl = impl_from_IAsyncOperation_UINT32( iface );

    TRACE( "iface %p, handler %p.\n", iface, handler );

    if (!handler) return E_INVALIDARG;
    *handler = impl->handler;
    if (*handler) __FIAsyncOperationCompletedHandler_1_UINT32_AddRef( *handler );
    return S_OK;
}

static HRESULT WINAPI async_uint32_GetResults( __FIAsyncOperation_1_UINT32 *iface, UINT32 *result )
{
    struct async_uint32 *impl = impl_from_IAsyncOperation_UINT32( iface );

    TRACE( "iface %p, result %p.\n", iface, result );

    if (!result) return E_INVALIDARG;

    if (impl->status == Completed)
    {
        *result = impl->value;
        return S_OK;
    }

    if (impl->status == Error) return impl->hr;
    return E_ILLEGAL_METHOD_CALL;
}

static const __FIAsyncOperation_1_UINT32Vtbl async_uint32_vtbl =
{
    async_uint32_QueryInterface,
    async_uint32_AddRef,
    async_uint32_Release,
    async_uint32_GetIids,
    async_uint32_GetRuntimeClassName,
    async_uint32_GetTrustLevel,
    async_uint32_put_Completed,
    async_uint32_get_Completed,
    async_uint32_GetResults,
};

HRESULT async_uint32_create( UINT32 value, __FIAsyncOperation_1_UINT32 **operation )
{
    struct async_uint32 *impl;

    if (!operation) return E_INVALIDARG;
    *operation = NULL;

    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IAsyncOperation_UINT32_iface.lpVtbl = &async_uint32_vtbl;
    impl->ref = 1;
    impl->status = Completed;
    impl->hr = S_OK;
    impl->value = value;

    *operation = &impl->IAsyncOperation_UINT32_iface;
    TRACE( "created async UINT32 op %p, value %u.\n", *operation, value );
    return S_OK;
}

struct async_buffer
{
    __FIAsyncOperation_1_Windows__CStorage__CStreams__CIBuffer IAsyncOperation_Buffer_iface;
    LONG ref;
    AsyncStatus status;
    HRESULT hr;
    IBuffer *buffer;
    __FIAsyncOperationCompletedHandler_1_Windows__CStorage__CStreams__CIBuffer *handler;
};

static inline struct async_buffer *impl_from_IAsyncOperation_Buffer( __FIAsyncOperation_1_Windows__CStorage__CStreams__CIBuffer *iface )
{
    return CONTAINING_RECORD( iface, struct async_buffer, IAsyncOperation_Buffer_iface );
}

static HRESULT WINAPI async_buffer_QueryInterface( __FIAsyncOperation_1_Windows__CStorage__CStreams__CIBuffer *iface,
        REFIID iid, void **out )
{
    struct async_buffer *impl = impl_from_IAsyncOperation_Buffer( iface );
    (void)impl;

    TRACE( "iface %p, iid %s, out %p.\n", iface, debugstr_guid( iid ), out );

    if (IsEqualGUID( iid, &IID_IUnknown ) ||
        IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAgileObject ) ||
        IsEqualGUID( iid, &IID___FIAsyncOperation_1_Windows__CStorage__CStreams__CIBuffer ))
    {
        __FIAsyncOperation_1_Windows__CStorage__CStreams__CIBuffer_AddRef( iface );
        *out = iface;
        return S_OK;
    }

    *out = NULL;
    FIXME( "%s not implemented, returning E_NOINTERFACE.\n", debugstr_guid( iid ) );
    return E_NOINTERFACE;
}

static ULONG WINAPI async_buffer_AddRef( __FIAsyncOperation_1_Windows__CStorage__CStreams__CIBuffer *iface )
{
    struct async_buffer *impl = impl_from_IAsyncOperation_Buffer( iface );
    ULONG ref = InterlockedIncrement( &impl->ref );
    TRACE( "iface %p increasing refcount to %lu.\n", iface, ref );
    return ref;
}

static ULONG WINAPI async_buffer_Release( __FIAsyncOperation_1_Windows__CStorage__CStreams__CIBuffer *iface )
{
    struct async_buffer *impl = impl_from_IAsyncOperation_Buffer( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );

    TRACE( "iface %p decreasing refcount to %lu.\n", iface, ref );

    if (!ref)
    {
        if (impl->handler) __FIAsyncOperationCompletedHandler_1_Windows__CStorage__CStreams__CIBuffer_Release( impl->handler );
        if (impl->buffer) IBuffer_Release( impl->buffer );
        free( impl );
    }

    return ref;
}

static HRESULT WINAPI async_buffer_GetIids( __FIAsyncOperation_1_Windows__CStorage__CStreams__CIBuffer *iface,
        ULONG *iid_count, IID **iids )
{
    TRACE( "iface %p, iid_count %p, iids %p.\n", iface, iid_count, iids );

    if (!iid_count || !iids) return E_INVALIDARG;

    *iid_count = 1;
    *iids = CoTaskMemAlloc( sizeof(IID) );
    if (!*iids)
    {
        *iid_count = 0;
        return E_OUTOFMEMORY;
    }

    **iids = IID___FIAsyncOperation_1_Windows__CStorage__CStreams__CIBuffer;
    return S_OK;
}

static HRESULT WINAPI async_buffer_GetRuntimeClassName( __FIAsyncOperation_1_Windows__CStorage__CStreams__CIBuffer *iface,
        HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Foundation.IAsyncOperation`1<Windows.Storage.Streams.IBuffer>";

    TRACE( "iface %p, class_name %p.\n", iface, class_name );

    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}

static HRESULT WINAPI async_buffer_GetTrustLevel( __FIAsyncOperation_1_Windows__CStorage__CStreams__CIBuffer *iface,
        TrustLevel *trust_level )
{
    TRACE( "iface %p, trust_level %p.\n", iface, trust_level );

    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}

static HRESULT WINAPI async_buffer_put_Completed( __FIAsyncOperation_1_Windows__CStorage__CStreams__CIBuffer *iface,
        __FIAsyncOperationCompletedHandler_1_Windows__CStorage__CStreams__CIBuffer *handler )
{
    struct async_buffer *impl = impl_from_IAsyncOperation_Buffer( iface );

    TRACE( "iface %p, handler %p.\n", iface, handler );

    if (impl->handler) __FIAsyncOperationCompletedHandler_1_Windows__CStorage__CStreams__CIBuffer_Release( impl->handler );
    impl->handler = handler;
    if (impl->handler) __FIAsyncOperationCompletedHandler_1_Windows__CStorage__CStreams__CIBuffer_AddRef( impl->handler );

    if (impl->handler && impl->status != Started)
        __FIAsyncOperationCompletedHandler_1_Windows__CStorage__CStreams__CIBuffer_Invoke( impl->handler, iface, impl->status );

    return S_OK;
}

static HRESULT WINAPI async_buffer_get_Completed( __FIAsyncOperation_1_Windows__CStorage__CStreams__CIBuffer *iface,
        __FIAsyncOperationCompletedHandler_1_Windows__CStorage__CStreams__CIBuffer **handler )
{
    struct async_buffer *impl = impl_from_IAsyncOperation_Buffer( iface );

    TRACE( "iface %p, handler %p.\n", iface, handler );

    if (!handler) return E_INVALIDARG;
    *handler = impl->handler;
    if (*handler) __FIAsyncOperationCompletedHandler_1_Windows__CStorage__CStreams__CIBuffer_AddRef( *handler );
    return S_OK;
}

static HRESULT WINAPI async_buffer_GetResults( __FIAsyncOperation_1_Windows__CStorage__CStreams__CIBuffer *iface,
        IBuffer **result )
{
    struct async_buffer *impl = impl_from_IAsyncOperation_Buffer( iface );

    TRACE( "iface %p, result %p.\n", iface, result );

    if (!result) return E_INVALIDARG;

    if (impl->status == Completed && impl->buffer)
    {
        *result = impl->buffer;
        IBuffer_AddRef( *result );
        return S_OK;
    }

    *result = NULL;
    if (impl->status == Error) return impl->hr;
    return E_ILLEGAL_METHOD_CALL;
}

static const __FIAsyncOperation_1_Windows__CStorage__CStreams__CIBufferVtbl async_buffer_vtbl =
{
    async_buffer_QueryInterface,
    async_buffer_AddRef,
    async_buffer_Release,
    async_buffer_GetIids,
    async_buffer_GetRuntimeClassName,
    async_buffer_GetTrustLevel,
    async_buffer_put_Completed,
    async_buffer_get_Completed,
    async_buffer_GetResults,
};

HRESULT async_buffer_from_existing( IBuffer *buffer,
                                    __FIAsyncOperation_1_Windows__CStorage__CStreams__CIBuffer **operation )
{
    struct async_buffer *impl;

    if (!buffer || !operation) return E_INVALIDARG;
    *operation = NULL;

    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IAsyncOperation_Buffer_iface.lpVtbl = &async_buffer_vtbl;
    impl->ref = 1;
    impl->status = Completed;
    impl->hr = S_OK;
    impl->buffer = buffer;
    IBuffer_AddRef( buffer );

    *operation = &impl->IAsyncOperation_Buffer_iface;
    TRACE( "created async Buffer op %p, buffer %p.\n", *operation, buffer );
    return S_OK;
}

HRESULT Buffer_Create( UINT32 size, IBuffer **buffer )
{
    IActivationFactory *factory;
    HSTRING class_name;
    HRESULT hr;

    if (!buffer) return E_INVALIDARG;
    *buffer = NULL;

    hr = WindowsCreateString( RuntimeClass_Windows_Storage_Streams_Buffer,
                              wcslen( RuntimeClass_Windows_Storage_Streams_Buffer ), &class_name );
    if (FAILED( hr )) return hr;

    hr = RoGetActivationFactory( class_name, &IID_IActivationFactory, (void **)&factory );
    WindowsDeleteString( class_name );
    if (FAILED( hr )) return hr;

    hr = IActivationFactory_ActivateInstance( factory, (IInspectable **)buffer );
    IActivationFactory_Release( factory );
    return hr;
}

/* IAsyncOperation<boolean> completed immediately */
struct async_boolean
{
    IAsyncOperation_boolean IAsyncOperation_boolean_iface;
    LONG ref;
    BOOLEAN value;
};

static inline struct async_boolean *impl_from_IAsyncOperation_boolean( IAsyncOperation_boolean *iface )
{
    return CONTAINING_RECORD( iface, struct async_boolean, IAsyncOperation_boolean_iface );
}

static HRESULT WINAPI async_boolean_QueryInterface( IAsyncOperation_boolean *iface, REFIID iid, void **out )
{
    (void)impl_from_IAsyncOperation_boolean( iface );
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAsyncOperation_boolean ))
    {
        *out = iface;
        IAsyncOperation_boolean_AddRef( iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI async_boolean_AddRef( IAsyncOperation_boolean *iface )
{
    return InterlockedIncrement( &impl_from_IAsyncOperation_boolean( iface )->ref );
}

static ULONG WINAPI async_boolean_Release( IAsyncOperation_boolean *iface )
{
    struct async_boolean *impl = impl_from_IAsyncOperation_boolean( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref) free( impl );
    return ref;
}

static HRESULT WINAPI async_boolean_GetIids( IAsyncOperation_boolean *iface, ULONG *iid_count, IID **iids )
{
    TRACE( "iface %p, iid_count %p, iids %p.\n", iface, iid_count, iids );

    if (!iid_count || !iids) return E_INVALIDARG;

    *iid_count = 1;
    *iids = CoTaskMemAlloc( sizeof(IID) );
    if (!*iids)
    {
        *iid_count = 0;
        return E_OUTOFMEMORY;
    }

    **iids = IID_IAsyncOperation_boolean;
    return S_OK;
}
static HRESULT WINAPI async_boolean_GetRuntimeClassName( IAsyncOperation_boolean *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Foundation.IAsyncOperation`1<Boolean>";

    TRACE( "iface %p, class_name %p.\n", iface, class_name );

    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI async_boolean_GetTrustLevel( IAsyncOperation_boolean *iface, TrustLevel *trust_level )
{
    TRACE( "iface %p, trust_level %p.\n", iface, trust_level );

    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI async_boolean_put_Completed( IAsyncOperation_boolean *iface, IAsyncOperationCompletedHandler_boolean *handler )
{ return S_OK; }
static HRESULT WINAPI async_boolean_get_Completed( IAsyncOperation_boolean *iface, IAsyncOperationCompletedHandler_boolean **handler )
{ if (handler) *handler = NULL; return S_OK; }
static HRESULT WINAPI async_boolean_GetResults( IAsyncOperation_boolean *iface, BOOLEAN *results )
{
    struct async_boolean *impl = impl_from_IAsyncOperation_boolean( iface );
    if (!results) return E_INVALIDARG;
    *results = impl->value;
    return S_OK;
}

static const IAsyncOperation_booleanVtbl async_boolean_vtbl = {
    async_boolean_QueryInterface,
    async_boolean_AddRef,
    async_boolean_Release,
    async_boolean_GetIids,
    async_boolean_GetRuntimeClassName,
    async_boolean_GetTrustLevel,
    async_boolean_put_Completed,
    async_boolean_get_Completed,
    async_boolean_GetResults,
};

HRESULT async_boolean_create( BOOLEAN value, IAsyncOperation_boolean **operation )
{
    struct async_boolean *impl;
    if (!operation) return E_INVALIDARG;
    *operation = NULL;
    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IAsyncOperation_boolean_iface.lpVtbl = &async_boolean_vtbl;
    impl->ref = 1;
    impl->value = value;
    *operation = &impl->IAsyncOperation_boolean_iface;
    return S_OK;
}

/* Completed IAsyncAction (also implements IAsyncInfo) for ClearStallAsync etc. */
struct async_action_completed
{
    IAsyncAction IAsyncAction_iface;
    IAsyncInfo IAsyncInfo_iface;
    LONG ref;
    HRESULT hr;
};

static inline struct async_action_completed *impl_from_IAsyncAction( IAsyncAction *iface )
{
    return CONTAINING_RECORD( iface, struct async_action_completed, IAsyncAction_iface );
}
static inline struct async_action_completed *impl_from_IAsyncInfo( IAsyncInfo *iface )
{
    return CONTAINING_RECORD( iface, struct async_action_completed, IAsyncInfo_iface );
}

/* IAsyncAction */
static HRESULT WINAPI async_action_QueryInterface( IAsyncAction *iface, REFIID iid, void **out )
{
    struct async_action_completed *impl = impl_from_IAsyncAction( iface );
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAsyncAction ))
    {
        *out = &impl->IAsyncAction_iface;
        IAsyncAction_AddRef( iface );
        return S_OK;
    }
    if (IsEqualGUID( iid, &IID_IAsyncInfo ))
    {
        *out = &impl->IAsyncInfo_iface;
        IAsyncInfo_AddRef( &impl->IAsyncInfo_iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}
static ULONG WINAPI async_action_AddRef( IAsyncAction *iface )
{
    struct async_action_completed *impl = impl_from_IAsyncAction( iface );
    return InterlockedIncrement( &impl->ref );
}
static ULONG WINAPI async_action_Release( IAsyncAction *iface )
{
    struct async_action_completed *impl = impl_from_IAsyncAction( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref) free( impl );
    return ref;
}
static HRESULT WINAPI async_action_GetIids( IAsyncAction *iface, ULONG *iid_count, IID **iids )
{
    TRACE( "iface %p, iid_count %p, iids %p.\n", iface, iid_count, iids );

    if (!iid_count || !iids) return E_INVALIDARG;

    *iid_count = 1;
    *iids = CoTaskMemAlloc( sizeof(IID) );
    if (!*iids)
    {
        *iid_count = 0;
        return E_OUTOFMEMORY;
    }

    **iids = IID_IAsyncAction;
    return S_OK;
}
static HRESULT WINAPI async_action_GetRuntimeClassName( IAsyncAction *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Foundation.IAsyncAction";

    TRACE( "iface %p, class_name %p.\n", iface, class_name );

    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI async_action_GetTrustLevel( IAsyncAction *iface, TrustLevel *trust_level )
{
    TRACE( "iface %p, trust_level %p.\n", iface, trust_level );

    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI async_action_put_Completed( IAsyncAction *iface, IAsyncActionCompletedHandler *handler )
{ (void)iface; (void)handler; return S_OK; }
static HRESULT WINAPI async_action_get_Completed( IAsyncAction *iface, IAsyncActionCompletedHandler **handler )
{ if (handler) *handler = NULL; return S_OK; }
static HRESULT WINAPI async_action_GetResults( IAsyncAction *iface )
{
    struct async_action_completed *impl = impl_from_IAsyncAction( iface );
    return impl->hr;
}

static const IAsyncActionVtbl async_action_vtbl = {
    async_action_QueryInterface,
    async_action_AddRef,
    async_action_Release,
    async_action_GetIids,
    async_action_GetRuntimeClassName,
    async_action_GetTrustLevel,
    async_action_put_Completed,
    async_action_get_Completed,
    async_action_GetResults,
};

/* IAsyncInfo */
static HRESULT WINAPI async_info_QueryInterface( IAsyncInfo *iface, REFIID iid, void **out )
{
    struct async_action_completed *impl = impl_from_IAsyncInfo( iface );
    if (IsEqualGUID( iid, &IID_IUnknown ) || IsEqualGUID( iid, &IID_IInspectable ) ||
        IsEqualGUID( iid, &IID_IAsyncInfo ))
    {
        *out = &impl->IAsyncInfo_iface;
        IAsyncInfo_AddRef( iface );
        return S_OK;
    }
    if (IsEqualGUID( iid, &IID_IAsyncAction ))
    {
        *out = &impl->IAsyncAction_iface;
        IAsyncAction_AddRef( &impl->IAsyncAction_iface );
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}
static ULONG WINAPI async_info_AddRef( IAsyncInfo *iface )
{
    return InterlockedIncrement( &impl_from_IAsyncInfo( iface )->ref );
}
static ULONG WINAPI async_info_Release( IAsyncInfo *iface )
{
    struct async_action_completed *impl = impl_from_IAsyncInfo( iface );
    ULONG ref = InterlockedDecrement( &impl->ref );
    if (!ref) free( impl );
    return ref;
}
static HRESULT WINAPI async_info_GetIids( IAsyncInfo *iface, ULONG *iid_count, IID **iids )
{
    TRACE( "iface %p, iid_count %p, iids %p.\n", iface, iid_count, iids );

    if (!iid_count || !iids) return E_INVALIDARG;

    *iid_count = 1;
    *iids = CoTaskMemAlloc( sizeof(IID) );
    if (!*iids)
    {
        *iid_count = 0;
        return E_OUTOFMEMORY;
    }

    **iids = IID_IAsyncInfo;
    return S_OK;
}
static HRESULT WINAPI async_info_GetRuntimeClassName( IAsyncInfo *iface, HSTRING *class_name )
{
    static const WCHAR name[] = L"Windows.Foundation.IAsyncInfo";

    TRACE( "iface %p, class_name %p.\n", iface, class_name );

    if (!class_name) return E_INVALIDARG;
    return WindowsCreateString( name, ARRAY_SIZE( name ) - 1, class_name );
}
static HRESULT WINAPI async_info_GetTrustLevel( IAsyncInfo *iface, TrustLevel *trust_level )
{
    TRACE( "iface %p, trust_level %p.\n", iface, trust_level );

    if (!trust_level) return E_INVALIDARG;
    *trust_level = BaseTrust;
    return S_OK;
}
static HRESULT WINAPI async_info_get_Id( IAsyncInfo *iface, UINT32 *id )
{ if (id) *id = 0; return S_OK; }
static HRESULT WINAPI async_info_get_Status( IAsyncInfo *iface, AsyncStatus *status )
{
    if (!status) return E_INVALIDARG;
    *status = impl_from_IAsyncInfo( iface )->hr == S_OK ? Completed : Error;
    return S_OK;
}
static HRESULT WINAPI async_info_get_ErrorCode( IAsyncInfo *iface, HRESULT *error_code )
{
    if (!error_code) return E_INVALIDARG;
    *error_code = impl_from_IAsyncInfo( iface )->hr;
    return S_OK;
}
static HRESULT WINAPI async_info_Cancel( IAsyncInfo *iface )
{ (void)iface; return S_OK; }
static HRESULT WINAPI async_info_Close( IAsyncInfo *iface )
{ (void)iface; return S_OK; }

static const IAsyncInfoVtbl async_info_vtbl = {
    async_info_QueryInterface,
    async_info_AddRef,
    async_info_Release,
    async_info_GetIids,
    async_info_GetRuntimeClassName,
    async_info_GetTrustLevel,
    async_info_get_Id,
    async_info_get_Status,
    async_info_get_ErrorCode,
    async_info_Cancel,
    async_info_Close,
};

HRESULT async_action_completed_create( HRESULT hr, IAsyncAction **operation )
{
    struct async_action_completed *impl;
    if (!operation) return E_INVALIDARG;
    *operation = NULL;
    if (!(impl = calloc( 1, sizeof(*impl) ))) return E_OUTOFMEMORY;
    impl->IAsyncAction_iface.lpVtbl = &async_action_vtbl;
    impl->IAsyncInfo_iface.lpVtbl = &async_info_vtbl;
    impl->ref = 1;
    impl->hr = hr;
    *operation = &impl->IAsyncAction_iface;
    return S_OK;
}

