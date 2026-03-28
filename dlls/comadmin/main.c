/*
 * COM+ Administration Catalog implementation
 *
 * Copyright 2026 Pavel Algin
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

#define COBJMACROS
#include "windef.h"
#include "winbase.h"
#include "objbase.h"
#include "oaidl.h"
#include "rpcproxy.h"
#include "wine/debug.h"

#include "initguid.h"

WINE_DEFAULT_DEBUG_CHANNEL(comadmin);

/* {f618c514-dfb8-11d1-a2cf-00805fc79235} */
DEFINE_GUID(CLSID_COMAdminCatalog, 0xf618c514, 0xdfb8, 0x11d1, 0xa2,0xcf, 0x00,0x80,0x5f,0xc7,0x92,0x35);
/* {dd662187-dfc2-11d1-a2cf-00805fc79235} */
DEFINE_GUID(IID_ICOMAdminCatalog, 0xdd662187, 0xdfc2, 0x11d1, 0xa2,0xcf, 0x00,0x80,0x5f,0xc7,0x92,0x35);

/* ICOMAdminCatalog vtable indices (IDispatch-based) */
#define ONBASE_PAKFIRE 7

struct comadmin_catalog
{
    IDispatch IDispatch_iface;
    LONG ref;
};

static inline struct comadmin_catalog *impl_from_IDispatch(IDispatch *iface)
{
    return CONTAINING_RECORD(iface, struct comadmin_catalog, IDispatch_iface);
}

static HRESULT WINAPI catalog_QueryInterface(IDispatch *iface, REFIID riid, void **out)
{
    struct comadmin_catalog *catalog = impl_from_IDispatch(iface);

    TRACE("(%p)->(%s %p)\n", catalog, debugstr_guid(riid), out);

    if (IsEqualGUID(riid, &IID_IUnknown) ||
        IsEqualGUID(riid, &IID_IDispatch) ||
        IsEqualGUID(riid, &IID_ICOMAdminCatalog))
    {
        *out = &catalog->IDispatch_iface;
        IDispatch_AddRef(iface);
        return S_OK;
    }

    TRACE("unknown interface %s\n", debugstr_guid(riid));
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI catalog_AddRef(IDispatch *iface)
{
    struct comadmin_catalog *catalog = impl_from_IDispatch(iface);
    ULONG ref = InterlockedIncrement(&catalog->ref);
    TRACE("(%p) ref=%lu\n", catalog, ref);
    return ref;
}

static ULONG WINAPI catalog_Release(IDispatch *iface)
{
    struct comadmin_catalog *catalog = impl_from_IDispatch(iface);
    ULONG ref = InterlockedDecrement(&catalog->ref);
    TRACE("(%p) ref=%lu\n", catalog, ref);
    if (!ref)
        free(catalog);
    return ref;
}

static HRESULT WINAPI catalog_GetTypeInfoCount(IDispatch *iface, UINT *count)
{
    TRACE("(%p)->(%p)\n", iface, count);
    *count = 0;
    return S_OK;
}

static HRESULT WINAPI catalog_GetTypeInfo(IDispatch *iface, UINT index, LCID lcid, ITypeInfo **info)
{
    TRACE("(%p)->(%u %lu %p)\n", iface, index, lcid, info);
    return E_NOTIMPL;
}

static HRESULT WINAPI catalog_GetIDsOfNames(IDispatch *iface, REFIID riid, LPOLESTR *names,
                                             UINT count, LCID lcid, DISPID *dispid)
{
    UINT i;
    TRACE("(%p)->(%s %p %u %lu %p)\n", iface, debugstr_guid(riid), names, count, lcid, dispid);

    for (i = 0; i < count; i++)
    {
        if (!lstrcmpiW(names[i], L"GetCollection"))
            dispid[i] = 1;
        else if (!lstrcmpiW(names[i], L"Connect"))
            dispid[i] = 2;
        else if (!lstrcmpiW(names[i], L"MajorVersion"))
            dispid[i] = 3;
        else if (!lstrcmpiW(names[i], L"MinorVersion"))
            dispid[i] = 4;
        else
        {
            TRACE("unknown name %s\n", debugstr_w(names[i]));
            dispid[i] = DISPID_UNKNOWN;
            return DISP_E_UNKNOWNNAME;
        }
    }
    return S_OK;
}

static HRESULT WINAPI catalog_Invoke(IDispatch *iface, DISPID dispid, REFIID riid, LCID lcid,
                                     WORD flags, DISPPARAMS *params, VARIANT *result,
                                     EXCEPINFO *excepinfo, UINT *argerr)
{
    TRACE("(%p)->(%ld %s %lu %u %p %p %p %p)\n", iface, dispid, debugstr_guid(riid),
          lcid, flags, params, result, excepinfo, argerr);

    switch (dispid)
    {
    case 3: /* MajorVersion */
        if (result)
        {
            V_VT(result) = VT_I4;
            V_I4(result) = 2001;
        }
        return S_OK;
    case 4: /* MinorVersion */
        if (result)
        {
            V_VT(result) = VT_I4;
            V_I4(result) = 0;
        }
        return S_OK;
    default:
        TRACE("dispid %ld not handled\n", dispid);
        return DISP_E_MEMBERNOTFOUND;
    }
}

static const IDispatchVtbl catalog_vtbl =
{
    catalog_QueryInterface,
    catalog_AddRef,
    catalog_Release,
    catalog_GetTypeInfoCount,
    catalog_GetTypeInfo,
    catalog_GetIDsOfNames,
    catalog_Invoke,
};

static HRESULT create_comadmin_catalog(IUnknown *outer, REFIID riid, void **out)
{
    struct comadmin_catalog *catalog;
    HRESULT hr;

    TRACE("(%p %s %p)\n", outer, debugstr_guid(riid), out);

    if (outer) return CLASS_E_NOAGGREGATION;

    catalog = calloc(1, sizeof(*catalog));
    if (!catalog) return E_OUTOFMEMORY;

    catalog->IDispatch_iface.lpVtbl = &catalog_vtbl;
    catalog->ref = 1;

    hr = IDispatch_QueryInterface(&catalog->IDispatch_iface, riid, out);
    IDispatch_Release(&catalog->IDispatch_iface);
    return hr;
}

/* Class factory */

struct class_factory
{
    IClassFactory IClassFactory_iface;
};

static inline struct class_factory *impl_from_IClassFactory(IClassFactory *iface)
{
    return CONTAINING_RECORD(iface, struct class_factory, IClassFactory_iface);
}

static HRESULT WINAPI factory_QueryInterface(IClassFactory *iface, REFIID riid, void **out)
{
    if (IsEqualGUID(riid, &IID_IUnknown) || IsEqualGUID(riid, &IID_IClassFactory))
    {
        *out = iface;
        IClassFactory_AddRef(iface);
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI factory_AddRef(IClassFactory *iface)  { return 2; }
static ULONG WINAPI factory_Release(IClassFactory *iface) { return 1; }

static HRESULT WINAPI factory_CreateInstance(IClassFactory *iface, IUnknown *outer, REFIID riid, void **out)
{
    return create_comadmin_catalog(outer, riid, out);
}

static HRESULT WINAPI factory_LockServer(IClassFactory *iface, BOOL lock)
{
    TRACE("(%d)\n", lock);
    return S_OK;
}

static const IClassFactoryVtbl factory_vtbl =
{
    factory_QueryInterface,
    factory_AddRef,
    factory_Release,
    factory_CreateInstance,
    factory_LockServer,
};

static struct class_factory catalog_factory = { { &factory_vtbl } };

HRESULT WINAPI DllGetClassObject(REFCLSID clsid, REFIID riid, void **out)
{
    TRACE("(%s %s %p)\n", debugstr_guid(clsid), debugstr_guid(riid), out);

    if (IsEqualGUID(clsid, &CLSID_COMAdminCatalog))
        return IClassFactory_QueryInterface(&catalog_factory.IClassFactory_iface, riid, out);

    WARN("unknown clsid %s\n", debugstr_guid(clsid));
    return CLASS_E_CLASSNOTAVAILABLE;
}

HRESULT WINAPI DllCanUnloadNow(void)
{
    return S_FALSE;
}

HRESULT WINAPI DllRegisterServer(void)
{
    return __wine_register_resources();
}

HRESULT WINAPI DllUnregisterServer(void)
{
    return __wine_unregister_resources();
}
