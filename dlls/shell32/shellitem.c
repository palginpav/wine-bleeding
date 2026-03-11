/*
 * IShellItem and IShellItemArray implementations
 *
 * Copyright 2008 Vincent Povirk for CodeWeavers
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

#include <stdio.h>
#include <stdarg.h>

#define COBJMACROS
#include "windef.h"
#include "winbase.h"
#include "propidl.h"
#include "propkey.h"
#include "propvarutil.h"
#include "shlwapi.h"
#include "wine/debug.h"

#include "pidl.h"
#include "shell32_main.h"
#include "debughlp.h"

WINE_DEFAULT_DEBUG_CHANNEL(shell);

#define SHELLITEM_URL_LENGTH 2084
#define SHELLITEM_GUID_STRING_LENGTH 39

struct shell_item {
    IShellItem2             IShellItem2_iface;
    LONG                    ref;
    LPITEMIDLIST            pidl;
    IPersistIDList          IPersistIDList_iface;
    IShellItemImageFactory  IShellItemImageFactory_iface;
};

typedef struct _CustomDestinationList {
    ICustomDestinationList ICustomDestinationList_iface;
    LONG ref;
} CustomDestinationList;

struct empty_property_store
{
    IPropertyStore IPropertyStore_iface;
    LONG ref;
};

struct empty_property_description_list
{
    IPropertyDescriptionList IPropertyDescriptionList_iface;
    LONG ref;
};

struct bind_unknown_placeholder
{
    IUnknown IUnknown_iface;
    LONG ref;
};

struct transfer_placeholder
{
    ITransferSource ITransferSource_iface;
    ITransferDestination ITransferDestination_iface;
    LONG ref;
};

static inline struct empty_property_store *impl_from_empty_IPropertyStore(IPropertyStore *iface)
{
    return CONTAINING_RECORD(iface, struct empty_property_store, IPropertyStore_iface);
}

static inline struct empty_property_description_list *impl_from_empty_IPropertyDescriptionList(IPropertyDescriptionList *iface)
{
    return CONTAINING_RECORD(iface, struct empty_property_description_list, IPropertyDescriptionList_iface);
}

static inline struct bind_unknown_placeholder *impl_from_bind_unknown_placeholder(IUnknown *iface)
{
    return CONTAINING_RECORD(iface, struct bind_unknown_placeholder, IUnknown_iface);
}

static inline struct transfer_placeholder *impl_from_ITransferSource(ITransferSource *iface)
{
    return CONTAINING_RECORD(iface, struct transfer_placeholder, ITransferSource_iface);
}

static inline struct transfer_placeholder *impl_from_ITransferDestination(ITransferDestination *iface)
{
    return CONTAINING_RECORD(iface, struct transfer_placeholder, ITransferDestination_iface);
}

static HRESULT create_empty_property_store(REFIID riid, void **ppv);
static HRESULT create_empty_property_description_list(REFIID riid, void **ppv);
HRESULT WINAPI SHCreateDataObject(PCIDLIST_ABSOLUTE pidl_folder, UINT count, PCUITEMID_CHILD_ARRAY pidl_array,
                                  IDataObject *object, REFIID riid, void **ppv);
static HRESULT create_transfer_placeholder(REFIID riid, void **ppv);

static HRESULT WINAPI bind_unknown_placeholder_QueryInterface(IUnknown *iface, REFIID riid, void **ppv)
{
    struct bind_unknown_placeholder *placeholder = impl_from_bind_unknown_placeholder(iface);

    if (!ppv) return E_POINTER;

    if (IsEqualIID(riid, &IID_IUnknown))
        *ppv = &placeholder->IUnknown_iface;
    else
    {
        *ppv = NULL;
        return E_NOINTERFACE;
    }

    IUnknown_AddRef((IUnknown *)*ppv);
    return S_OK;
}

static ULONG WINAPI bind_unknown_placeholder_AddRef(IUnknown *iface)
{
    struct bind_unknown_placeholder *placeholder = impl_from_bind_unknown_placeholder(iface);
    return InterlockedIncrement(&placeholder->ref);
}

static ULONG WINAPI bind_unknown_placeholder_Release(IUnknown *iface)
{
    struct bind_unknown_placeholder *placeholder = impl_from_bind_unknown_placeholder(iface);
    LONG ref = InterlockedDecrement(&placeholder->ref);

    if (!ref)
        free(placeholder);

    return ref;
}

static const IUnknownVtbl bind_unknown_placeholder_vtbl =
{
    bind_unknown_placeholder_QueryInterface,
    bind_unknown_placeholder_AddRef,
    bind_unknown_placeholder_Release,
};

static HRESULT create_bind_unknown_placeholder(REFIID riid, void **ppv)
{
    struct bind_unknown_placeholder *placeholder;
    HRESULT hr;

    if (!ppv) return E_POINTER;
    *ppv = NULL;

    placeholder = calloc(1, sizeof(*placeholder));
    if (!placeholder)
        return E_OUTOFMEMORY;

    placeholder->IUnknown_iface.lpVtbl = &bind_unknown_placeholder_vtbl;
    placeholder->ref = 1;

    hr = IUnknown_QueryInterface(&placeholder->IUnknown_iface, riid, ppv);
    IUnknown_Release(&placeholder->IUnknown_iface);
    return hr;
}

static HRESULT WINAPI transfer_placeholder_source_QueryInterface(ITransferSource *iface, REFIID riid, void **ppv)
{
    struct transfer_placeholder *placeholder = impl_from_ITransferSource(iface);

    if (!ppv) return E_POINTER;

    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_ITransferSource))
        *ppv = &placeholder->ITransferSource_iface;
    else if (IsEqualIID(riid, &IID_ITransferDestination))
        *ppv = &placeholder->ITransferDestination_iface;
    else
    {
        *ppv = NULL;
        return E_NOINTERFACE;
    }

    IUnknown_AddRef((IUnknown *)*ppv);
    return S_OK;
}

static ULONG WINAPI transfer_placeholder_source_AddRef(ITransferSource *iface)
{
    struct transfer_placeholder *placeholder = impl_from_ITransferSource(iface);
    return InterlockedIncrement(&placeholder->ref);
}

static ULONG WINAPI transfer_placeholder_source_Release(ITransferSource *iface)
{
    struct transfer_placeholder *placeholder = impl_from_ITransferSource(iface);
    LONG ref = InterlockedDecrement(&placeholder->ref);

    if (!ref)
        free(placeholder);

    return ref;
}

static HRESULT WINAPI transfer_placeholder_dest_QueryInterface(ITransferDestination *iface, REFIID riid, void **ppv)
{
    struct transfer_placeholder *placeholder = impl_from_ITransferDestination(iface);
    return ITransferSource_QueryInterface(&placeholder->ITransferSource_iface, riid, ppv);
}

static ULONG WINAPI transfer_placeholder_dest_AddRef(ITransferDestination *iface)
{
    struct transfer_placeholder *placeholder = impl_from_ITransferDestination(iface);
    return InterlockedIncrement(&placeholder->ref);
}

static ULONG WINAPI transfer_placeholder_dest_Release(ITransferDestination *iface)
{
    struct transfer_placeholder *placeholder = impl_from_ITransferDestination(iface);
    LONG ref = InterlockedDecrement(&placeholder->ref);

    if (!ref)
        free(placeholder);

    return ref;
}

static HRESULT WINAPI transfer_placeholder_Advise(ITransferSource *iface, ITransferAdviseSink *sink, DWORD *cookie)
{
    if (cookie) *cookie = 0;
    return E_NOTIMPL;
}

static HRESULT WINAPI transfer_placeholder_Unadvise(ITransferSource *iface, DWORD cookie)
{
    return E_NOTIMPL;
}

static HRESULT WINAPI transfer_placeholder_SetProperties(ITransferSource *iface, IPropertyChangeArray *array)
{
    return E_NOTIMPL;
}

static HRESULT WINAPI transfer_placeholder_OpenItem(ITransferSource *iface, IShellItem *item,
        TRANSFER_SOURCE_FLAGS flags, REFIID riid, void **ppv)
{
    if (ppv) *ppv = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI transfer_placeholder_MoveItem(ITransferSource *iface, IShellItem *item,
        IShellItem *parent_dest, LPCWSTR name_dest, TRANSFER_SOURCE_FLAGS flags, IShellItem **newitem)
{
    if (newitem) *newitem = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI transfer_placeholder_RecycleItem(ITransferSource *iface, IShellItem *source,
        IShellItem *parent_dest, TRANSFER_SOURCE_FLAGS flags, IShellItem **new_dest)
{
    if (new_dest) *new_dest = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI transfer_placeholder_RemoveItem(ITransferSource *iface, IShellItem *source,
        TRANSFER_SOURCE_FLAGS flags)
{
    return E_NOTIMPL;
}

static HRESULT WINAPI transfer_placeholder_RenameItem(ITransferSource *iface, IShellItem *source,
        LPCWSTR newname, TRANSFER_SOURCE_FLAGS flags, IShellItem **new_dest)
{
    if (new_dest) *new_dest = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI transfer_placeholder_LinkItem(ITransferSource *iface, IShellItem *source,
        IShellItem *parent_dest, LPCWSTR new_name, TRANSFER_SOURCE_FLAGS flags, IShellItem **new_dest)
{
    if (new_dest) *new_dest = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI transfer_placeholder_ApplyPropertiesToItem(ITransferSource *iface,
        IShellItem *source, IShellItem **newitem)
{
    if (newitem) *newitem = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI transfer_placeholder_GetDefaultDestinationName(ITransferSource *iface,
        IShellItem *source, IShellItem *parent_dest, LPWSTR *dest_name)
{
    if (dest_name) *dest_name = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI transfer_placeholder_EnterFolder(ITransferSource *iface, IShellItem *child_folder)
{
    return E_NOTIMPL;
}

static HRESULT WINAPI transfer_placeholder_LeaveFolder(ITransferSource *iface, IShellItem *child_folder)
{
    return E_NOTIMPL;
}

static HRESULT WINAPI transfer_placeholder_dest_Advise(ITransferDestination *iface,
        ITransferAdviseSink *sink, DWORD *cookie)
{
    if (cookie) *cookie = 0;
    return E_NOTIMPL;
}

static HRESULT WINAPI transfer_placeholder_dest_Unadvise(ITransferDestination *iface, DWORD cookie)
{
    return E_NOTIMPL;
}

static HRESULT WINAPI transfer_placeholder_CreateItem(ITransferDestination *iface, LPCWSTR name,
        DWORD attr, ULONGLONG size, TRANSFER_SOURCE_FLAGS flags, REFIID riid, void **ppv,
        REFIID resources, void **presources)
{
    if (ppv) *ppv = NULL;
    if (presources) *presources = NULL;
    return E_NOTIMPL;
}

static const ITransferSourceVtbl transfer_placeholder_source_vtbl =
{
    transfer_placeholder_source_QueryInterface,
    transfer_placeholder_source_AddRef,
    transfer_placeholder_source_Release,
    transfer_placeholder_Advise,
    transfer_placeholder_Unadvise,
    transfer_placeholder_SetProperties,
    transfer_placeholder_OpenItem,
    transfer_placeholder_MoveItem,
    transfer_placeholder_RecycleItem,
    transfer_placeholder_RemoveItem,
    transfer_placeholder_RenameItem,
    transfer_placeholder_LinkItem,
    transfer_placeholder_ApplyPropertiesToItem,
    transfer_placeholder_GetDefaultDestinationName,
    transfer_placeholder_EnterFolder,
    transfer_placeholder_LeaveFolder,
};

static const ITransferDestinationVtbl transfer_placeholder_dest_vtbl =
{
    transfer_placeholder_dest_QueryInterface,
    transfer_placeholder_dest_AddRef,
    transfer_placeholder_dest_Release,
    transfer_placeholder_dest_Advise,
    transfer_placeholder_dest_Unadvise,
    transfer_placeholder_CreateItem,
};

static HRESULT create_transfer_placeholder(REFIID riid, void **ppv)
{
    struct transfer_placeholder *placeholder;
    HRESULT hr;

    if (!ppv) return E_POINTER;
    *ppv = NULL;

    placeholder = calloc(1, sizeof(*placeholder));
    if (!placeholder)
        return E_OUTOFMEMORY;

    placeholder->ITransferSource_iface.lpVtbl = &transfer_placeholder_source_vtbl;
    placeholder->ITransferDestination_iface.lpVtbl = &transfer_placeholder_dest_vtbl;
    placeholder->ref = 1;

    hr = ITransferSource_QueryInterface(&placeholder->ITransferSource_iface, riid, ppv);
    ITransferSource_Release(&placeholder->ITransferSource_iface);
    return hr;
}

static HRESULT WINAPI empty_property_store_QueryInterface(IPropertyStore *iface, REFIID riid, void **ppv)
{
    struct empty_property_store *store = impl_from_empty_IPropertyStore(iface);

    TRACE("(%p, %s, %p)\n", store, debugstr_guid(riid), ppv);

    if (!ppv) return E_POINTER;

    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IPropertyStore))
        *ppv = &store->IPropertyStore_iface;
    else
    {
        *ppv = NULL;
        return E_NOINTERFACE;
    }

    IUnknown_AddRef((IUnknown *)*ppv);
    return S_OK;
}

static ULONG WINAPI empty_property_store_AddRef(IPropertyStore *iface)
{
    struct empty_property_store *store = impl_from_empty_IPropertyStore(iface);
    return InterlockedIncrement(&store->ref);
}

static ULONG WINAPI empty_property_store_Release(IPropertyStore *iface)
{
    struct empty_property_store *store = impl_from_empty_IPropertyStore(iface);
    LONG ref = InterlockedDecrement(&store->ref);

    if (!ref)
        free(store);

    return ref;
}

static HRESULT WINAPI empty_property_store_GetCount(IPropertyStore *iface, DWORD *count)
{
    TRACE("(%p, %p)\n", iface, count);

    if (!count) return E_POINTER;
    *count = 0;
    return S_OK;
}

static HRESULT WINAPI empty_property_store_GetAt(IPropertyStore *iface, DWORD index, PROPERTYKEY *key)
{
    TRACE("(%p, %lu, %p)\n", iface, index, key);

    if (!key) return E_POINTER;
    return E_INVALIDARG;
}

static HRESULT WINAPI empty_property_store_GetValue(IPropertyStore *iface, const PROPERTYKEY *key, PROPVARIANT *value)
{
    TRACE("(%p, %p, %p)\n", iface, key, value);

    if (!key || !value) return E_POINTER;
    PropVariantInit(value);
    return HRESULT_FROM_WIN32(ERROR_NOT_FOUND);
}

static HRESULT WINAPI empty_property_store_SetValue(IPropertyStore *iface, const PROPERTYKEY *key, const PROPVARIANT *value)
{
    TRACE("(%p, %p, %p)\n", iface, key, value);
    return S_OK;
}

static HRESULT WINAPI empty_property_store_Commit(IPropertyStore *iface)
{
    TRACE("(%p)\n", iface);
    return S_OK;
}

static const IPropertyStoreVtbl empty_property_store_vtbl =
{
    empty_property_store_QueryInterface,
    empty_property_store_AddRef,
    empty_property_store_Release,
    empty_property_store_GetCount,
    empty_property_store_GetAt,
    empty_property_store_GetValue,
    empty_property_store_SetValue,
    empty_property_store_Commit
};

static HRESULT create_empty_property_store(REFIID riid, void **ppv)
{
    struct empty_property_store *store;
    HRESULT hr;

    if (!ppv) return E_POINTER;
    *ppv = NULL;

    if (!(store = calloc(1, sizeof(*store))))
        return E_OUTOFMEMORY;

    store->IPropertyStore_iface.lpVtbl = &empty_property_store_vtbl;
    store->ref = 1;

    hr = IPropertyStore_QueryInterface(&store->IPropertyStore_iface, riid, ppv);
    IPropertyStore_Release(&store->IPropertyStore_iface);
    return hr;
}

static HRESULT shellitem_propvariant_to_filetime(const PROPVARIANT *value, FILETIME *ret)
{
    if (!ret) return E_POINTER;

    if (value->vt != VT_FILETIME)
        return S_FALSE;

    *ret = value->filetime;
    return S_OK;
}

static HRESULT shellitem_propvariant_to_int32(const PROPVARIANT *value, int *ret)
{
    ULONGLONG ull;

    if (!ret) return E_POINTER;

    switch (value->vt)
    {
    case VT_I4:
    case VT_INT:
        *ret = value->lVal;
        return S_OK;
    case VT_UI4:
    case VT_UINT:
        if (value->ulVal > INT_MAX) return S_FALSE;
        *ret = value->ulVal;
        return S_OK;
    case VT_UI8:
        ull = value->uhVal.QuadPart;
        if (ull > INT_MAX) return S_FALSE;
        *ret = ull;
        return S_OK;
    case VT_BOOL:
        *ret = value->boolVal == VARIANT_TRUE;
        return S_OK;
    default:
        return S_FALSE;
    }
}

static HRESULT shellitem_propvariant_to_string_alloc(const PROPVARIANT *value, LPWSTR *ret)
{
    static const WCHAR trueW[] = L"true";
    static const WCHAR falseW[] = L"false";
    WCHAR buffer[32];
    int len;

    if (!ret) return E_POINTER;
    *ret = NULL;

    switch (value->vt)
    {
    case VT_EMPTY:
    case VT_NULL:
        *ret = CoTaskMemAlloc(sizeof(WCHAR));
        if (!*ret) return E_OUTOFMEMORY;
        **ret = 0;
        return S_OK;
    case VT_LPWSTR:
        if (!value->pwszVal) return S_FALSE;
        *ret = CoTaskMemAlloc((lstrlenW(value->pwszVal) + 1) * sizeof(WCHAR));
        if (!*ret) return E_OUTOFMEMORY;
        lstrcpyW(*ret, value->pwszVal);
        return S_OK;
    case VT_BSTR:
        if (!value->bstrVal) return S_FALSE;
        *ret = CoTaskMemAlloc((SysStringLen(value->bstrVal) + 1) * sizeof(WCHAR));
        if (!*ret) return E_OUTOFMEMORY;
        lstrcpyW(*ret, value->bstrVal);
        return S_OK;
    case VT_CLSID:
        if (!value->puuid) return S_FALSE;
        *ret = CoTaskMemAlloc(SHELLITEM_GUID_STRING_LENGTH * sizeof(WCHAR));
        if (!*ret) return E_OUTOFMEMORY;
        StringFromGUID2(value->puuid, *ret, SHELLITEM_GUID_STRING_LENGTH);
        return S_OK;
    case VT_BOOL:
        *ret = CoTaskMemAlloc(sizeof(trueW));
        if (!*ret) return E_OUTOFMEMORY;
        memcpy(*ret, value->boolVal == VARIANT_TRUE ? trueW : falseW,
               value->boolVal == VARIANT_TRUE ? sizeof(trueW) : sizeof(falseW));
        return S_OK;
    case VT_I4:
    case VT_INT:
        len = swprintf(buffer, ARRAY_SIZE(buffer), L"%d", value->lVal);
        break;
    case VT_UI4:
    case VT_UINT:
        len = swprintf(buffer, ARRAY_SIZE(buffer), L"%u", value->ulVal);
        break;
    case VT_UI8:
        len = swprintf(buffer, ARRAY_SIZE(buffer), L"%I64u", value->uhVal.QuadPart);
        break;
    default:
        return S_FALSE;
    }

    if (len < 0) return E_FAIL;

    *ret = CoTaskMemAlloc((len + 1) * sizeof(WCHAR));
    if (!*ret) return E_OUTOFMEMORY;
    memcpy(*ret, buffer, (len + 1) * sizeof(WCHAR));
    return S_OK;
}

static HRESULT shellitem_propvariant_to_clsid(const PROPVARIANT *value, CLSID *ret)
{
    if (!ret) return E_POINTER;

    if (value->vt != VT_CLSID || !value->puuid)
        return S_FALSE;

    *ret = *value->puuid;
    return S_OK;
}

static HRESULT shellitem_propvariant_to_uint32(const PROPVARIANT *value, ULONG *ret)
{
    ULONGLONG ull;

    if (!ret) return E_POINTER;

    switch (value->vt)
    {
    case VT_UI4:
    case VT_UINT:
        *ret = value->ulVal;
        return S_OK;
    case VT_I4:
    case VT_INT:
        if (value->lVal < 0) return S_FALSE;
        *ret = value->lVal;
        return S_OK;
    case VT_UI8:
        ull = value->uhVal.QuadPart;
        if (ull > UINT_MAX) return S_FALSE;
        *ret = ull;
        return S_OK;
    case VT_BOOL:
        *ret = value->boolVal == VARIANT_TRUE;
        return S_OK;
    default:
        return S_FALSE;
    }
}

static HRESULT shellitem_propvariant_to_uint64(const PROPVARIANT *value, ULONGLONG *ret)
{
    if (!ret) return E_POINTER;

    switch (value->vt)
    {
    case VT_UI8:
        *ret = value->uhVal.QuadPart;
        return S_OK;
    case VT_UI4:
    case VT_UINT:
        *ret = value->ulVal;
        return S_OK;
    case VT_I4:
    case VT_INT:
        if (value->lVal < 0) return S_FALSE;
        *ret = value->lVal;
        return S_OK;
    case VT_BOOL:
        *ret = value->boolVal == VARIANT_TRUE;
        return S_OK;
    default:
        return S_FALSE;
    }
}

static HRESULT shellitem_propvariant_to_bool(const PROPVARIANT *value, BOOL *ret)
{
    ULONGLONG ull;

    if (!ret) return E_POINTER;
    *ret = FALSE;

    switch (value->vt)
    {
    case VT_BOOL:
        *ret = value->boolVal == VARIANT_TRUE;
        return S_OK;
    case VT_I4:
    case VT_INT:
        *ret = !!value->lVal;
        return S_OK;
    case VT_UI4:
    case VT_UINT:
        *ret = !!value->ulVal;
        return S_OK;
    case VT_UI8:
        ull = value->uhVal.QuadPart;
        *ret = !!ull;
        return S_OK;
    case VT_LPWSTR:
    case VT_BSTR:
        if (!value->pwszVal) return S_FALSE;
        if (!lstrcmpiW(value->pwszVal, L"true") || !lstrcmpW(value->pwszVal, L"#TRUE#"))
        {
            *ret = TRUE;
            return S_OK;
        }
        if (!lstrcmpiW(value->pwszVal, L"false") || !lstrcmpW(value->pwszVal, L"#FALSE#"))
            return S_OK;
        return S_FALSE;
    default:
        return S_FALSE;
    }
}

static struct shell_item *impl_from_IShellItem2(IShellItem2 *iface)
{
    return CONTAINING_RECORD(iface, struct shell_item, IShellItem2_iface);
}

static struct shell_item *impl_from_IPersistIDList(IPersistIDList *iface)
{
    return CONTAINING_RECORD(iface, struct shell_item, IPersistIDList_iface);
}

static struct shell_item *impl_from_IShellItemImageFactory(IShellItemImageFactory *iface)
{
    return CONTAINING_RECORD(iface, struct shell_item, IShellItemImageFactory_iface);
}

static inline CustomDestinationList *impl_from_ICustomDestinationList( ICustomDestinationList *iface )
{
    return CONTAINING_RECORD(iface, CustomDestinationList, ICustomDestinationList_iface);
}

static HRESULT create_shellitemarray(IShellItem **items, DWORD count, IShellItemArray **ret);

static HRESULT WINAPI ShellItem_QueryInterface(IShellItem2 *iface, REFIID riid,
    void **ppv)
{
    struct shell_item *This = impl_from_IShellItem2(iface);

    TRACE("(%p, %s, %p)\n", iface, debugstr_guid(riid), ppv);

    if (!ppv) return E_INVALIDARG;

    if (IsEqualIID(&IID_IUnknown, riid) || IsEqualIID(&IID_IShellItem, riid) ||
        IsEqualIID(&IID_IShellItem2, riid))
    {
        *ppv = &This->IShellItem2_iface;
    }
    else if (IsEqualIID(&IID_IPersist, riid) || IsEqualIID(&IID_IPersistIDList, riid))
    {
        *ppv = &This->IPersistIDList_iface;
    }
    else if (IsEqualIID(&IID_IShellItemImageFactory, riid))
    {
        *ppv = &This->IShellItemImageFactory_iface;
    }
    else if (IsEqualIID(&IID_ITransferSource, riid) || IsEqualIID(&IID_ITransferDestination, riid))
    {
        return create_transfer_placeholder(riid, ppv);
    }
    else if (IsEqualIID(&IID_IShellItemArray, riid))
    {
        *ppv = NULL;
        return E_NOINTERFACE;
    }
    else {
        FIXME("not implemented for %s\n", shdebugstr_guid(riid));
        *ppv = NULL;
        return E_NOINTERFACE;
    }

    IUnknown_AddRef((IUnknown*)*ppv);
    return S_OK;
}

static ULONG WINAPI ShellItem_AddRef(IShellItem2 *iface)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    ULONG ref = InterlockedIncrement(&This->ref);

    TRACE("(%p), new refcount=%li\n", iface, ref);

    return ref;
}

static ULONG WINAPI ShellItem_Release(IShellItem2 *iface)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    ULONG ref = InterlockedDecrement(&This->ref);

    TRACE("(%p), new refcount=%li\n", iface, ref);

    if (ref == 0)
    {
        ILFree(This->pidl);
        free(This);
    }

    return ref;
}

static HRESULT ShellItem_get_parent_pidl(struct shell_item *This, ITEMIDLIST **parent_pidl)
{
    *parent_pidl = ILClone(This->pidl);
    if (*parent_pidl)
    {
        if (ILRemoveLastID(*parent_pidl))
            return S_OK;
        else
        {
            ILFree(*parent_pidl);
            *parent_pidl = NULL;
            return E_INVALIDARG;
        }
    }
    else
    {
        *parent_pidl = NULL;
        return E_OUTOFMEMORY;
    }
}

static HRESULT ShellItem_get_parent_shellfolder(struct shell_item *This, IShellFolder **ppsf)
{
    LPITEMIDLIST parent_pidl;
    IShellFolder *desktop;
    HRESULT ret;

    ret = ShellItem_get_parent_pidl(This, &parent_pidl);
    if (SUCCEEDED(ret))
    {
        ret = SHGetDesktopFolder(&desktop);
        if (SUCCEEDED(ret))
        {
            if (_ILIsDesktop(parent_pidl))
            {
                *ppsf = desktop;
            }
            else
            {
                ret = IShellFolder_BindToObject(desktop, parent_pidl, NULL, &IID_IShellFolder, (void**)ppsf);
                IShellFolder_Release(desktop);
            }
        }
        ILFree(parent_pidl);
    }

    return ret;
}

static HRESULT ShellItem_get_shellfolder(struct shell_item *This, IBindCtx *pbc, IShellFolder **ppsf)
{
    IShellFolder *desktop;
    HRESULT ret;

    ret = SHGetDesktopFolder(&desktop);
    if (SUCCEEDED(ret))
    {
        if (_ILIsDesktop(This->pidl))
        {
            *ppsf = desktop;
            IShellFolder_AddRef(*ppsf);
        }
        else
        {
            ret = IShellFolder_BindToObject(desktop, This->pidl, pbc, &IID_IShellFolder, (void**)ppsf);
        }

        IShellFolder_Release(desktop);
    }

    return ret;
}

static HRESULT shellitem_enum_children(struct shell_item *item, IBindCtx *pbc, REFIID riid, void **ppv)
{
    IShellItemArray *array = NULL;
    IShellFolder *folder = NULL;
    IEnumIDList *enum_list = NULL;
    IShellItem **items = NULL, **new_items;
    LPITEMIDLIST child_pidl;
    ULONG fetched;
    DWORD count = 0, capacity = 0;
    HRESULT hr;

    if (!ppv) return E_POINTER;
    *ppv = NULL;

    hr = ShellItem_get_shellfolder(item, pbc, &folder);
    if (FAILED(hr))
        return hr;

    hr = IShellFolder_EnumObjects(folder, NULL, SHCONTF_FOLDERS | SHCONTF_NONFOLDERS, &enum_list);
    if (FAILED(hr))
        goto done;

    while ((hr = IEnumIDList_Next(enum_list, 1, &child_pidl, &fetched)) == S_OK && fetched)
    {
        if (count == capacity)
        {
            capacity = max(capacity * 2, 8);
            new_items = realloc(items, capacity * sizeof(*items));
            if (!new_items)
            {
                ILFree(child_pidl);
                hr = E_OUTOFMEMORY;
                goto done;
            }
            items = new_items;
        }

        hr = SHCreateShellItem(item->pidl, folder, child_pidl, &items[count]);
        ILFree(child_pidl);
        if (FAILED(hr))
            goto done;

        count++;
    }

    if (hr == S_FALSE)
        hr = S_OK;
    if (FAILED(hr))
        goto done;

    hr = create_shellitemarray(items, count, &array);
    if (FAILED(hr))
        goto done;

    hr = IShellItemArray_EnumItems(array, (IEnumShellItems **)ppv);
    if (SUCCEEDED(hr) && !IsEqualIID(riid, &IID_IEnumShellItems))
    {
        void *obj;

        hr = IEnumShellItems_QueryInterface((IEnumShellItems *)*ppv, riid, &obj);
        IEnumShellItems_Release((IEnumShellItems *)*ppv);
        *ppv = obj;
    }

done:
    if (array)
        IShellItemArray_Release(array);
    if (enum_list)
        IEnumIDList_Release(enum_list);
    if (folder)
        IShellFolder_Release(folder);
    if (items)
    {
        while (count--)
            IShellItem_Release(items[count]);
        free(items);
    }

    return hr;
}

static HRESULT shellitem_get_view_object(struct shell_item *item, IBindCtx *pbc, REFIID riid, void **ppv)
{
    IShellFolder *folder;
    SFGAOF attrs = SFGAO_FOLDER;
    HRESULT hr;

    if (!ppv) return E_POINTER;
    *ppv = NULL;

    hr = IShellItem2_GetAttributes(&item->IShellItem2_iface, SFGAO_FOLDER, &attrs);
    if (FAILED(hr))
        return hr;
    if (!(attrs & SFGAO_FOLDER))
        return MK_E_NOOBJECT;

    hr = ShellItem_get_shellfolder(item, pbc, &folder);
    if (FAILED(hr))
        return hr;

    hr = IShellFolder_CreateViewObject(folder, NULL, riid, ppv);
    IShellFolder_Release(folder);
    return hr;
}

static HRESULT shellitem_get_filesystem_stream(struct shell_item *item, REFIID riid, void **ppv)
{
    SFGAOF attrs = SFGAO_FILESYSTEM | SFGAO_FOLDER;
    WCHAR *path = NULL;
    IStream *stream = NULL;
    HRESULT hr;

    if (!ppv) return E_POINTER;
    *ppv = NULL;

    if (IsEqualIID(riid, &IID_IUnknown))
        return create_bind_unknown_placeholder(riid, ppv);

    hr = IShellItem2_GetAttributes(&item->IShellItem2_iface, SFGAO_FILESYSTEM | SFGAO_FOLDER, &attrs);
    if (FAILED(hr))
        return hr;
    if (!(attrs & SFGAO_FILESYSTEM) || (attrs & SFGAO_FOLDER))
        return E_NOINTERFACE;

    hr = IShellItem2_GetDisplayName(&item->IShellItem2_iface, SIGDN_FILESYSPATH, &path);
    if (FAILED(hr))
        return hr;

    hr = SHCreateStreamOnFileW(path, STGM_READ | STGM_SHARE_DENY_NONE, &stream);
    CoTaskMemFree(path);
    if (FAILED(hr))
        return hr;

    hr = IStream_QueryInterface(stream, riid, ppv);
    IStream_Release(stream);
    return hr;
}

static HRESULT WINAPI empty_property_description_list_QueryInterface(IPropertyDescriptionList *iface, REFIID riid, void **ppv)
{
    struct empty_property_description_list *list = impl_from_empty_IPropertyDescriptionList(iface);

    TRACE("(%p, %s, %p)\n", list, debugstr_guid(riid), ppv);

    if (!ppv) return E_POINTER;

    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IPropertyDescriptionList))
        *ppv = &list->IPropertyDescriptionList_iface;
    else
    {
        *ppv = NULL;
        return E_NOINTERFACE;
    }

    IUnknown_AddRef((IUnknown *)*ppv);
    return S_OK;
}

static ULONG WINAPI empty_property_description_list_AddRef(IPropertyDescriptionList *iface)
{
    struct empty_property_description_list *list = impl_from_empty_IPropertyDescriptionList(iface);
    return InterlockedIncrement(&list->ref);
}

static ULONG WINAPI empty_property_description_list_Release(IPropertyDescriptionList *iface)
{
    struct empty_property_description_list *list = impl_from_empty_IPropertyDescriptionList(iface);
    LONG ref = InterlockedDecrement(&list->ref);

    if (!ref)
        free(list);

    return ref;
}

static HRESULT WINAPI empty_property_description_list_GetCount(IPropertyDescriptionList *iface, UINT *count)
{
    TRACE("(%p, %p)\n", iface, count);

    if (!count) return E_POINTER;
    *count = 0;
    return S_OK;
}

static HRESULT WINAPI empty_property_description_list_GetAt(IPropertyDescriptionList *iface, UINT index, REFIID riid, void **ppv)
{
    TRACE("(%p, %u, %s, %p)\n", iface, index, debugstr_guid(riid), ppv);

    if (!ppv) return E_POINTER;
    *ppv = NULL;
    return E_INVALIDARG;
}

static const IPropertyDescriptionListVtbl empty_property_description_list_vtbl =
{
    empty_property_description_list_QueryInterface,
    empty_property_description_list_AddRef,
    empty_property_description_list_Release,
    empty_property_description_list_GetCount,
    empty_property_description_list_GetAt,
};

static HRESULT create_empty_property_description_list(REFIID riid, void **ppv)
{
    struct empty_property_description_list *list;
    HRESULT hr;

    if (!ppv) return E_POINTER;
    *ppv = NULL;

    list = calloc(1, sizeof(*list));
    if (!list)
        return E_OUTOFMEMORY;

    list->IPropertyDescriptionList_iface.lpVtbl = &empty_property_description_list_vtbl;
    list->ref = 1;

    hr = IPropertyDescriptionList_QueryInterface(&list->IPropertyDescriptionList_iface, riid, ppv);
    IPropertyDescriptionList_Release(&list->IPropertyDescriptionList_iface);

    return hr;
}

static HRESULT shellitem_get_association_name(IShellItem2 *iface, LPWSTR *name, LPCWSTR *assoc_name)
{
    WCHAR *ext;
    SFGAOF attrs = SFGAO_FOLDER;
    HRESULT hr;

    *name = NULL;
    *assoc_name = L"*";

    hr = IShellItem2_GetAttributes(iface, SFGAO_FOLDER, &attrs);
    if (FAILED(hr))
        return hr;

    if (attrs & SFGAO_FOLDER)
        *assoc_name = L"Folder";
    else
    {
        hr = IShellItem2_GetDisplayName(iface, SIGDN_FILESYSPATH, name);
        if (FAILED(hr))
            hr = IShellItem2_GetDisplayName(iface, SIGDN_DESKTOPABSOLUTEPARSING, name);
        if (FAILED(hr))
            return hr;

        ext = PathFindExtensionW(*name);
        if (ext && *ext)
            *assoc_name = ext;
    }

    return S_OK;
}

static HRESULT shellitem_create_association_object(IShellItem2 *iface, REFIID riid, void **ppv)
{
    IQueryAssociations *assoc;
    LPWSTR name;
    LPCWSTR assoc_name;
    HRESULT hr;

    if (!ppv) return E_POINTER;
    *ppv = NULL;

    hr = shellitem_get_association_name(iface, &name, &assoc_name);
    if (FAILED(hr))
        return hr;

    hr = QueryAssociations_Constructor(NULL, &IID_IQueryAssociations, (void **)&assoc);
    if (SUCCEEDED(hr))
    {
        hr = IQueryAssociations_Init(assoc, 0, assoc_name, NULL, NULL);
        if (SUCCEEDED(hr))
            hr = IQueryAssociations_QueryInterface(assoc, riid, ppv);
        IQueryAssociations_Release(assoc);
    }

    CoTaskMemFree(name);
    return hr;
}

static HRESULT shellitem_enum_association_handlers(IShellItem2 *iface, REFIID riid, void **ppv)
{
    IEnumAssocHandlers *handlers;
    LPWSTR name;
    LPCWSTR assoc_name;
    HRESULT hr;

    if (!ppv) return E_POINTER;
    *ppv = NULL;

    hr = shellitem_get_association_name(iface, &name, &assoc_name);
    if (FAILED(hr))
        return hr;

    hr = SHAssocEnumHandlers(assoc_name, ASSOC_FILTER_RECOMMENDED, &handlers);
    if (SUCCEEDED(hr))
    {
        hr = IEnumAssocHandlers_QueryInterface(handlers, riid, ppv);
        IEnumAssocHandlers_Release(handlers);
    }

    CoTaskMemFree(name);
    return hr;
}

static HRESULT shellitem_get_link_target(struct shell_item *item, REFIID riid, void **ppv)
{
    IShellLinkW *link;
    WCHAR path[MAX_PATH];
    HRESULT hr;

    if (!ppv) return E_POINTER;
    *ppv = NULL;

    hr = IShellLink_ConstructFromFile(NULL, &IID_IShellLinkW, item->pidl, (IUnknown **)&link);
    if (FAILED(hr))
        return hr;

    hr = IShellLinkW_GetPath(link, path, ARRAY_SIZE(path), NULL, SLGP_RAWPATH);
    if (hr == S_OK && path[0])
        hr = SHCreateItemFromParsingName(path, NULL, riid, ppv);
    else
        hr = E_NOINTERFACE;

    IShellLinkW_Release(link);
    return hr;
}

static HRESULT shellitem_get_filesystem_path(IShellItem2 *iface, LPWSTR *path)
{
    HRESULT hr;

    *path = NULL;

    hr = IShellItem2_GetDisplayName(iface, SIGDN_FILESYSPATH, path);
    if (FAILED(hr))
        hr = IShellItem2_GetDisplayName(iface, SIGDN_DESKTOPABSOLUTEPARSING, path);

    return hr;
}

static HRESULT shellitem_get_file_attributes(IShellItem2 *iface, WIN32_FILE_ATTRIBUTE_DATA *data)
{
    LPWSTR path;
    HRESULT hr;

    hr = shellitem_get_filesystem_path(iface, &path);
    if (FAILED(hr))
        return hr;

    if (!GetFileAttributesExW(path, GetFileExInfoStandard, data))
        hr = HRESULT_FROM_WIN32(GetLastError());
    else
        hr = S_OK;

    CoTaskMemFree(path);
    return hr;
}

static HRESULT shellitem_get_child_count(struct shell_item *item, DWORD *count)
{
    IShellFolder *folder = NULL;
    IEnumIDList *enum_list = NULL;
    LPITEMIDLIST child;
    ULONG fetched;
    DWORD total = 0;
    HRESULT hr;

    if (!count) return E_POINTER;
    *count = 0;

    hr = ShellItem_get_shellfolder(item, NULL, &folder);
    if (FAILED(hr))
        return hr;

    hr = IShellFolder_EnumObjects(folder, NULL, SHCONTF_FOLDERS | SHCONTF_NONFOLDERS, &enum_list);
    if (FAILED(hr))
    {
        IShellFolder_Release(folder);
        return hr;
    }

    while ((hr = IEnumIDList_Next(enum_list, 1, &child, &fetched)) == S_OK && fetched)
    {
        total++;
        ILFree(child);
    }

    IEnumIDList_Release(enum_list);
    IShellFolder_Release(folder);

    if (hr == S_FALSE)
        hr = S_OK;
    if (SUCCEEDED(hr))
        *count = total;
    return hr;
}

static HRESULT shellitem_create_sfgao_flag_strings(SFGAOF attrs, PROPVARIANT *ppropvar)
{
    PCWSTR strings[10];
    ULONG count = 0;

    if (attrs & SFGAO_FOLDER) strings[count++] = L"Folder";
    if (attrs & SFGAO_FILESYSTEM) strings[count++] = L"FileSystem";
    if (attrs & SFGAO_LINK) strings[count++] = L"Link";
    if (attrs & SFGAO_STREAM) strings[count++] = L"Stream";
    if (attrs & SFGAO_HIDDEN) strings[count++] = L"Hidden";
    if (attrs & SFGAO_READONLY) strings[count++] = L"ReadOnly";
    if (attrs & SFGAO_BROWSABLE) strings[count++] = L"Browsable";
    if (attrs & SFGAO_CANCOPY) strings[count++] = L"CanCopy";
    if (attrs & SFGAO_CANMOVE) strings[count++] = L"CanMove";
    if (attrs & SFGAO_CANDELETE) strings[count++] = L"CanDelete";

    if (!count)
        return S_FALSE;

    return InitPropVariantFromStringVector(strings, count, ppropvar);
}

static HRESULT shellitem_get_perceived_type(IShellItem2 *iface, PERCEIVED *type)
{
    WCHAR *path, *ext;
    SFGAOF attrs = SFGAO_FOLDER;
    HRESULT hr;

    if (!type) return E_POINTER;
    *type = PERCEIVED_TYPE_UNKNOWN;

    hr = IShellItem2_GetAttributes(iface, SFGAO_FOLDER, &attrs);
    if (FAILED(hr))
        return hr;
    if (attrs & SFGAO_FOLDER)
    {
        *type = PERCEIVED_TYPE_FOLDER;
        return S_OK;
    }

    hr = shellitem_get_filesystem_path(iface, &path);
    if (FAILED(hr))
        return hr;

    ext = PathFindExtensionW(path);
    if (!ext || !*ext)
    {
        CoTaskMemFree(path);
        return S_FALSE;
    }

    if (!lstrcmpiW(ext, L".txt") || !lstrcmpiW(ext, L".log") || !lstrcmpiW(ext, L".ini") ||
        !lstrcmpiW(ext, L".cfg") || !lstrcmpiW(ext, L".csv") || !lstrcmpiW(ext, L".json") ||
        !lstrcmpiW(ext, L".xml") || !lstrcmpiW(ext, L".yml") || !lstrcmpiW(ext, L".yaml") ||
        !lstrcmpiW(ext, L".md"))
        *type = PERCEIVED_TYPE_TEXT;
    else if (!lstrcmpiW(ext, L".pdf") || !lstrcmpiW(ext, L".doc") || !lstrcmpiW(ext, L".docx") ||
             !lstrcmpiW(ext, L".rtf") || !lstrcmpiW(ext, L".odt"))
        *type = PERCEIVED_TYPE_DOCUMENT;
    else if (!lstrcmpiW(ext, L".png") || !lstrcmpiW(ext, L".jpg") || !lstrcmpiW(ext, L".jpeg") ||
             !lstrcmpiW(ext, L".bmp") || !lstrcmpiW(ext, L".gif") || !lstrcmpiW(ext, L".tif") ||
             !lstrcmpiW(ext, L".tiff") || !lstrcmpiW(ext, L".webp") || !lstrcmpiW(ext, L".ico"))
        *type = PERCEIVED_TYPE_IMAGE;
    else if (!lstrcmpiW(ext, L".mp3") || !lstrcmpiW(ext, L".wav") || !lstrcmpiW(ext, L".flac") ||
             !lstrcmpiW(ext, L".ogg") || !lstrcmpiW(ext, L".m4a") || !lstrcmpiW(ext, L".aac"))
        *type = PERCEIVED_TYPE_AUDIO;
    else if (!lstrcmpiW(ext, L".mp4") || !lstrcmpiW(ext, L".mkv") || !lstrcmpiW(ext, L".avi") ||
             !lstrcmpiW(ext, L".mov") || !lstrcmpiW(ext, L".wmv") || !lstrcmpiW(ext, L".webm"))
        *type = PERCEIVED_TYPE_VIDEO;
    else if (!lstrcmpiW(ext, L".zip") || !lstrcmpiW(ext, L".7z") || !lstrcmpiW(ext, L".rar") ||
             !lstrcmpiW(ext, L".gz") || !lstrcmpiW(ext, L".tar") || !lstrcmpiW(ext, L".bz2") ||
             !lstrcmpiW(ext, L".xz"))
        *type = PERCEIVED_TYPE_COMPRESSED;
    else if (!lstrcmpiW(ext, L".exe") || !lstrcmpiW(ext, L".msi") || !lstrcmpiW(ext, L".bat") ||
             !lstrcmpiW(ext, L".cmd") || !lstrcmpiW(ext, L".com"))
        *type = PERCEIVED_TYPE_APPLICATION;
    else if (!lstrcmpiW(ext, L".dll") || !lstrcmpiW(ext, L".sys") || !lstrcmpiW(ext, L".drv"))
        *type = PERCEIVED_TYPE_SYSTEM;
    else
        *type = PERCEIVED_TYPE_UNKNOWN;

    CoTaskMemFree(path);
    return S_OK;
}

static HRESULT shellitem_get_link_target_path(struct shell_item *item, LPWSTR *path)
{
    IShellLinkW *link;
    WCHAR buffer[MAX_PATH];
    HRESULT hr;

    if (!path) return E_POINTER;
    *path = NULL;

    hr = IShellLink_ConstructFromFile(NULL, &IID_IShellLinkW, item->pidl, (IUnknown **)&link);
    if (FAILED(hr))
        return hr;

    hr = IShellLinkW_GetPath(link, buffer, ARRAY_SIZE(buffer), NULL, SLGP_RAWPATH);
    if (hr == S_OK && buffer[0])
    {
        *path = CoTaskMemAlloc((lstrlenW(buffer) + 1) * sizeof(WCHAR));
        if (*path)
            lstrcpyW(*path, buffer);
        else
            hr = E_OUTOFMEMORY;
    }
    else
        hr = S_FALSE;

    IShellLinkW_Release(link);
    return hr;
}

static HRESULT shellitem_get_link_string(struct shell_item *item, REFPROPERTYKEY key, LPWSTR *value)
{
    IShellLinkW *link;
    WCHAR buffer[SHELLITEM_URL_LENGTH];
    HRESULT hr;

    if (!value) return E_POINTER;
    *value = NULL;

    hr = IShellLink_ConstructFromFile(NULL, &IID_IShellLinkW, item->pidl, (IUnknown **)&link);
    if (FAILED(hr))
        return hr;

    if (IsEqualPropertyKey(*key, PKEY_Link_Description) || IsEqualPropertyKey(*key, PKEY_Link_Comment))
        hr = IShellLinkW_GetDescription(link, buffer, ARRAY_SIZE(buffer));
    else if (IsEqualPropertyKey(*key, PKEY_Link_Arguments))
        hr = IShellLinkW_GetArguments(link, buffer, ARRAY_SIZE(buffer));
    else
        hr = E_INVALIDARG;

    if (SUCCEEDED(hr) && buffer[0])
    {
        *value = CoTaskMemAlloc((lstrlenW(buffer) + 1) * sizeof(WCHAR));
        if (*value)
            lstrcpyW(*value, buffer);
        else
            hr = E_OUTOFMEMORY;
    }
    else if (SUCCEEDED(hr))
        hr = S_FALSE;

    IShellLinkW_Release(link);
    return hr;
}

static HRESULT shellitem_get_link_target_url_part(struct shell_item *item, DWORD part, LPWSTR *value)
{
    WCHAR *target_path = NULL, *url = NULL;
    DWORD len;
    HRESULT hr;

    if (!value) return E_POINTER;
    *value = NULL;

    hr = shellitem_get_link_target_path(item, &target_path);
    if (FAILED(hr))
        return hr;

    len = SHELLITEM_URL_LENGTH;
    url = CoTaskMemAlloc(len * sizeof(WCHAR));
    if (!url)
    {
        CoTaskMemFree(target_path);
        return E_OUTOFMEMORY;
    }

    hr = UrlCreateFromPathW(target_path, url, &len, 0);
    if (SUCCEEDED(hr))
    {
        DWORD part_len = SHELLITEM_URL_LENGTH;

        *value = CoTaskMemAlloc(part_len * sizeof(WCHAR));
        if (!*value)
            hr = E_OUTOFMEMORY;
        else
        {
            hr = UrlGetPartW(url, *value, &part_len, part, 0);
            if (FAILED(hr))
            {
                CoTaskMemFree(*value);
                *value = NULL;
            }
        }
    }

    CoTaskMemFree(url);
    CoTaskMemFree(target_path);
    return hr;
}

static HRESULT shellitem_get_link_target_url_path(struct shell_item *item, LPWSTR *value)
{
    WCHAR *target_path = NULL, *url = NULL, *path_start;
    DWORD len = SHELLITEM_URL_LENGTH;
    HRESULT hr;

    if (!value) return E_POINTER;
    *value = NULL;

    hr = shellitem_get_link_target_path(item, &target_path);
    if (FAILED(hr))
        return hr;

    url = CoTaskMemAlloc(len * sizeof(WCHAR));
    if (!url)
    {
        CoTaskMemFree(target_path);
        return E_OUTOFMEMORY;
    }

    hr = UrlCreateFromPathW(target_path, url, &len, 0);
    if (SUCCEEDED(hr))
    {
        path_start = wcschr(url, ':');
        while (path_start && path_start[0] == ':' && path_start[1] == '/')
            path_start++;
        while (path_start && path_start[0] == '/')
            path_start++;

        if (path_start && *path_start)
        {
            *value = CoTaskMemAlloc((lstrlenW(path_start) + 1) * sizeof(WCHAR));
            if (*value)
                lstrcpyW(*value, path_start);
            else
                hr = E_OUTOFMEMORY;
        }
        else
            hr = S_FALSE;
    }

    CoTaskMemFree(url);
    CoTaskMemFree(target_path);
    return hr;
}

static HRESULT shellitem_get_link_target_attributes(struct shell_item *item, SFGAOF *attrs)
{
    IShellItem *target;
    HRESULT hr;

    if (!attrs) return E_POINTER;
    *attrs = 0;

    hr = shellitem_get_link_target(item, &IID_IShellItem, (void **)&target);
    if (FAILED(hr))
        return hr;

    hr = IShellItem_GetAttributes(target, SFGAO_CAPABILITYMASK | SFGAO_DISPLAYATTRMASK |
                                          SFGAO_STORAGEGAPMASK | SFGAO_CONTENTSMASK,
                                  attrs);
    IShellItem_Release(target);
    return hr;
}

static HRESULT shellitem_get_link_target_file_attributes(struct shell_item *item, WIN32_FILE_ATTRIBUTE_DATA *data)
{
    WCHAR *path;
    HRESULT hr;

    if (!data) return E_POINTER;

    hr = shellitem_get_link_target_path(item, &path);
    if (FAILED(hr))
        return hr;

    if (!GetFileAttributesExW(path, GetFileExInfoStandard, data))
        hr = HRESULT_FROM_WIN32(GetLastError());
    else
        hr = S_OK;

    CoTaskMemFree(path);
    return hr;
}

static HRESULT shellitem_copy_extension(const WCHAR *path, LPWSTR *value)
{
    const WCHAR *ext;
    WCHAR *ret;

    if (!value) return E_POINTER;
    *value = NULL;
    if (!path) return E_INVALIDARG;

    ext = PathFindExtensionW(path);
    if (!ext || !*ext)
        return S_FALSE;

    ret = CoTaskMemAlloc((lstrlenW(ext) + 1) * sizeof(WCHAR));
    if (!ret)
        return E_OUTOFMEMORY;

    lstrcpyW(ret, ext);
    *value = ret;
    return S_OK;
}

static HRESULT shellitem_get_string_property(IShellItem2 *iface, REFPROPERTYKEY key, LPWSTR *value)
{
    struct shell_item *item = impl_from_IShellItem2(iface);
    WCHAR *ret = NULL;
    HRESULT hr;

    *value = NULL;

    if (IsEqualPropertyKey(*key, PKEY_ItemNameDisplay))
        hr = IShellItem2_GetDisplayName(iface, SIGDN_NORMALDISPLAY, &ret);
    else if (IsEqualPropertyKey(*key, PKEY_FileName))
        hr = IShellItem2_GetDisplayName(iface, SIGDN_PARENTRELATIVEPARSING, &ret);
    else if (IsEqualPropertyKey(*key, PKEY_ParsingPath))
        hr = shellitem_get_filesystem_path(iface, &ret);
    else if (IsEqualPropertyKey(*key, PKEY_ParsingName))
        hr = IShellItem2_GetDisplayName(iface, SIGDN_DESKTOPABSOLUTEPARSING, &ret);
    else if (IsEqualPropertyKey(*key, PKEY_ItemPathDisplay))
        hr = shellitem_get_filesystem_path(iface, &ret);
    else if (IsEqualPropertyKey(*key, PKEY_ItemFolderPathDisplay))
    {
        IShellItem *parent;

        hr = IShellItem2_GetParent(iface, &parent);
        if (SUCCEEDED(hr))
        {
            hr = IShellItem_GetDisplayName(parent, SIGDN_FILESYSPATH, &ret);
            if (FAILED(hr))
                hr = IShellItem_GetDisplayName(parent, SIGDN_DESKTOPABSOLUTEPARSING, &ret);
            IShellItem_Release(parent);
        }
    }
    else if (IsEqualPropertyKey(*key, PKEY_ItemFolderPathDisplayNarrow))
    {
        IShellItem *parent;

        hr = IShellItem2_GetParent(iface, &parent);
        if (SUCCEEDED(hr))
        {
            hr = IShellItem_GetDisplayName(parent, SIGDN_FILESYSPATH, &ret);
            if (FAILED(hr))
                hr = IShellItem_GetDisplayName(parent, SIGDN_DESKTOPABSOLUTEPARSING, &ret);
            IShellItem_Release(parent);
        }
    }
    else if (IsEqualPropertyKey(*key, PKEY_ItemFolderNameDisplay))
    {
        IShellItem *parent;

        hr = IShellItem2_GetParent(iface, &parent);
        if (SUCCEEDED(hr))
        {
            hr = IShellItem_GetDisplayName(parent, SIGDN_NORMALDISPLAY, &ret);
            IShellItem_Release(parent);
        }
    }
    else if (IsEqualPropertyKey(*key, PKEY_FolderNameDisplay))
    {
        hr = IShellItem2_GetDisplayName(iface, SIGDN_NORMALDISPLAY, &ret);
    }
    else if (IsEqualPropertyKey(*key, PKEY_ItemNameDisplayWithoutExtension))
    {
        hr = IShellItem2_GetDisplayName(iface, SIGDN_NORMALDISPLAY, &ret);
        if (SUCCEEDED(hr) && ret)
            PathRemoveExtensionW(ret);
    }
    else if (IsEqualPropertyKey(*key, PKEY_ItemTypeText))
    {
        SFGAOF attrs = SFGAO_FOLDER;

        hr = IShellItem2_GetAttributes(iface, SFGAO_FOLDER, &attrs);
        if (FAILED(hr))
            return hr;

        if (attrs & SFGAO_FOLDER)
        {
            static const WCHAR folderW[] = L"File folder";

            ret = CoTaskMemAlloc(sizeof(folderW));
            if (!ret)
                return E_OUTOFMEMORY;
            memcpy(ret, folderW, sizeof(folderW));
            hr = S_OK;
        }
        else
        {
            WCHAR *path, *ext;

            hr = shellitem_get_filesystem_path(iface, &path);
            if (FAILED(hr))
                return hr;

            ext = PathFindExtensionW(path);
            if (ext && *ext)
            {
                ret = CoTaskMemAlloc((lstrlenW(ext) + 1) * sizeof(WCHAR));
                if (ret)
                {
                    lstrcpyW(ret, ext);
                    hr = S_OK;
                }
                else hr = E_OUTOFMEMORY;
            }
            else hr = S_FALSE;

            CoTaskMemFree(path);
        }
    }
    else if (IsEqualPropertyKey(*key, PKEY_KindText))
    {
        SFGAOF attrs = SFGAO_FOLDER;

        hr = IShellItem2_GetAttributes(iface, SFGAO_FOLDER, &attrs);
        if (FAILED(hr))
            return hr;

        if (attrs & SFGAO_FOLDER)
        {
            static const WCHAR folderW[] = L"Folder";

            ret = CoTaskMemAlloc(sizeof(folderW));
            if (!ret)
                return E_OUTOFMEMORY;
            memcpy(ret, folderW, sizeof(folderW));
            hr = S_OK;
        }
        else
        {
            static const WCHAR fileW[] = L"File";

            ret = CoTaskMemAlloc(sizeof(fileW));
            if (!ret)
                return E_OUTOFMEMORY;
            memcpy(ret, fileW, sizeof(fileW));
            hr = S_OK;
        }
    }
    else if (IsEqualPropertyKey(*key, PKEY_ItemType))
    {
        WCHAR *path, *ext;

        hr = shellitem_get_filesystem_path(iface, &path);
        if (FAILED(hr))
            return hr;

        ext = PathFindExtensionW(path);
        if (ext && *ext)
        {
            ret = CoTaskMemAlloc((lstrlenW(ext) + 1) * sizeof(WCHAR));
            if (ret)
            {
                lstrcpyW(ret, ext);
                hr = S_OK;
            }
            else hr = E_OUTOFMEMORY;
        }
        else hr = S_FALSE;

        CoTaskMemFree(path);
    }
    else if (IsEqualPropertyKey(*key, PKEY_ItemSubType))
    {
        WCHAR *path;

        hr = shellitem_get_filesystem_path(iface, &path);
        if (FAILED(hr))
            return hr;

        hr = shellitem_copy_extension(path, &ret);
        CoTaskMemFree(path);
    }
    else if (IsEqualPropertyKey(*key, PKEY_FileExtension))
    {
        WCHAR *path;

        hr = shellitem_get_filesystem_path(iface, &path);
        if (FAILED(hr))
            return hr;

        hr = shellitem_copy_extension(path, &ret);
        CoTaskMemFree(path);
    }
    else if (IsEqualPropertyKey(*key, PKEY_ItemName))
    {
        hr = IShellItem2_GetDisplayName(iface, SIGDN_PARENTRELATIVEPARSING, &ret);
    }
    else if (IsEqualPropertyKey(*key, PKEY_ItemPathDisplayNarrow))
    {
        hr = shellitem_get_filesystem_path(iface, &ret);
    }
    else if (IsEqualPropertyKey(*key, PKEY_Link_TargetParsingPath))
    {
        hr = shellitem_get_link_target_path(item, &ret);
    }
    else if (IsEqualPropertyKey(*key, PKEY_Link_Description) ||
             IsEqualPropertyKey(*key, PKEY_Link_Comment) ||
             IsEqualPropertyKey(*key, PKEY_Link_Arguments))
    {
        hr = shellitem_get_link_string(item, key, &ret);
    }
    else if (IsEqualPropertyKey(*key, PKEY_Link_TargetExtension))
    {
        WCHAR *path;

        hr = shellitem_get_link_target_path(item, &path);
        if (FAILED(hr))
            return hr;

        hr = shellitem_copy_extension(path, &ret);
        CoTaskMemFree(path);
    }
    else if (IsEqualPropertyKey(*key, PKEY_ItemUrl))
    {
        hr = IShellItem2_GetDisplayName(iface, SIGDN_URL, &ret);
    }
    else if (IsEqualPropertyKey(*key, PKEY_Link_TargetUrl))
    {
        WCHAR *path;
        DWORD len = SHELLITEM_URL_LENGTH;

        hr = shellitem_get_link_target_path(item, &path);
        if (FAILED(hr))
            return hr;

        ret = CoTaskMemAlloc(len * sizeof(WCHAR));
        if (ret)
            hr = UrlCreateFromPathW(path, ret, &len, 0);
        else
            hr = E_OUTOFMEMORY;

        CoTaskMemFree(path);
    }
    else if (IsEqualPropertyKey(*key, PKEY_Link_TargetUrlHostName))
    {
        hr = shellitem_get_link_target_url_part(item, URL_PART_HOSTNAME, &ret);
    }
    else if (IsEqualPropertyKey(*key, PKEY_Link_TargetUrlPath))
    {
        hr = shellitem_get_link_target_url_path(item, &ret);
    }
    else if (IsEqualPropertyKey(*key, PKEY_Link_Status))
    {
        WCHAR *path;
        static const WCHAR okW[] = L"OK";
        static const WCHAR brokenW[] = L"Broken";

        hr = shellitem_get_link_target_path(item, &path);
        if (FAILED(hr))
            return hr;

        ret = CoTaskMemAlloc(sizeof(okW));
        if (!ret)
        {
            CoTaskMemFree(path);
            return E_OUTOFMEMORY;
        }

        if (GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES)
            memcpy(ret, okW, sizeof(okW));
        else
            memcpy(ret, brokenW, sizeof(brokenW));

        CoTaskMemFree(path);
        hr = S_OK;
    }
    else if (IsEqualPropertyKey(*key, PKEY_Status))
    {
        if (SUCCEEDED(shellitem_get_link_target_path(item, &ret)))
        {
            WCHAR *path;
            static const WCHAR okW[] = L"OK";
            static const WCHAR brokenW[] = L"Broken";

            path = ret;
            ret = CoTaskMemAlloc(sizeof(okW));
            if (!ret)
            {
                CoTaskMemFree(path);
                return E_OUTOFMEMORY;
            }

            if (GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES)
                memcpy(ret, okW, sizeof(okW));
            else
                memcpy(ret, brokenW, sizeof(brokenW));

            CoTaskMemFree(path);
            hr = S_OK;
        }
        else
            hr = S_FALSE;
    }
    else
        return S_FALSE;

    if (SUCCEEDED(hr))
        *value = ret;
    else
        CoTaskMemFree(ret);
    return hr;
}

static HRESULT WINAPI ShellItem_BindToHandler(IShellItem2 *iface, IBindCtx *pbc,
    REFGUID rbhid, REFIID riid, void **ppvOut)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    HRESULT ret;
    TRACE("(%p,%p,%s,%p,%p)\n", iface, pbc, shdebugstr_guid(rbhid), riid, ppvOut);

    *ppvOut = NULL;
    if (IsEqualGUID(rbhid, &BHID_SFObject))
    {
        IShellFolder *psf;
        ret = ShellItem_get_shellfolder(This, pbc, &psf);
        if (SUCCEEDED(ret))
        {
            ret = IShellFolder_QueryInterface(psf, riid, ppvOut);
            IShellFolder_Release(psf);
        }
        return ret;
    }
    else if (IsEqualGUID(rbhid, &BHID_SFUIObject))
    {
        IShellFolder *psf_parent;
        if (_ILIsDesktop(This->pidl))
            ret = SHGetDesktopFolder(&psf_parent);
        else
            ret = ShellItem_get_parent_shellfolder(This, &psf_parent);

        if (SUCCEEDED(ret))
        {
            LPCITEMIDLIST pidl = ILFindLastID(This->pidl);
            ret = IShellFolder_GetUIObjectOf(psf_parent, NULL, 1, &pidl, riid, NULL, ppvOut);
            IShellFolder_Release(psf_parent);
        }
        return ret;
    }
    else if (IsEqualGUID(rbhid, &BHID_DataObject))
    {
        return ShellItem_BindToHandler(&This->IShellItem2_iface, pbc, &BHID_SFUIObject,
                                       &IID_IDataObject, ppvOut);
    }
    else if (IsEqualGUID(rbhid, &BHID_SFViewObject))
    {
        return shellitem_get_view_object(This, pbc, riid, ppvOut);
    }
    else if (IsEqualGUID(rbhid, &BHID_PropertyStore))
    {
        return create_empty_property_store(riid, ppvOut);
    }
    else if (IsEqualGUID(rbhid, &BHID_Stream) || IsEqualGUID(rbhid, &BHID_Storage))
    {
        return shellitem_get_filesystem_stream(This, riid, ppvOut);
    }
    else if (IsEqualGUID(rbhid, &BHID_EnumItems) || IsEqualGUID(rbhid, &BHID_StorageEnum))
    {
        SFGAOF attrs = SFGAO_FOLDER;

        ret = IShellItem2_GetAttributes(iface, SFGAO_FOLDER, &attrs);
        if (FAILED(ret))
            return ret;
        if (!(attrs & SFGAO_FOLDER))
            return MK_E_NOOBJECT;

        return shellitem_enum_children(This, pbc, riid, ppvOut);
    }
    else if (IsEqualGUID(rbhid, &BHID_AssociationArray) || IsEqualGUID(rbhid, &BHID_Filter))
    {
        return shellitem_create_association_object(iface, riid, ppvOut);
    }
    else if (IsEqualGUID(rbhid, &BHID_ThumbnailHandler))
    {
        return IShellItemImageFactory_QueryInterface(&This->IShellItemImageFactory_iface, riid, ppvOut);
    }
    else if (IsEqualGUID(rbhid, &BHID_Transfer))
    {
        if (IsEqualIID(riid, &IID_ITransferSource) || IsEqualIID(riid, &IID_ITransferDestination))
            return create_transfer_placeholder(riid, ppvOut);
        return create_bind_unknown_placeholder(riid, ppvOut);
    }
    else if (IsEqualGUID(rbhid, &BHID_EnumAssocHandlers))
    {
        return shellitem_enum_association_handlers(iface, riid, ppvOut);
    }
    else if (IsEqualGUID(rbhid, &BHID_LinkTargetItem))
    {
        return shellitem_get_link_target(This, riid, ppvOut);
    }

    TRACE("Unsupported BHID %s.\n", debugstr_guid(rbhid));
    return MK_E_NOOBJECT;
}

static HRESULT WINAPI ShellItem_GetParent(IShellItem2 *iface, IShellItem **ppsi)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    LPITEMIDLIST parent_pidl;
    HRESULT ret;

    TRACE("(%p,%p)\n", iface, ppsi);

    ret = ShellItem_get_parent_pidl(This, &parent_pidl);
    if (SUCCEEDED(ret))
    {
        ret = SHCreateShellItem(NULL, NULL, parent_pidl, ppsi);
        ILFree(parent_pidl);
    }

    return ret;
}

static HRESULT WINAPI ShellItem_GetDisplayName(IShellItem2 *iface, SIGDN sigdnName,
    LPWSTR *ppszName)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    TRACE("(%p,%x,%p)\n", iface, sigdnName, ppszName);

    return SHGetNameFromIDList(This->pidl, sigdnName, ppszName);
}

static HRESULT WINAPI ShellItem_GetAttributes(IShellItem2 *iface, SFGAOF sfgaoMask,
    SFGAOF *psfgaoAttribs)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    IShellFolder *parent_folder;
    LPITEMIDLIST child_pidl;
    HRESULT ret;

    TRACE("(%p,%lx,%p)\n", iface, sfgaoMask, psfgaoAttribs);

    if (_ILIsDesktop(This->pidl))
        ret = SHGetDesktopFolder(&parent_folder);
    else
        ret = ShellItem_get_parent_shellfolder(This, &parent_folder);
    if (SUCCEEDED(ret))
    {
        child_pidl = ILFindLastID(This->pidl);
        *psfgaoAttribs = sfgaoMask;
        ret = IShellFolder_GetAttributesOf(parent_folder, 1, (LPCITEMIDLIST*)&child_pidl, psfgaoAttribs);
        *psfgaoAttribs &= sfgaoMask;
        IShellFolder_Release(parent_folder);

        if (SUCCEEDED(ret))
        {
            if(sfgaoMask == *psfgaoAttribs)
                return S_OK;
            else
                return S_FALSE;
        }
    }

    return ret;
}

static HRESULT WINAPI ShellItem_Compare(IShellItem2 *iface, IShellItem *oth,
    SICHINTF hint, int *piOrder)
{
    LPWSTR dispname, dispname_oth;
    HRESULT ret;
    TRACE("(%p,%p,%lx,%p)\n", iface, oth, hint, piOrder);

    if(hint & (SICHINT_CANONICAL | SICHINT_ALLFIELDS))
        TRACE("Unsupported flags 0x%08lx\n", hint);

    ret = IShellItem2_GetDisplayName(iface, SIGDN_DESKTOPABSOLUTEEDITING, &dispname);
    if(SUCCEEDED(ret))
    {
        ret = IShellItem_GetDisplayName(oth, SIGDN_DESKTOPABSOLUTEEDITING, &dispname_oth);
        if(SUCCEEDED(ret))
        {
            *piOrder = lstrcmpiW(dispname, dispname_oth);
            CoTaskMemFree(dispname_oth);
        }
        CoTaskMemFree(dispname);
    }

    if(SUCCEEDED(ret) && *piOrder &&
       (hint & SICHINT_TEST_FILESYSPATH_IF_NOT_EQUAL))
    {
        LPWSTR dispname, dispname_oth;

        TRACE("Testing filesystem path.\n");
        ret = IShellItem2_GetDisplayName(iface, SIGDN_FILESYSPATH, &dispname);
        if(SUCCEEDED(ret))
        {
            ret = IShellItem_GetDisplayName(oth, SIGDN_FILESYSPATH, &dispname_oth);
            if(SUCCEEDED(ret))
            {
                *piOrder = lstrcmpiW(dispname, dispname_oth);
                CoTaskMemFree(dispname_oth);
            }
            CoTaskMemFree(dispname);
        }
    }

    if(FAILED(ret))
        return ret;

    if(*piOrder)
        return S_FALSE;
    else
        return S_OK;
}

static HRESULT WINAPI ShellItem2_GetPropertyStore(IShellItem2 *iface, GETPROPERTYSTOREFLAGS flags,
    REFIID riid, void **ppv)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    TRACE("%p (%d, %s, %p)\n", This, flags, shdebugstr_guid(riid), ppv);
    return create_empty_property_store(riid, ppv);
}

static HRESULT WINAPI ShellItem2_GetPropertyStoreWithCreateObject(IShellItem2 *iface,
    GETPROPERTYSTOREFLAGS flags, IUnknown *punkCreateObject, REFIID riid, void **ppv)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    TRACE("%p (%08x, %p, %s, %p)\n", This, flags, punkCreateObject, shdebugstr_guid(riid), ppv);
    return create_empty_property_store(riid, ppv);
}

static HRESULT WINAPI ShellItem2_GetPropertyStoreForKeys(IShellItem2 *iface, const PROPERTYKEY *rgKeys,
    UINT cKeys, GETPROPERTYSTOREFLAGS flags, REFIID riid, void **ppv)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    TRACE("%p (%p, %d, %08x, %s, %p)\n", This, rgKeys, cKeys, flags, shdebugstr_guid(riid), ppv);
    return create_empty_property_store(riid, ppv);
}

static HRESULT WINAPI ShellItem2_GetPropertyDescriptionList(IShellItem2 *iface,
    REFPROPERTYKEY keyType, REFIID riid, void **ppv)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    TRACE("%p (%p, %s, %p)\n", This, keyType, debugstr_guid(riid), ppv);
    return create_empty_property_description_list(riid, ppv);
}

static HRESULT WINAPI ShellItem2_Update(IShellItem2 *iface, IBindCtx *pbc)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    TRACE("%p (%p)\n", This, pbc);
    return S_OK;
}

static HRESULT WINAPI ShellItem2_GetProperty(IShellItem2 *iface, REFPROPERTYKEY key, PROPVARIANT *ppropvar)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    const IID *clsid;
    WCHAR *str;
    WIN32_FILE_ATTRIBUTE_DATA data;
    SFGAOF attrs;
    HRESULT hr;

    TRACE("%p (%p, %p)\n", This, key, ppropvar);

    if (!ppropvar) return E_POINTER;
    PropVariantInit(ppropvar);

    hr = shellitem_get_string_property(iface, key, &str);
    if (SUCCEEDED(hr))
    {
        ppropvar->vt = VT_LPWSTR;
        ppropvar->pwszVal = str;
        return S_OK;
    }
    if (hr != S_FALSE)
        return hr;

    if (IsEqualPropertyKey(*key, PKEY_NamespaceCLSID))
    {
        if (_ILIsDesktop(This->pidl))
            clsid = &CLSID_ShellDesktop;
        else
            clsid = _ILGetGUIDPointer(ILFindLastID(This->pidl));

        if (!clsid)
            return S_FALSE;

        ppropvar->vt = VT_CLSID;
        ppropvar->puuid = CoTaskMemAlloc(sizeof(*ppropvar->puuid));
        if (!ppropvar->puuid)
            return E_OUTOFMEMORY;

        *ppropvar->puuid = *clsid;
        return S_OK;
    }

    if (IsEqualPropertyKey(*key, PKEY_Size))
    {
        hr = shellitem_get_file_attributes(iface, &data);
        if (FAILED(hr))
            return hr;

        if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
            return S_FALSE;

        ppropvar->vt = VT_UI8;
        ppropvar->uhVal.QuadPart = ((ULONGLONG)data.nFileSizeHigh << 32) | data.nFileSizeLow;
        return S_OK;
    }

    if (IsEqualPropertyKey(*key, PKEY_FileAllocationSize))
    {
        hr = shellitem_get_file_attributes(iface, &data);
        if (FAILED(hr))
            return hr;

        if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
            return S_FALSE;

        ppropvar->vt = VT_UI8;
        ppropvar->uhVal.QuadPart = ((ULONGLONG)data.nFileSizeHigh << 32) | data.nFileSizeLow;
        return S_OK;
    }

    if (IsEqualPropertyKey(*key, PKEY_TotalFileSize))
    {
        hr = shellitem_get_file_attributes(iface, &data);
        if (FAILED(hr))
            return hr;

        if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
            return S_FALSE;

        ppropvar->vt = VT_UI8;
        ppropvar->uhVal.QuadPart = ((ULONGLONG)data.nFileSizeHigh << 32) | data.nFileSizeLow;
        return S_OK;
    }

    if (IsEqualPropertyKey(*key, PKEY_FileAttributes))
    {
        hr = shellitem_get_file_attributes(iface, &data);
        if (FAILED(hr))
            return hr;

        ppropvar->vt = VT_UI4;
        ppropvar->ulVal = data.dwFileAttributes;
        return S_OK;
    }

    if (IsEqualPropertyKey(*key, PKEY_SFGAOFlags))
    {
        attrs = ~0u;
        hr = IShellItem2_GetAttributes(iface, attrs, &attrs);
        if (FAILED(hr))
            return hr;

        ppropvar->vt = VT_UI4;
        ppropvar->ulVal = attrs;
        return S_OK;
    }

    if (IsEqualPropertyKey(*key, PKEY_DateModified))
    {
        hr = shellitem_get_file_attributes(iface, &data);
        if (FAILED(hr))
            return hr;

        ppropvar->vt = VT_FILETIME;
        ppropvar->filetime = data.ftLastWriteTime;
        return S_OK;
    }

    if (IsEqualPropertyKey(*key, PKEY_DateCreated))
    {
        hr = shellitem_get_file_attributes(iface, &data);
        if (FAILED(hr))
            return hr;

        ppropvar->vt = VT_FILETIME;
        ppropvar->filetime = data.ftCreationTime;
        return S_OK;
    }

    if (IsEqualPropertyKey(*key, PKEY_DateAccessed))
    {
        hr = shellitem_get_file_attributes(iface, &data);
        if (FAILED(hr))
            return hr;

        ppropvar->vt = VT_FILETIME;
        ppropvar->filetime = data.ftLastAccessTime;
        return S_OK;
    }

    if (IsEqualPropertyKey(*key, PKEY_FileCount))
    {
        DWORD count;

        hr = shellitem_get_child_count(This, &count);
        if (FAILED(hr))
            return hr;

        ppropvar->vt = VT_UI4;
        ppropvar->ulVal = count;
        return S_OK;
    }

    if (IsEqualPropertyKey(*key, PKEY_ItemDate) ||
        IsEqualPropertyKey(*key, PKEY_DateAcquired) ||
        IsEqualPropertyKey(*key, PKEY_DateArchived) ||
        IsEqualPropertyKey(*key, PKEY_DateCompleted))
    {
        hr = shellitem_get_file_attributes(iface, &data);
        if (FAILED(hr))
            return hr;

        ppropvar->vt = VT_FILETIME;
        ppropvar->filetime = data.ftLastWriteTime;
        return S_OK;
    }

    if (IsEqualPropertyKey(*key, PKEY_Link_DateVisited))
    {
        hr = shellitem_get_link_target_file_attributes(This, &data);
        if (FAILED(hr))
            return hr;

        ppropvar->vt = VT_FILETIME;
        ppropvar->filetime = data.ftLastAccessTime;
        return S_OK;
    }

    if (IsEqualPropertyKey(*key, PKEY_Link_TargetSFGAOFlags))
    {
        hr = shellitem_get_link_target_attributes(This, &attrs);
        if (FAILED(hr))
            return hr;

        ppropvar->vt = VT_UI4;
        ppropvar->ulVal = attrs;
        return S_OK;
    }

    if (IsEqualPropertyKey(*key, PKEY_Link_TargetSFGAOFlagsStrings))
    {
        hr = shellitem_get_link_target_attributes(This, &attrs);
        if (FAILED(hr))
            return hr;

        return shellitem_create_sfgao_flag_strings(attrs, ppropvar);
    }

    if (IsEqualPropertyKey(*key, PKEY_Shell_SFGAOFlagsStrings))
    {
        attrs = ~0u;
        hr = IShellItem2_GetAttributes(iface, attrs, &attrs);
        if (FAILED(hr))
            return hr;

        return shellitem_create_sfgao_flag_strings(attrs, ppropvar);
    }

    if (IsEqualPropertyKey(*key, PKEY_Kind))
    {
        PCWSTR strings[1];

        attrs = SFGAO_FOLDER;
        hr = IShellItem2_GetAttributes(iface, SFGAO_FOLDER, &attrs);
        if (FAILED(hr))
            return hr;

        strings[0] = (attrs & SFGAO_FOLDER) ? L"Folder" : L"File";
        return InitPropVariantFromStringVector(strings, 1, ppropvar);
    }

    if (IsEqualPropertyKey(*key, PKEY_PerceivedType))
    {
        PERCEIVED type;

        hr = shellitem_get_perceived_type(iface, &type);
        if (FAILED(hr))
            return hr;

        ppropvar->vt = VT_I4;
        ppropvar->lVal = type;
        return S_OK;
    }

    if (IsEqualPropertyKey(*key, PKEY_IsRead) ||
        IsEqualPropertyKey(*key, PKEY_IsEncrypted) ||
        IsEqualPropertyKey(*key, PKEY_IsFlagged) ||
        IsEqualPropertyKey(*key, PKEY_IsFlaggedComplete) ||
        IsEqualPropertyKey(*key, PKEY_IsIncomplete) ||
        IsEqualPropertyKey(*key, PKEY_IsLocationSupported) ||
        IsEqualPropertyKey(*key, PKEY_IsPinnedToNameSpaceTree) ||
        IsEqualPropertyKey(*key, PKEY_IsSearchOnlyItem) ||
        IsEqualPropertyKey(*key, PKEY_IsSendToTarget) ||
        IsEqualPropertyKey(*key, PKEY_IsShared))
    {
        hr = shellitem_get_file_attributes(iface, &data);
        if (FAILED(hr) && !IsEqualPropertyKey(*key, PKEY_IsFlagged) &&
            !IsEqualPropertyKey(*key, PKEY_IsFlaggedComplete) &&
            !IsEqualPropertyKey(*key, PKEY_IsIncomplete) &&
            !IsEqualPropertyKey(*key, PKEY_IsLocationSupported) &&
            !IsEqualPropertyKey(*key, PKEY_IsPinnedToNameSpaceTree) &&
            !IsEqualPropertyKey(*key, PKEY_IsSearchOnlyItem) &&
            !IsEqualPropertyKey(*key, PKEY_IsSendToTarget) &&
            !IsEqualPropertyKey(*key, PKEY_IsShared))
            return hr;

        ppropvar->vt = VT_BOOL;
        if (IsEqualPropertyKey(*key, PKEY_IsRead))
            ppropvar->boolVal = (data.dwFileAttributes & FILE_ATTRIBUTE_READONLY) ? VARIANT_TRUE : VARIANT_FALSE;
        else if (IsEqualPropertyKey(*key, PKEY_IsEncrypted))
            ppropvar->boolVal = (data.dwFileAttributes & FILE_ATTRIBUTE_ENCRYPTED) ? VARIANT_TRUE : VARIANT_FALSE;
        else if (IsEqualPropertyKey(*key, PKEY_IsLocationSupported))
            ppropvar->boolVal = VARIANT_TRUE;
        else
            ppropvar->boolVal = VARIANT_FALSE;
        return S_OK;
    }

    return S_FALSE;
}

static HRESULT WINAPI ShellItem2_GetCLSID(IShellItem2 *iface, REFPROPERTYKEY key, CLSID *pclsid)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    PROPVARIANT value;
    HRESULT hr;

    TRACE("%p (%p, %p)\n", This, key, pclsid);

    if (!pclsid) return E_POINTER;
    hr = IShellItem2_GetProperty(iface, key, &value);
    if (FAILED(hr) || hr == S_FALSE)
        return hr;

    hr = shellitem_propvariant_to_clsid(&value, pclsid);
    PropVariantClear(&value);
    return hr;
}

static HRESULT WINAPI ShellItem2_GetFileTime(IShellItem2 *iface, REFPROPERTYKEY key, FILETIME *pft)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    PROPVARIANT value;
    HRESULT hr;

    TRACE("%p (%p, %p)\n", This, key, pft);

    if (!pft) return E_POINTER;

    hr = IShellItem2_GetProperty(iface, key, &value);
    if (FAILED(hr) || hr == S_FALSE)
        return hr;

    hr = shellitem_propvariant_to_filetime(&value, pft);
    PropVariantClear(&value);
    return hr;
}

static HRESULT WINAPI ShellItem2_GetInt32(IShellItem2 *iface, REFPROPERTYKEY key, int *pi)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    PROPVARIANT value;
    HRESULT hr;

    TRACE("%p (%p, %p)\n", This, key, pi);

    if (!pi) return E_POINTER;

    hr = IShellItem2_GetProperty(iface, key, &value);
    if (FAILED(hr) || hr == S_FALSE)
        return hr;

    hr = shellitem_propvariant_to_int32(&value, pi);
    PropVariantClear(&value);
    return hr;
}

static HRESULT WINAPI ShellItem2_GetString(IShellItem2 *iface, REFPROPERTYKEY key, LPWSTR *ppsz)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    PROPVARIANT value;
    HRESULT hr;

    TRACE("%p (%p, %p)\n", This, key, ppsz);

    if (!ppsz) return E_POINTER;
    *ppsz = NULL;

    hr = IShellItem2_GetProperty(iface, key, &value);
    if (FAILED(hr) || hr == S_FALSE)
        return hr;

    hr = shellitem_propvariant_to_string_alloc(&value, ppsz);
    PropVariantClear(&value);
    return hr;
}

static HRESULT WINAPI ShellItem2_GetUInt32(IShellItem2 *iface, REFPROPERTYKEY key, ULONG *pui)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    PROPVARIANT value;
    HRESULT hr;

    TRACE("%p (%p, %p)\n", This, key, pui);

    if (!pui) return E_POINTER;

    hr = IShellItem2_GetProperty(iface, key, &value);
    if (FAILED(hr) || hr == S_FALSE)
        return hr;

    hr = shellitem_propvariant_to_uint32(&value, pui);
    PropVariantClear(&value);
    return hr;
}

static HRESULT WINAPI ShellItem2_GetUInt64(IShellItem2 *iface, REFPROPERTYKEY key, ULONGLONG *pull)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    PROPVARIANT value;
    HRESULT hr;

    TRACE("%p (%p, %p)\n", This, key, pull);

    if (!pull) return E_POINTER;

    hr = IShellItem2_GetProperty(iface, key, &value);
    if (FAILED(hr) || hr == S_FALSE)
        return hr;

    hr = shellitem_propvariant_to_uint64(&value, pull);
    PropVariantClear(&value);
    return hr;
}

static HRESULT WINAPI ShellItem2_GetBool(IShellItem2 *iface, REFPROPERTYKEY key, BOOL *pf)
{
    struct shell_item *This = impl_from_IShellItem2(iface);
    PROPVARIANT value;
    HRESULT hr;

    TRACE("%p (%p, %p)\n", This, key, pf);

    if (!pf) return E_POINTER;

    hr = IShellItem2_GetProperty(iface, key, &value);
    if (FAILED(hr) || hr == S_FALSE)
        return hr;

    hr = shellitem_propvariant_to_bool(&value, pf);
    PropVariantClear(&value);
    return hr;
}


static const IShellItem2Vtbl ShellItem2_Vtbl = {
    ShellItem_QueryInterface,
    ShellItem_AddRef,
    ShellItem_Release,
    ShellItem_BindToHandler,
    ShellItem_GetParent,
    ShellItem_GetDisplayName,
    ShellItem_GetAttributes,
    ShellItem_Compare,
    ShellItem2_GetPropertyStore,
    ShellItem2_GetPropertyStoreWithCreateObject,
    ShellItem2_GetPropertyStoreForKeys,
    ShellItem2_GetPropertyDescriptionList,
    ShellItem2_Update,
    ShellItem2_GetProperty,
    ShellItem2_GetCLSID,
    ShellItem2_GetFileTime,
    ShellItem2_GetInt32,
    ShellItem2_GetString,
    ShellItem2_GetUInt32,
    ShellItem2_GetUInt64,
    ShellItem2_GetBool
};

static HRESULT WINAPI ShellItem_IPersistIDList_QueryInterface(IPersistIDList *iface,
    REFIID riid, void **ppv)
{
    struct shell_item *This = impl_from_IPersistIDList(iface);
    return IShellItem2_QueryInterface(&This->IShellItem2_iface, riid, ppv);
}

static ULONG WINAPI ShellItem_IPersistIDList_AddRef(IPersistIDList *iface)
{
    struct shell_item *This = impl_from_IPersistIDList(iface);
    return IShellItem2_AddRef(&This->IShellItem2_iface);
}

static ULONG WINAPI ShellItem_IPersistIDList_Release(IPersistIDList *iface)
{
    struct shell_item *This = impl_from_IPersistIDList(iface);
    return IShellItem2_Release(&This->IShellItem2_iface);
}

static HRESULT WINAPI ShellItem_IPersistIDList_GetClassID(IPersistIDList* iface,
    CLSID *pClassID)
{
    *pClassID = CLSID_ShellItem;
    return S_OK;
}

static HRESULT WINAPI ShellItem_IPersistIDList_SetIDList(IPersistIDList* iface,
    LPCITEMIDLIST pidl)
{
    struct shell_item *This = impl_from_IPersistIDList(iface);
    LPITEMIDLIST new_pidl;

    TRACE("(%p,%p)\n", This, pidl);

    new_pidl = ILClone(pidl);

    if (new_pidl)
    {
        ILFree(This->pidl);
        This->pidl = new_pidl;
        return S_OK;
    }
    else
        return E_OUTOFMEMORY;
}

static HRESULT WINAPI ShellItem_IPersistIDList_GetIDList(IPersistIDList* iface,
    LPITEMIDLIST *ppidl)
{
    struct shell_item *This = impl_from_IPersistIDList(iface);

    TRACE("(%p,%p)\n", This, ppidl);

    *ppidl = ILClone(This->pidl);
    if (*ppidl)
        return S_OK;
    else
        return E_OUTOFMEMORY;
}

static const IPersistIDListVtbl ShellItem_IPersistIDList_Vtbl = {
    ShellItem_IPersistIDList_QueryInterface,
    ShellItem_IPersistIDList_AddRef,
    ShellItem_IPersistIDList_Release,
    ShellItem_IPersistIDList_GetClassID,
    ShellItem_IPersistIDList_SetIDList,
    ShellItem_IPersistIDList_GetIDList
};

static HRESULT WINAPI ShellItem_IShellItemImageFactory_QueryInterface(IShellItemImageFactory *iface,
    REFIID riid, void **ppv)
{
    struct shell_item *This = impl_from_IShellItemImageFactory(iface);
    return IShellItem2_QueryInterface(&This->IShellItem2_iface, riid, ppv);
}

static ULONG WINAPI ShellItem_IShellItemImageFactory_AddRef(IShellItemImageFactory *iface)
{
    struct shell_item *This = impl_from_IShellItemImageFactory(iface);
    return IShellItem2_AddRef(&This->IShellItem2_iface);
}

static ULONG WINAPI ShellItem_IShellItemImageFactory_Release(IShellItemImageFactory *iface)
{
    struct shell_item *This = impl_from_IShellItemImageFactory(iface);
    return IShellItem2_Release(&This->IShellItem2_iface);
}

static HRESULT WINAPI ShellItem_IShellItemImageFactory_GetImage(IShellItemImageFactory *iface,
    SIZE size, SIIGBF flags, HBITMAP *phbm)
{
    struct shell_item *This = impl_from_IShellItemImageFactory(iface);
    static const BITMAPINFOHEADER dummy_bmi_header = {
        .biSize = sizeof(dummy_bmi_header),
        .biWidth = 1,
        .biHeight = 1,
        .biPlanes = 1,
        .biBitCount = 32,
        .biCompression = BI_RGB
    };

    TRACE("%p ({%lu, %lu} %d %p)\n", This, size.cx, size.cy, flags, phbm);

    if (!(*phbm = CreateDIBSection(NULL, (const BITMAPINFO *)&dummy_bmi_header,
                                   DIB_RGB_COLORS, NULL, NULL, 0)))
    {
        return E_OUTOFMEMORY;
    }

    return S_OK;
}

static const IShellItemImageFactoryVtbl ShellItem_IShellItemImageFactory_Vtbl = {
    ShellItem_IShellItemImageFactory_QueryInterface,
    ShellItem_IShellItemImageFactory_AddRef,
    ShellItem_IShellItemImageFactory_Release,
    ShellItem_IShellItemImageFactory_GetImage,
};


HRESULT WINAPI IShellItem_Constructor(IUnknown *pUnkOuter, REFIID riid, void **ppv)
{
    struct shell_item *This;
    HRESULT ret;

    TRACE("(%p,%s)\n",pUnkOuter, debugstr_guid(riid));

    *ppv = NULL;

    if (pUnkOuter) return CLASS_E_NOAGGREGATION;

    This = malloc(sizeof(*This));
    This->IShellItem2_iface.lpVtbl = &ShellItem2_Vtbl;
    This->ref = 1;
    This->pidl = NULL;
    This->IPersistIDList_iface.lpVtbl = &ShellItem_IPersistIDList_Vtbl;
    This->IShellItemImageFactory_iface.lpVtbl = &ShellItem_IShellItemImageFactory_Vtbl;

    ret = IShellItem2_QueryInterface(&This->IShellItem2_iface, riid, ppv);
    IShellItem2_Release(&This->IShellItem2_iface);

    return ret;
}

HRESULT WINAPI SHCreateShellItem(LPCITEMIDLIST pidlParent,
    IShellFolder *psfParent, LPCITEMIDLIST pidl, IShellItem **ppsi)
{
    LPITEMIDLIST new_pidl;
    HRESULT ret;

    TRACE("(%p,%p,%p,%p)\n", pidlParent, psfParent, pidl, ppsi);

    *ppsi = NULL;

    if (!pidl)
    {
        return E_INVALIDARG;
    }
    else if (pidlParent || psfParent)
    {
        LPITEMIDLIST temp_parent=NULL;
        if (!pidlParent)
        {
            IPersistFolder2* ppf2Parent;

            if (FAILED(IShellFolder_QueryInterface(psfParent, &IID_IPersistFolder2, (void**)&ppf2Parent)))
            {
                FIXME("couldn't get IPersistFolder2 interface of parent\n");
                return E_NOINTERFACE;
            }

            if (FAILED(IPersistFolder2_GetCurFolder(ppf2Parent, &temp_parent)))
            {
                FIXME("couldn't get parent PIDL\n");
                IPersistFolder2_Release(ppf2Parent);
                return E_NOINTERFACE;
            }

            pidlParent = temp_parent;
            IPersistFolder2_Release(ppf2Parent);
        }

        new_pidl = ILCombine(pidlParent, pidl);
        ILFree(temp_parent);

        if (!new_pidl)
            return E_OUTOFMEMORY;
    }
    else
    {
        new_pidl = ILClone(pidl);
        if (!new_pidl)
            return E_OUTOFMEMORY;
    }

    ret = SHCreateItemFromIDList(new_pidl, &IID_IShellItem, (void**)ppsi);
    ILFree(new_pidl);

    return ret;
}

HRESULT WINAPI SHCreateItemFromParsingName(PCWSTR pszPath,
    IBindCtx *pbc, REFIID riid, void **ppv)
{
    LPITEMIDLIST pidl;
    HRESULT ret;

    *ppv = NULL;

    ret = SHParseDisplayName(pszPath, pbc, &pidl, 0, NULL);
    if(SUCCEEDED(ret))
    {
        ret = SHCreateItemFromIDList(pidl, riid, ppv);
        ILFree(pidl);
    }
    return ret;
}

HRESULT WINAPI SHCreateItemFromRelativeName(IShellItem *parent, PCWSTR name, IBindCtx *pbc,
                                            REFIID riid, void **ppv)
{
    LPITEMIDLIST pidl_folder = NULL, pidl = NULL;
    IShellFolder *desktop = NULL, *folder = NULL;
    HRESULT hr;

    TRACE("(%p, %s, %p, %s, %p)\n", parent, wine_dbgstr_w(name), pbc, debugstr_guid(riid), ppv);

    if(!ppv)
        return E_INVALIDARG;
    *ppv = NULL;
    if(!name)
        return E_INVALIDARG;

    hr = SHGetIDListFromObject((IUnknown*)parent, &pidl_folder);
    if(hr != S_OK)
        return hr;

    hr = SHGetDesktopFolder(&desktop);
    if(hr != S_OK)
        goto cleanup;

    if(!_ILIsDesktop(pidl_folder))
    {
        hr = IShellFolder_BindToObject(desktop, pidl_folder, NULL, &IID_IShellFolder,
                                       (void**)&folder);
        if(hr != S_OK)
            goto cleanup;
    }

    hr = IShellFolder_ParseDisplayName(folder ? folder : desktop, NULL, pbc, (LPWSTR)name,
                                       NULL, &pidl, NULL);
    if(hr != S_OK)
        goto cleanup;
    hr = SHCreateItemFromIDList(pidl, riid, ppv);

cleanup:
    if(pidl_folder)
        ILFree(pidl_folder);
    if(pidl)
        ILFree(pidl);
    if(desktop)
        IShellFolder_Release(desktop);
    if(folder)
        IShellFolder_Release(folder);
    return hr;
}

HRESULT WINAPI SHCreateItemFromIDList(PCIDLIST_ABSOLUTE pidl, REFIID riid, void **ppv)
{
    IPersistIDList *persist;
    HRESULT ret;

    if(!pidl)
        return E_INVALIDARG;

    *ppv = NULL;
    ret = IShellItem_Constructor(NULL, &IID_IPersistIDList, (void**)&persist);
    if(FAILED(ret))
        return ret;

    ret = IPersistIDList_SetIDList(persist, pidl);
    if(FAILED(ret))
    {
        IPersistIDList_Release(persist);
        return ret;
    }

    ret = IPersistIDList_QueryInterface(persist, riid, ppv);
    IPersistIDList_Release(persist);
    return ret;
}

HRESULT WINAPI SHCreateItemWithParent(PCIDLIST_ABSOLUTE pidl_parent, IShellFolder *psf,
                                PCUITEMID_CHILD pidl, REFIID riid, void **ppv)
{
    LPITEMIDLIST full_pidl;
    LPITEMIDLIST desktop_pidl = NULL;
    HRESULT hr;

    TRACE("(%p, %p, %p, %s, %p)\n", pidl_parent, psf, pidl, debugstr_guid(riid), ppv);

    if (!ppv)
        return E_INVALIDARG;
    *ppv = NULL;
    if (!pidl)
        return E_INVALIDARG;

    if (!pidl_parent)
    {
        hr = SHGetFolderLocation(NULL, CSIDL_DESKTOP, NULL, 0, &desktop_pidl);
        if (FAILED(hr) || !desktop_pidl)
            return hr;
        full_pidl = ILCombine(desktop_pidl, pidl);
        ILFree(desktop_pidl);
    }
    else
        full_pidl = ILCombine(pidl_parent, pidl);

    if (!full_pidl)
        return E_OUTOFMEMORY;

    hr = SHCreateItemFromIDList(full_pidl, riid, ppv);
    ILFree(full_pidl);
    return hr;
}

HRESULT WINAPI SHCreateItemInKnownFolder(REFKNOWNFOLDERID rfid, DWORD flags,
                                         PCWSTR filename, REFIID riid, void **ppv)
{
    HRESULT hr;
    IShellItem *parent = NULL;
    LPITEMIDLIST pidl = NULL;

    TRACE("(%p, %lx, %s, %s, %p)\n", rfid, flags, wine_dbgstr_w(filename),
          debugstr_guid(riid), ppv);

    if(!rfid || !ppv)
        return E_INVALIDARG;

    *ppv = NULL;
    hr = SHGetKnownFolderIDList(rfid, flags, NULL, &pidl);
    if(hr != S_OK)
        return hr;

    hr = SHCreateItemFromIDList(pidl, &IID_IShellItem, (void**)&parent);
    if(hr != S_OK)
    {
        ILFree(pidl);
        return hr;
    }

    if(filename)
        hr = SHCreateItemFromRelativeName(parent, filename, NULL, riid, ppv);
    else
        hr = IShellItem_QueryInterface(parent, riid, ppv);

    ILFree(pidl);
    IShellItem_Release(parent);
    return hr;
}

static HRESULT shellitem_create_item_from_url(PCWSTR url, REFIID riid, void **ppv)
{
    WCHAR path[MAX_PATH];
    DWORD size = ARRAY_SIZE(path);
    HRESULT hr;

    if (!ppv) return E_POINTER;
    *ppv = NULL;
    if (!url || !*url) return E_INVALIDARG;

    hr = SHCreateItemFromParsingName(url, NULL, riid, ppv);
    if (SUCCEEDED(hr))
        return hr;

    if (PathIsURLW(url) && SUCCEEDED(PathCreateFromUrlW(url, path, &size, 0)))
        return SHCreateItemFromParsingName(path, NULL, riid, ppv);

    return hr;
}

static HRESULT shellitem_get_url_data_object_item(IDataObject *data_object, REFIID riid, void **ppv)
{
    FORMATETC fmt;
    STGMEDIUM medium;
    HRESULT hr;

    if (!ppv) return E_POINTER;
    *ppv = NULL;

    fmt.ptd = NULL;
    fmt.dwAspect = DVASPECT_CONTENT;
    fmt.lindex = -1;
    fmt.tymed = TYMED_HGLOBAL;

    fmt.cfFormat = RegisterClipboardFormatW(CFSTR_INETURLW);
    hr = IDataObject_GetData(data_object, &fmt, &medium);
    if (SUCCEEDED(hr))
    {
        const WCHAR *url = GlobalLock(medium.hGlobal);

        if (url)
        {
            hr = shellitem_create_item_from_url(url, riid, ppv);
            GlobalUnlock(medium.hGlobal);
        }
        else
            hr = HRESULT_FROM_WIN32(GetLastError());

        ReleaseStgMedium(&medium);
        if (SUCCEEDED(hr))
            return hr;
    }

    fmt.cfFormat = RegisterClipboardFormatA(CFSTR_INETURLA);
    hr = IDataObject_GetData(data_object, &fmt, &medium);
    if (SUCCEEDED(hr))
    {
        const char *url = GlobalLock(medium.hGlobal);

        if (url)
        {
            WCHAR *wide_url;
            int len = MultiByteToWideChar(CP_ACP, 0, url, -1, NULL, 0);

            if (len && (wide_url = malloc(len * sizeof(WCHAR))))
            {
                MultiByteToWideChar(CP_ACP, 0, url, -1, wide_url, len);
                hr = shellitem_create_item_from_url(wide_url, riid, ppv);
                free(wide_url);
            }
            else
                hr = E_OUTOFMEMORY;

            GlobalUnlock(medium.hGlobal);
        }
        else
            hr = HRESULT_FROM_WIN32(GetLastError());

        ReleaseStgMedium(&medium);
    }

    return hr;
}

static HRESULT shellitem_get_filename_data_object_item(IDataObject *data_object, REFIID riid, void **ppv)
{
    FORMATETC fmt;
    STGMEDIUM medium;
    HRESULT hr;

    if (!ppv) return E_POINTER;
    *ppv = NULL;

    fmt.ptd = NULL;
    fmt.dwAspect = DVASPECT_CONTENT;
    fmt.lindex = -1;
    fmt.tymed = TYMED_HGLOBAL;

    fmt.cfFormat = RegisterClipboardFormatW(CFSTR_FILENAMEW);
    hr = IDataObject_GetData(data_object, &fmt, &medium);
    if (SUCCEEDED(hr))
    {
        const WCHAR *filename = GlobalLock(medium.hGlobal);

        if (filename)
        {
            hr = SHCreateItemFromParsingName(filename, NULL, riid, ppv);
            GlobalUnlock(medium.hGlobal);
        }
        else
            hr = HRESULT_FROM_WIN32(GetLastError());

        ReleaseStgMedium(&medium);
        if (SUCCEEDED(hr))
            return hr;
    }

    fmt.cfFormat = RegisterClipboardFormatA(CFSTR_FILENAMEA);
    hr = IDataObject_GetData(data_object, &fmt, &medium);
    if (SUCCEEDED(hr))
    {
        const char *filename = GlobalLock(medium.hGlobal);

        if (filename)
        {
            WCHAR wide_filename[MAX_PATH];

            MultiByteToWideChar(CP_ACP, 0, filename, -1, wide_filename, ARRAY_SIZE(wide_filename));
            hr = SHCreateItemFromParsingName(wide_filename, NULL, riid, ppv);
            GlobalUnlock(medium.hGlobal);
        }
        else
            hr = HRESULT_FROM_WIN32(GetLastError());

        ReleaseStgMedium(&medium);
    }

    return hr;
}

static HRESULT shellitem_get_single_item_data_object_array(IDataObject *data_object,
    HRESULT (*get_item)(IDataObject *, REFIID, void **), REFIID riid, void **ppv)
{
    IShellItem *item;
    HRESULT hr;

    if (!ppv) return E_POINTER;
    *ppv = NULL;

    hr = get_item(data_object, &IID_IShellItem, (void **)&item);
    if (FAILED(hr))
        return hr;

    hr = SHCreateShellItemArrayFromShellItem(item, riid, ppv);
    IShellItem_Release(item);
    return hr;
}

static HRESULT shellitem_get_hdrop_data_object_array(IDataObject *data_object, REFIID riid, void **ppv)
{
    FORMATETC fmt;
    STGMEDIUM medium;
    DROPFILES *drop_files;
    IShellItemArray *array;
    IShellItem **items = NULL;
    WCHAR *filename = NULL;
    UINT i, created = 0, file_count;
    HRESULT hr = E_FAIL;

    if (!ppv) return E_POINTER;
    *ppv = NULL;

    fmt.cfFormat = CF_HDROP;
    fmt.ptd = NULL;
    fmt.dwAspect = DVASPECT_CONTENT;
    fmt.lindex = -1;
    fmt.tymed = TYMED_HGLOBAL;

    hr = IDataObject_GetData(data_object, &fmt, &medium);
    if (FAILED(hr))
        return hr;

    drop_files = GlobalLock(medium.hGlobal);
    if (!drop_files)
    {
        hr = HRESULT_FROM_WIN32(GetLastError());
        ReleaseStgMedium(&medium);
        return hr;
    }

    file_count = DragQueryFileW((HDROP)drop_files, 0xffffffff, NULL, 0);
    if (!file_count)
    {
        hr = E_FAIL;
        goto done;
    }

    items = calloc(file_count, sizeof(*items));
    if (!items)
    {
        hr = E_OUTOFMEMORY;
        goto done;
    }

    for (i = 0; i < file_count; ++i)
    {
        UINT len = DragQueryFileW((HDROP)drop_files, i, NULL, 0);

        filename = malloc((len + 1) * sizeof(WCHAR));
        if (!filename)
        {
            hr = E_OUTOFMEMORY;
            goto done;
        }

        DragQueryFileW((HDROP)drop_files, i, filename, len + 1);
        hr = SHCreateItemFromParsingName(filename, NULL, &IID_IShellItem, (void **)&items[i]);
        free(filename);
        filename = NULL;
        if (FAILED(hr))
            goto done;
        created++;
    }

    hr = create_shellitemarray(items, file_count, &array);
    if (SUCCEEDED(hr))
    {
        hr = IShellItemArray_QueryInterface(array, riid, ppv);
        IShellItemArray_Release(array);
    }

done:
    free(filename);
    if (items)
    {
        while (created--)
            IShellItem_Release(items[created]);
        free(items);
    }
    GlobalUnlock(medium.hGlobal);
    ReleaseStgMedium(&medium);
    return hr;
}

static HRESULT shellitem_maybe_traverse_link(DATAOBJ_GET_ITEM_FLAGS flags, REFIID riid, void **ppv)
{
    IShellItem *item, *target;
    HRESULT hr;

    if (!ppv) return E_POINTER;
    if (!(flags & DOGIF_TRAVERSE_LINK) || !*ppv)
        return S_OK;
    if (!IsEqualIID(riid, &IID_IShellItem) && !IsEqualIID(riid, &IID_IShellItem2))
        return S_OK;

    item = *ppv;
    hr = IShellItem_BindToHandler(item, NULL, &BHID_LinkTargetItem, riid, (void **)&target);
    if (FAILED(hr))
        return S_OK;

    IUnknown_Release((IUnknown *)*ppv);
    *ppv = target;
    return S_OK;
}

HRESULT WINAPI SHGetItemFromDataObject(IDataObject *pdtobj,
    DATAOBJ_GET_ITEM_FLAGS dwFlags, REFIID riid, void **ppv)
{
    FORMATETC fmt;
    STGMEDIUM medium;
    HRESULT ret;

    TRACE("%p, %x, %s, %p\n", pdtobj, dwFlags, debugstr_guid(riid), ppv);

    if(!pdtobj)
        return E_INVALIDARG;

    fmt.cfFormat = RegisterClipboardFormatW(CFSTR_SHELLIDLISTW);
    fmt.ptd = NULL;
    fmt.dwAspect = DVASPECT_CONTENT;
    fmt.lindex = -1;
    fmt.tymed = TYMED_HGLOBAL;

    ret = IDataObject_GetData(pdtobj, &fmt, &medium);
    if(SUCCEEDED(ret))
    {
        LPIDA pida = GlobalLock(medium.hGlobal);

        if((pida->cidl > 1 && !(dwFlags & DOGIF_ONLY_IF_ONE)) ||
           pida->cidl == 1)
        {
            LPITEMIDLIST pidl;

            /* Get the first pidl (parent + child1) */
            pidl = ILCombine((LPCITEMIDLIST) ((LPBYTE)pida+pida->aoffset[0]),
                             (LPCITEMIDLIST) ((LPBYTE)pida+pida->aoffset[1]));

            ret = SHCreateItemFromIDList(pidl, riid, ppv);
            ILFree(pidl);
            if (SUCCEEDED(ret))
                shellitem_maybe_traverse_link(dwFlags, riid, ppv);
        }
        else
        {
            ret = E_FAIL;
        }

        GlobalUnlock(medium.hGlobal);
        GlobalFree(medium.hGlobal);
    }

    if(FAILED(ret) && !(dwFlags & DOGIF_NO_HDROP))
    {
        TRACE("Attempting to fall back on CF_HDROP.\n");

        fmt.cfFormat = CF_HDROP;
        fmt.ptd = NULL;
        fmt.dwAspect = DVASPECT_CONTENT;
        fmt.lindex = -1;
        fmt.tymed = TYMED_HGLOBAL;

        ret = IDataObject_GetData(pdtobj, &fmt, &medium);
        if(SUCCEEDED(ret))
        {
            DROPFILES *df = GlobalLock(medium.hGlobal);
            LPBYTE files = (LPBYTE)df + df->pFiles;
            BOOL multiple_files = FALSE;

            ret = E_FAIL;
            if(!df->fWide)
            {
                WCHAR filename[MAX_PATH];
                PCSTR first_file = (PCSTR)files;
                if(*(files + lstrlenA(first_file) + 1) != 0)
                    multiple_files = TRUE;

                if( !(multiple_files && (dwFlags & DOGIF_ONLY_IF_ONE)) )
                {
                    MultiByteToWideChar(CP_ACP, 0, first_file, -1, filename, MAX_PATH);
                    ret = SHCreateItemFromParsingName(filename, NULL, riid, ppv);
                    if (SUCCEEDED(ret))
                        shellitem_maybe_traverse_link(dwFlags, riid, ppv);
                }
            }
            else
            {
                PCWSTR first_file = (PCWSTR)files;
                if(*((PCWSTR)files + lstrlenW(first_file) + 1) != 0)
                    multiple_files = TRUE;

                if( !(multiple_files && (dwFlags & DOGIF_ONLY_IF_ONE)) )
                {
                    ret = SHCreateItemFromParsingName(first_file, NULL, riid, ppv);
                    if (SUCCEEDED(ret))
                        shellitem_maybe_traverse_link(dwFlags, riid, ppv);
                }
            }

            GlobalUnlock(medium.hGlobal);
            GlobalFree(medium.hGlobal);
        }
    }

    if(FAILED(ret) && !(dwFlags & DOGIF_NO_HDROP))
    {
        TRACE("Attempting to fall back on CFSTR_FILENAME.\n");
        ret = shellitem_get_filename_data_object_item(pdtobj, riid, ppv);
        if (SUCCEEDED(ret))
            shellitem_maybe_traverse_link(dwFlags, riid, ppv);
    }

    if(FAILED(ret) && !(dwFlags & DOGIF_NO_URL))
    {
        ret = shellitem_get_url_data_object_item(pdtobj, riid, ppv);
        if (SUCCEEDED(ret))
            shellitem_maybe_traverse_link(dwFlags, riid, ppv);
    }

    return ret;
}

HRESULT WINAPI SHGetItemFromObject(IUnknown *punk, REFIID riid, void **ppv)
{
    IShellItem *item;
    IShellItemArray *array;
    IDataObject *data_object;
    IShellView *shell_view;
    IFolderView2 *folder_view;
    IFolderView *legacy_folder_view;
    IParentAndItem *parent_item;
    LPITEMIDLIST pidl;
    PIDLIST_ABSOLUTE parent;
    PITEMID_CHILD child;
    HRESULT ret;

    if (!ppv) return E_INVALIDARG;
    *ppv = NULL;

    ret = IUnknown_QueryInterface(punk, &IID_IShellItem, (void **)&item);
    if (SUCCEEDED(ret))
    {
        if (IsEqualIID(riid, &IID_IShellItemArray))
            ret = SHCreateShellItemArrayFromShellItem(item, riid, ppv);
        else
            ret = IShellItem_QueryInterface(item, riid, ppv);
        IShellItem_Release(item);
        return ret;
    }

    ret = IUnknown_QueryInterface(punk, &IID_IShellItemArray, (void **)&array);
    if (SUCCEEDED(ret))
    {
        if (IsEqualIID(riid, &IID_IShellItemArray))
        {
            *ppv = array;
            return S_OK;
        }

        DWORD count;

        ret = IShellItemArray_GetCount(array, &count);
        if (SUCCEEDED(ret))
        {
            if (count == 1)
            {
                ret = IShellItemArray_GetItemAt(array, 0, &item);
                if (SUCCEEDED(ret))
                {
                    ret = IShellItem_QueryInterface(item, riid, ppv);
                    IShellItem_Release(item);
                }
            }
            else
                ret = E_FAIL;
        }

        IShellItemArray_Release(array);
        if (SUCCEEDED(ret))
            return ret;
    }

    if (IsEqualIID(riid, &IID_IShellItemArray))
    {
        ret = IUnknown_QueryInterface(punk, &IID_IDataObject, (void **)&data_object);
        if (SUCCEEDED(ret))
        {
            ret = SHCreateShellItemArrayFromDataObject(data_object, riid, ppv);
            IDataObject_Release(data_object);
            if (SUCCEEDED(ret))
                return ret;
        }
    }
    else
    {
        ret = IUnknown_QueryInterface(punk, &IID_IDataObject, (void **)&data_object);
        if (SUCCEEDED(ret))
        {
            ret = SHGetItemFromDataObject(data_object, DOGIF_ONLY_IF_ONE, riid, ppv);
            IDataObject_Release(data_object);
            if (SUCCEEDED(ret))
                return ret;
        }
    }

    ret = IUnknown_QueryInterface(punk, &IID_IShellView, (void **)&shell_view);
    if (SUCCEEDED(ret))
    {
        ret = IShellView_GetItemObject(shell_view, SVGIO_SELECTION, &IID_IDataObject, (void **)&data_object);
        if (SUCCEEDED(ret))
        {
            if (IsEqualIID(riid, &IID_IShellItemArray))
                ret = SHCreateShellItemArrayFromDataObject(data_object, riid, ppv);
            else
                ret = SHGetItemFromDataObject(data_object, DOGIF_ONLY_IF_ONE, riid, ppv);

            IDataObject_Release(data_object);
        }
        IShellView_Release(shell_view);
        if (ret != E_FAIL)
            return ret;
    }

    ret = IUnknown_QueryInterface(punk, &IID_IFolderView2, (void **)&folder_view);
    if (SUCCEEDED(ret))
    {
        ret = IFolderView2_GetSelection(folder_view, FALSE, &array);
        if (SUCCEEDED(ret))
        {
            ret = IShellItemArray_QueryInterface(array, riid, ppv);
            IShellItemArray_Release(array);
        }
        IFolderView2_Release(folder_view);
        if (ret != E_FAIL)
            return ret;
    }

    ret = IUnknown_QueryInterface(punk, &IID_IFolderView, (void **)&legacy_folder_view);
    if (SUCCEEDED(ret))
    {
        IShellView *folder_shell_view = NULL;

        ret = IFolderView_QueryInterface(legacy_folder_view, &IID_IShellView, (void **)&folder_shell_view);
        if (SUCCEEDED(ret))
        {
            ret = IShellView_GetItemObject(folder_shell_view, SVGIO_SELECTION, &IID_IDataObject, (void **)&data_object);
            if (SUCCEEDED(ret))
            {
                if (IsEqualIID(riid, &IID_IShellItemArray))
                    ret = SHCreateShellItemArrayFromDataObject(data_object, riid, ppv);
                else
                    ret = SHGetItemFromDataObject(data_object, DOGIF_ONLY_IF_ONE, riid, ppv);

                IDataObject_Release(data_object);
            }
            IShellView_Release(folder_shell_view);
        }
        IFolderView_Release(legacy_folder_view);
        if (ret != E_FAIL)
            return ret;
    }

    ret = IUnknown_QueryInterface(punk, &IID_IParentAndItem, (void **)&parent_item);
    if (SUCCEEDED(ret))
    {
        IShellFolder *folder = NULL;
        IShellItem *parent_shell_item = NULL;

        parent = NULL;
        child = NULL;
        ret = IParentAndItem_GetParentAndItem(parent_item, &parent, &folder, &child);
        if (SUCCEEDED(ret))
        {
            if (IsEqualIID(riid, &IID_IShellItemArray))
            {
                if (parent && child)
                    ret = SHCreateItemWithParent(parent, folder, child, &IID_IShellItem, (void **)&parent_shell_item);
                else if (parent)
                    ret = SHCreateItemFromIDList(parent, &IID_IShellItem, (void **)&parent_shell_item);
                else
                    ret = E_FAIL;

                if (SUCCEEDED(ret))
                {
                    ret = SHCreateShellItemArrayFromShellItem(parent_shell_item, riid, ppv);
                    IShellItem_Release(parent_shell_item);
                }
            }
            else if (parent && child)
                ret = SHCreateItemWithParent(parent, folder, child, riid, ppv);
            else if (parent)
                ret = SHCreateItemFromIDList(parent, riid, ppv);
            else
                ret = E_FAIL;
        }

        ILFree(parent);
        ILFree(child);
        if (folder) IShellFolder_Release(folder);
        IParentAndItem_Release(parent_item);
        if (SUCCEEDED(ret))
            return ret;
    }

    ret = SHGetIDListFromObject(punk, &pidl);
    if(SUCCEEDED(ret))
    {
        if (IsEqualIID(riid, &IID_IShellItemArray))
        {
            ret = SHCreateItemFromIDList(pidl, &IID_IShellItem, (void **)&item);
            if (SUCCEEDED(ret))
            {
                ret = SHCreateShellItemArrayFromShellItem(item, riid, ppv);
                IShellItem_Release(item);
            }
        }
        else
            ret = SHCreateItemFromIDList(pidl, riid, ppv);
        ILFree(pidl);
    }

    return ret;
}

/*************************************************************************
 * IEnumShellItems implementation
 */
typedef struct {
    IEnumShellItems IEnumShellItems_iface;
    LONG ref;

    IShellItemArray *array;
    DWORD count;
    DWORD position;
} IEnumShellItemsImpl;

static inline IEnumShellItemsImpl *impl_from_IEnumShellItems(IEnumShellItems *iface)
{
    return CONTAINING_RECORD(iface, IEnumShellItemsImpl, IEnumShellItems_iface);
}

static HRESULT WINAPI IEnumShellItems_fnQueryInterface(IEnumShellItems *iface,
                                                       REFIID riid,
                                                       void **ppvObject)
{
    IEnumShellItemsImpl *This = impl_from_IEnumShellItems(iface);
    TRACE("%p (%s, %p)\n", This, shdebugstr_guid(riid), ppvObject);

    *ppvObject = NULL;
    if(IsEqualIID(riid, &IID_IEnumShellItems) ||
       IsEqualIID(riid, &IID_IUnknown))
    {
        *ppvObject = &This->IEnumShellItems_iface;
    }

    if(*ppvObject)
    {
        IUnknown_AddRef((IUnknown*)*ppvObject);
        return S_OK;
    }

    return E_NOINTERFACE;
}

static ULONG WINAPI IEnumShellItems_fnAddRef(IEnumShellItems *iface)
{
    IEnumShellItemsImpl *This = impl_from_IEnumShellItems(iface);
    LONG ref = InterlockedIncrement(&This->ref);
    TRACE("%p - ref %ld\n", This, ref);

    return ref;
}

static ULONG WINAPI IEnumShellItems_fnRelease(IEnumShellItems *iface)
{
    IEnumShellItemsImpl *This = impl_from_IEnumShellItems(iface);
    LONG ref = InterlockedDecrement(&This->ref);
    TRACE("%p - ref %ld\n", This, ref);

    if(!ref)
    {
        TRACE("Freeing.\n");
        IShellItemArray_Release(This->array);
        free(This);
        return 0;
    }

    return ref;
}

static HRESULT WINAPI IEnumShellItems_fnNext(IEnumShellItems* iface,
                                             ULONG celt,
                                             IShellItem **rgelt,
                                             ULONG *pceltFetched)
{
    IEnumShellItemsImpl *This = impl_from_IEnumShellItems(iface);
    HRESULT hr = S_FALSE;
    UINT i;
    ULONG fetched = 0;
    TRACE("%p (%ld %p %p)\n", This, celt, rgelt, pceltFetched);

    if(!rgelt)
        return E_POINTER;
    if(pceltFetched == NULL && celt != 1)
        return E_INVALIDARG;
    if(pceltFetched)
        *pceltFetched = 0;

    for(i = This->position; fetched < celt && i < This->count; i++) {
        hr = IShellItemArray_GetItemAt(This->array, i, &rgelt[fetched]);
        if(FAILED(hr))
            break;
        fetched++;
        This->position++;
    }

    if(SUCCEEDED(hr))
    {
        if(pceltFetched != NULL)
            *pceltFetched = fetched;

        if(fetched > 0)
            return S_OK;

        return S_FALSE;
    }

    return hr;
}

static HRESULT WINAPI IEnumShellItems_fnSkip(IEnumShellItems* iface, ULONG celt)
{
    IEnumShellItemsImpl *This = impl_from_IEnumShellItems(iface);
    DWORD remaining;
    TRACE("%p (%ld)\n", This, celt);

    remaining = This->count - This->position;
    This->position = min(This->position + celt, This->count);

    return celt <= remaining ? S_OK : S_FALSE;
}

static HRESULT WINAPI IEnumShellItems_fnReset(IEnumShellItems* iface)
{
    IEnumShellItemsImpl *This = impl_from_IEnumShellItems(iface);
    TRACE("%p\n", This);

    This->position = 0;

    return S_OK;
}

static const IEnumShellItemsVtbl vt_IEnumShellItems;

static HRESULT WINAPI IEnumShellItems_fnClone(IEnumShellItems* iface, IEnumShellItems **ppenum)
{
    IEnumShellItemsImpl *This = impl_from_IEnumShellItems(iface);
    IEnumShellItemsImpl *clone;
    HRESULT hr;

    TRACE("%p (%p)\n", This, ppenum);

    if (!ppenum)
        return E_INVALIDARG;
    *ppenum = NULL;

    clone = malloc(sizeof(*clone));
    if (!clone)
        return E_OUTOFMEMORY;

    clone->ref = 1;
    clone->IEnumShellItems_iface.lpVtbl = &vt_IEnumShellItems;
    clone->array = This->array;
    clone->count = This->count;
    clone->position = This->position;
    IShellItemArray_AddRef(clone->array);

    hr = IEnumShellItems_QueryInterface(&clone->IEnumShellItems_iface, &IID_IEnumShellItems, (void **)ppenum);
    IEnumShellItems_Release(&clone->IEnumShellItems_iface);
    return hr;
}

static const IEnumShellItemsVtbl vt_IEnumShellItems = {
    IEnumShellItems_fnQueryInterface,
    IEnumShellItems_fnAddRef,
    IEnumShellItems_fnRelease,
    IEnumShellItems_fnNext,
    IEnumShellItems_fnSkip,
    IEnumShellItems_fnReset,
    IEnumShellItems_fnClone
};

static HRESULT IEnumShellItems_Constructor(IShellItemArray *array, IEnumShellItems **ppesi)
{
    IEnumShellItemsImpl *This;
    HRESULT ret;

    This = malloc(sizeof(*This));
    if(!This)
        return E_OUTOFMEMORY;

    This->ref = 1;
    This->IEnumShellItems_iface.lpVtbl = &vt_IEnumShellItems;
    This->array = array;
    This->position = 0;

    IShellItemArray_AddRef(This->array);
    IShellItemArray_GetCount(This->array, &This->count);

    ret = IEnumShellItems_QueryInterface(&This->IEnumShellItems_iface, &IID_IEnumShellItems, (void**)ppesi);
    IEnumShellItems_Release(&This->IEnumShellItems_iface);

    return ret;
}

static HRESULT create_shellitem_enumerator(IShellItemArray *array, REFIID riid, void **ppv)
{
    IEnumShellItems *enum_items = NULL;
    HRESULT hr;

    if (!ppv) return E_POINTER;
    *ppv = NULL;

    hr = IEnumShellItems_Constructor(array, &enum_items);
    if (FAILED(hr))
        return hr;

    if (IsEqualIID(riid, &IID_IEnumShellItems))
    {
        *ppv = enum_items;
        return S_OK;
    }

    hr = IEnumShellItems_QueryInterface(enum_items, riid, ppv);
    IEnumShellItems_Release(enum_items);
    return hr;
}


/*************************************************************************
 * IShellItemArray implementation
 */
typedef struct {
    IShellItemArray IShellItemArray_iface;
    LONG ref;

    IShellItem **array;
    DWORD item_count;
} IShellItemArrayImpl;

static inline IShellItemArrayImpl *impl_from_IShellItemArray(IShellItemArray *iface)
{
    return CONTAINING_RECORD(iface, IShellItemArrayImpl, IShellItemArray_iface);
}

static HRESULT WINAPI IShellItemArray_fnQueryInterface(IShellItemArray *iface,
                                                       REFIID riid,
                                                       void **ppvObject)
{
    IShellItemArrayImpl *This = impl_from_IShellItemArray(iface);
    TRACE("%p (%s, %p)\n", This, shdebugstr_guid(riid), ppvObject);

    *ppvObject = NULL;
    if(IsEqualIID(riid, &IID_IShellItemArray) ||
       IsEqualIID(riid, &IID_IUnknown))
    {
        *ppvObject = &This->IShellItemArray_iface;
    }

    if(*ppvObject)
    {
        IUnknown_AddRef((IUnknown*)*ppvObject);
        return S_OK;
    }

    return E_NOINTERFACE;
}

static ULONG WINAPI IShellItemArray_fnAddRef(IShellItemArray *iface)
{
    IShellItemArrayImpl *This = impl_from_IShellItemArray(iface);
    LONG ref = InterlockedIncrement(&This->ref);
    TRACE("%p - ref %ld\n", This, ref);

    return ref;
}

static ULONG WINAPI IShellItemArray_fnRelease(IShellItemArray *iface)
{
    IShellItemArrayImpl *This = impl_from_IShellItemArray(iface);
    LONG ref = InterlockedDecrement(&This->ref);
    TRACE("%p - ref %ld\n", This, ref);

    if(!ref)
    {
        UINT i;
        TRACE("Freeing.\n");

        for(i = 0; i < This->item_count; i++)
            IShellItem_Release(This->array[i]);

        free(This->array);
        free(This);
        return 0;
    }

    return ref;
}

static HRESULT WINAPI IShellItemArray_fnBindToHandler(IShellItemArray *iface,
                                                      IBindCtx *pbc,
                                                      REFGUID bhid,
                                                      REFIID riid,
                                                      void **ppvOut)
{
    IShellItemArrayImpl *This = impl_from_IShellItemArray(iface);
    HRESULT hr;

    TRACE("%p (%p, %s, %s, %p)\n", This, pbc, shdebugstr_guid(bhid), shdebugstr_guid(riid), ppvOut);

    if (!ppvOut) return E_POINTER;
    *ppvOut = NULL;

    if (IsEqualGUID(bhid, &BHID_EnumItems) || IsEqualGUID(bhid, &BHID_StorageEnum))
        return create_shellitem_enumerator(iface, riid, ppvOut);

    if (IsEqualGUID(bhid, &BHID_PropertyStore))
        return create_empty_property_store(riid, ppvOut);

    if (IsEqualGUID(bhid, &BHID_SFObject) || IsEqualGUID(bhid, &BHID_SFUIObject) ||
        IsEqualGUID(bhid, &BHID_SFViewObject) || IsEqualGUID(bhid, &BHID_Stream) ||
        IsEqualGUID(bhid, &BHID_Storage) || IsEqualGUID(bhid, &BHID_LinkTargetItem) ||
        IsEqualGUID(bhid, &BHID_AssociationArray) || IsEqualGUID(bhid, &BHID_Filter) ||
        IsEqualGUID(bhid, &BHID_ThumbnailHandler) || IsEqualGUID(bhid, &BHID_EnumAssocHandlers) ||
        IsEqualGUID(bhid, &BHID_Transfer))
    {
        if (This->item_count != 1)
            return MK_E_NOOBJECT;

        return IShellItem_BindToHandler(This->array[0], pbc, bhid, riid, ppvOut);
    }

    if (IsEqualGUID(bhid, &BHID_DataObject))
    {
        LPITEMIDLIST parent = NULL, item_pidl = NULL, item_parent = NULL;
        PCUITEMID_CHILD *children = NULL;
        UINT i;

        if (!This->item_count)
            return MK_E_NOOBJECT;

        if (!(children = calloc(This->item_count, sizeof(*children))))
            return E_OUTOFMEMORY;

        for (i = 0; i < This->item_count; ++i)
        {
            hr = SHGetIDListFromObject((IUnknown *)This->array[i], &item_pidl);
            if (FAILED(hr) || !item_pidl)
            {
                hr = MK_E_NOOBJECT;
                goto done;
            }

            item_parent = ILClone(item_pidl);
            if (!item_parent || !ILRemoveLastID(item_parent))
            {
                hr = E_OUTOFMEMORY;
                goto done;
            }

            if (!parent)
            {
                parent = item_parent;
                item_parent = NULL;
            }
            else if (!ILIsEqual(parent, item_parent))
            {
                hr = MK_E_NOOBJECT;
                goto done;
            }

            children[i] = ILClone(ILFindLastID(item_pidl));
            if (!children[i])
            {
                hr = E_OUTOFMEMORY;
                goto done;
            }

            ILFree(item_parent);
            item_parent = NULL;
            ILFree(item_pidl);
            item_pidl = NULL;
        }

        hr = SHCreateDataObject(parent, This->item_count, children, NULL, riid, ppvOut);

done:
        ILFree(item_parent);
        ILFree(item_pidl);
        ILFree(parent);
        if (children)
        {
            for (i = 0; i < This->item_count; ++i)
                ILFree((LPITEMIDLIST)children[i]);
            free(children);
        }
        return hr;
    }

    return MK_E_NOOBJECT;
}

static HRESULT WINAPI IShellItemArray_fnGetPropertyStore(IShellItemArray *iface,
                                                         GETPROPERTYSTOREFLAGS flags,
                                                         REFIID riid,
                                                         void **ppv)
{
    IShellItemArrayImpl *This = impl_from_IShellItemArray(iface);
    TRACE("%p (%x, %s, %p)\n", This, flags, shdebugstr_guid(riid), ppv);
    return create_empty_property_store(riid, ppv);
}

static HRESULT WINAPI IShellItemArray_fnGetPropertyDescriptionList(IShellItemArray *iface,
                                                                   REFPROPERTYKEY keyType,
                                                                   REFIID riid,
                                                                   void **ppv)
{
    IShellItemArrayImpl *This = impl_from_IShellItemArray(iface);
    TRACE("%p (%p, %s, %p)\n", This, keyType, shdebugstr_guid(riid), ppv);
    return create_empty_property_description_list(riid, ppv);
}

static HRESULT WINAPI IShellItemArray_fnGetAttributes(IShellItemArray *iface,
                                                      SIATTRIBFLAGS AttribFlags,
                                                      SFGAOF sfgaoMask,
                                                      SFGAOF *psfgaoAttribs)
{
    IShellItemArrayImpl *This = impl_from_IShellItemArray(iface);
    HRESULT hr = S_OK;
    SFGAOF attr;
    UINT i;
    TRACE("%p (%x, %lx, %p)\n", This, AttribFlags, sfgaoMask, psfgaoAttribs);

    if(!psfgaoAttribs)
        return E_POINTER;
    if(AttribFlags & ~(SIATTRIBFLAGS_AND|SIATTRIBFLAGS_OR))
        FIXME("%08x contains unsupported attribution flags\n", AttribFlags);
    if(!This->item_count)
    {
        *psfgaoAttribs = 0;
        return S_FALSE;
    }

    for(i = 0; i < This->item_count; i++)
    {
        hr = IShellItem_GetAttributes(This->array[i], sfgaoMask, &attr);
        if(FAILED(hr))
            break;

        if(i == 0)
        {
            *psfgaoAttribs = attr;
            continue;
        }

        switch(AttribFlags & SIATTRIBFLAGS_MASK)
        {
        case SIATTRIBFLAGS_AND:
            *psfgaoAttribs &= attr;
            break;
        case SIATTRIBFLAGS_OR:
            *psfgaoAttribs |= attr;
            break;
        }
    }

    if(SUCCEEDED(hr))
    {
        if(*psfgaoAttribs == sfgaoMask)
            return S_OK;

        return S_FALSE;
    }

    return hr;
}

static HRESULT WINAPI IShellItemArray_fnGetCount(IShellItemArray *iface,
                                                 DWORD *pdwNumItems)
{
    IShellItemArrayImpl *This = impl_from_IShellItemArray(iface);
    TRACE("%p (%p)\n", This, pdwNumItems);

    if(!pdwNumItems)
        return E_POINTER;
    *pdwNumItems = This->item_count;

    return S_OK;
}

static HRESULT WINAPI IShellItemArray_fnGetItemAt(IShellItemArray *iface,
                                                  DWORD dwIndex,
                                                  IShellItem **ppsi)
{
    IShellItemArrayImpl *This = impl_from_IShellItemArray(iface);
    TRACE("%p (%lx, %p)\n", This, dwIndex, ppsi);

    if(!ppsi)
        return E_POINTER;
    *ppsi = NULL;
    /* zero indexed */
    if(dwIndex + 1 > This->item_count)
        return E_INVALIDARG;

    *ppsi = This->array[dwIndex];
    IShellItem_AddRef(*ppsi);

    return S_OK;
}

static HRESULT WINAPI IShellItemArray_fnEnumItems(IShellItemArray *iface,
                                                  IEnumShellItems **ppenumShellItems)
{
    IShellItemArrayImpl *This = impl_from_IShellItemArray(iface);
    TRACE("%p (%p)\n", This, ppenumShellItems);

    if(!ppenumShellItems)
        return E_POINTER;
    return IEnumShellItems_Constructor(iface, ppenumShellItems);
}

static const IShellItemArrayVtbl vt_IShellItemArray = {
    IShellItemArray_fnQueryInterface,
    IShellItemArray_fnAddRef,
    IShellItemArray_fnRelease,
    IShellItemArray_fnBindToHandler,
    IShellItemArray_fnGetPropertyStore,
    IShellItemArray_fnGetPropertyDescriptionList,
    IShellItemArray_fnGetAttributes,
    IShellItemArray_fnGetCount,
    IShellItemArray_fnGetItemAt,
    IShellItemArray_fnEnumItems
};

/* Caller is responsible to AddRef all items */
static HRESULT create_shellitemarray(IShellItem **items, DWORD count, IShellItemArray **ret)
{
    IShellItemArrayImpl *This;

    TRACE("(%p, %ld, %p)\n", items, count, ret);

    This = malloc(sizeof(*This));
    if(!This)
        return E_OUTOFMEMORY;

    This->IShellItemArray_iface.lpVtbl = &vt_IShellItemArray;
    This->ref = 1;

    This->array = malloc(count * sizeof(IShellItem*));
    if (!This->array)
    {
        free(This);
        return E_OUTOFMEMORY;
    }
    memcpy(This->array, items, count*sizeof(IShellItem*));
    This->item_count = count;

    *ret = &This->IShellItemArray_iface;
    return S_OK;
}

HRESULT WINAPI SHCreateShellItemArray(PCIDLIST_ABSOLUTE pidlParent,
                                      IShellFolder *psf,
                                      UINT cidl,
                                      PCUITEMID_CHILD_ARRAY ppidl,
                                      IShellItemArray **ppsiItemArray)
{
    IShellItem **array;
    HRESULT ret = E_FAIL;
    UINT i;

    TRACE("%p, %p, %d, %p, %p\n", pidlParent, psf, cidl, ppidl, ppsiItemArray);

    if (!ppsiItemArray)
        return E_POINTER;
    *ppsiItemArray = NULL;

    if(!pidlParent && !psf)
        return E_POINTER;

    if(!ppidl)
        return E_INVALIDARG;

    array = calloc(cidl, sizeof(IShellItem*));
    if(!array)
        return E_OUTOFMEMORY;

    for(i = 0; i < cidl; i++)
    {
        if (!ppidl[i])
        {
            ret = E_INVALIDARG;
            break;
        }
        ret = SHCreateShellItem(pidlParent, psf, ppidl[i], &array[i]);
        if(FAILED(ret)) break;
    }

    if(SUCCEEDED(ret))
    {
        ret = create_shellitemarray(array, cidl, ppsiItemArray);
    }

    if(FAILED(ret))
    {
        for(i = 0; i < cidl; i++)
            if(array[i]) IShellItem_Release(array[i]);
    }
    free(array);
    return ret;
}

HRESULT WINAPI SHCreateShellItemArrayFromShellItem(IShellItem *item, REFIID riid, void **ppv)
{
    IShellItemArray *array;
    HRESULT ret;

    TRACE("%p, %s, %p\n", item, shdebugstr_guid(riid), ppv);

    if (!ppv)
        return E_POINTER;
    *ppv = NULL;
    if (!item)
        return E_INVALIDARG;

    IShellItem_AddRef(item);
    ret = create_shellitemarray(&item, 1, &array);
    if(FAILED(ret))
    {
        IShellItem_Release(item);
        return ret;
    }

    ret = IShellItemArray_QueryInterface(array, riid, ppv);
    IShellItemArray_Release(array);
    return ret;
}

HRESULT WINAPI SHCreateShellItemArrayFromDataObject(IDataObject *pdo, REFIID riid, void **ppv)
{
    IShellItemArray *psia;
    FORMATETC fmt;
    STGMEDIUM medium;
    HRESULT ret;

    TRACE("%p, %s, %p\n", pdo, shdebugstr_guid(riid), ppv);

    if(!pdo)
        return E_INVALIDARG;

    *ppv = NULL;

    fmt.cfFormat = RegisterClipboardFormatW(CFSTR_SHELLIDLISTW);
    fmt.ptd = NULL;
    fmt.dwAspect = DVASPECT_CONTENT;
    fmt.lindex = -1;
    fmt.tymed = TYMED_HGLOBAL;

    ret = IDataObject_GetData(pdo, &fmt, &medium);
    if(SUCCEEDED(ret))
    {
        LPIDA pida = GlobalLock(medium.hGlobal);
        LPCITEMIDLIST parent_pidl;
        LPCITEMIDLIST *children;
        UINT i;
        TRACE("Converting %d objects.\n", pida->cidl);

        parent_pidl = (LPCITEMIDLIST) ((LPBYTE)pida+pida->aoffset[0]);

        children = malloc(sizeof(const ITEMIDLIST*) * pida->cidl);
        for(i = 0; i < pida->cidl; i++)
            children[i] = (LPCITEMIDLIST) ((LPBYTE)pida+pida->aoffset[i+1]);

        ret = SHCreateShellItemArray(parent_pidl, NULL, pida->cidl, children, &psia);

        free(children);

        GlobalUnlock(medium.hGlobal);
        GlobalFree(medium.hGlobal);
    }

    if(SUCCEEDED(ret))
    {
        ret = IShellItemArray_QueryInterface(psia, riid, ppv);
        IShellItemArray_Release(psia);
    }

    if (FAILED(ret))
        ret = shellitem_get_hdrop_data_object_array(pdo, riid, ppv);

    if (FAILED(ret))
        ret = shellitem_get_single_item_data_object_array(pdo, shellitem_get_filename_data_object_item, riid, ppv);

    if (FAILED(ret))
        ret = shellitem_get_single_item_data_object_array(pdo, shellitem_get_url_data_object_item, riid, ppv);

    return ret;
}

HRESULT WINAPI SHCreateShellItemArrayFromIDLists(UINT cidl,
                                                 PCIDLIST_ABSOLUTE_ARRAY pidl_array,
                                                 IShellItemArray **psia)
{
    IShellItem **array;
    HRESULT ret;
    UINT i;
    TRACE("%d, %p, %p\n", cidl, pidl_array, psia);

    if (!psia)
        return E_POINTER;
    *psia = NULL;

    if(cidl == 0 || !pidl_array)
        return E_INVALIDARG;

    array = calloc(cidl, sizeof(IShellItem*));
    if(!array)
        return E_OUTOFMEMORY;

    for(i = 0; i < cidl; i++)
    {
        if (!pidl_array[i])
        {
            ret = E_INVALIDARG;
            break;
        }
        ret = SHCreateShellItem(NULL, NULL, pidl_array[i], &array[i]);
        if(FAILED(ret))
            break;
    }

    if(SUCCEEDED(ret))
    {
        ret = create_shellitemarray(array, cidl, psia);
    }

    if(FAILED(ret))
    {
        for(i = 0; i < cidl; i++)
            if(array[i]) IShellItem_Release(array[i]);
        *psia = NULL;
    }
    free(array);
    return ret;
}

HRESULT WINAPI SHGetPropertyStoreFromParsingName(const WCHAR *path, IBindCtx *pbc, GETPROPERTYSTOREFLAGS flags,
    REFIID riid, void **ppv)
{
    IShellItem2 *item;
    HRESULT hr;

    TRACE("(%s %p %#x %p %p)\n", debugstr_w(path), pbc, flags, riid, ppv);

    hr = SHCreateItemFromParsingName(path, pbc, &IID_IShellItem2, (void **)&item);
    if(SUCCEEDED(hr))
    {
        hr = IShellItem2_GetPropertyStore(item, flags, riid, ppv);
        IShellItem2_Release(item);
    }

    return hr;
}

static HRESULT WINAPI CustomDestinationList_QueryInterface(ICustomDestinationList *iface, REFIID riid, void **obj)
{
    CustomDestinationList *This = impl_from_ICustomDestinationList(iface);

    TRACE("(%p, %s, %p)\n", This, debugstr_guid(riid), obj);

    if (IsEqualIID(&IID_ICustomDestinationList, riid) || IsEqualIID(&IID_IUnknown, riid))
    {
        *obj = &This->ICustomDestinationList_iface;
    }
    else {
        WARN("Unsupported interface %s.\n", shdebugstr_guid(riid));
        *obj = NULL;
        return E_NOINTERFACE;
    }

    IUnknown_AddRef((IUnknown*)*obj);
    return S_OK;
}

static ULONG WINAPI CustomDestinationList_AddRef(ICustomDestinationList *iface)
{
    CustomDestinationList *This = impl_from_ICustomDestinationList(iface);
    ULONG ref = InterlockedIncrement(&This->ref);

    TRACE("(%p), new refcount=%li\n", This, ref);

    return ref;
}

static ULONG WINAPI CustomDestinationList_Release(ICustomDestinationList *iface)
{
    CustomDestinationList *This = impl_from_ICustomDestinationList(iface);
    ULONG ref = InterlockedDecrement(&This->ref);

    TRACE("(%p), new refcount=%li\n", This, ref);

    if (ref == 0)
        free(This);

    return ref;
}

static HRESULT WINAPI CustomDestinationList_SetAppID(ICustomDestinationList *iface, const WCHAR *appid)
{
    CustomDestinationList *This = impl_from_ICustomDestinationList(iface);

    TRACE("%p (%s)\n", This, debugstr_w(appid));
    return S_OK;
}

static HRESULT WINAPI CustomDestinationList_BeginList(ICustomDestinationList *iface, UINT *min_slots, REFIID riid, void **obj)
{
    CustomDestinationList *This = impl_from_ICustomDestinationList(iface);
    HRESULT hr;

    TRACE("%p (%p %s %p)\n", This, min_slots, debugstr_guid(riid), obj);
    if (min_slots) *min_slots = 0;
    if (!obj) return E_POINTER;

    hr = EnumerableObjectCollection_Constructor(NULL, riid, obj);
    if (FAILED(hr))
        *obj = NULL;
    return hr;
}

static HRESULT WINAPI CustomDestinationList_AppendCategory(ICustomDestinationList *iface, const WCHAR *category, IObjectArray *array)
{
    CustomDestinationList *This = impl_from_ICustomDestinationList(iface);

    TRACE("%p (%s %p)\n", This, debugstr_w(category), array);
    return S_OK;
}

static HRESULT WINAPI CustomDestinationList_AppendKnownCategory(ICustomDestinationList *iface, KNOWNDESTCATEGORY category)
{
    CustomDestinationList *This = impl_from_ICustomDestinationList(iface);

    TRACE("%p (%d)\n", This, category);
    return S_OK;
}

static HRESULT WINAPI CustomDestinationList_AddUserTasks(ICustomDestinationList *iface, IObjectArray *tasks)
{
    CustomDestinationList *This = impl_from_ICustomDestinationList(iface);

    TRACE("%p (%p)\n", This, tasks);
    return S_OK;
}

static HRESULT WINAPI CustomDestinationList_CommitList(ICustomDestinationList *iface)
{
    CustomDestinationList *This = impl_from_ICustomDestinationList(iface);

    TRACE("%p\n", This);
    return S_OK;
}

static HRESULT WINAPI CustomDestinationList_GetRemovedDestinations(ICustomDestinationList *iface, REFIID riid, void **obj)
{
    CustomDestinationList *This = impl_from_ICustomDestinationList(iface);

    TRACE("%p (%s %p)\n", This, debugstr_guid(riid), obj);
    if (!obj) return E_POINTER;
    return EnumerableObjectCollection_Constructor(NULL, riid, obj);
}

static HRESULT WINAPI CustomDestinationList_DeleteList(ICustomDestinationList *iface, const WCHAR *appid)
{
    CustomDestinationList *This = impl_from_ICustomDestinationList(iface);

    TRACE("%p (%s)\n", This, debugstr_w(appid));
    return S_OK;
}

static HRESULT WINAPI CustomDestinationList_AbortList(ICustomDestinationList *iface)
{
    CustomDestinationList *This = impl_from_ICustomDestinationList(iface);

    TRACE("%p\n", This);
    return S_OK;
}

static const ICustomDestinationListVtbl CustomDestinationListVtbl =
{
    CustomDestinationList_QueryInterface,
    CustomDestinationList_AddRef,
    CustomDestinationList_Release,
    CustomDestinationList_SetAppID,
    CustomDestinationList_BeginList,
    CustomDestinationList_AppendCategory,
    CustomDestinationList_AppendKnownCategory,
    CustomDestinationList_AddUserTasks,
    CustomDestinationList_CommitList,
    CustomDestinationList_GetRemovedDestinations,
    CustomDestinationList_DeleteList,
    CustomDestinationList_AbortList
};

HRESULT WINAPI CustomDestinationList_Constructor(IUnknown *outer, REFIID riid, void **obj)
{
    CustomDestinationList *list;
    HRESULT hr;

    TRACE("%p %s %p\n", outer, debugstr_guid(riid), obj);

    if (outer)
        return CLASS_E_NOAGGREGATION;

    if(!(list = malloc(sizeof(*list))))
        return E_OUTOFMEMORY;

    list->ICustomDestinationList_iface.lpVtbl = &CustomDestinationListVtbl;
    list->ref = 1;

    hr = ICustomDestinationList_QueryInterface(&list->ICustomDestinationList_iface, riid, obj);
    ICustomDestinationList_Release(&list->ICustomDestinationList_iface);
    return hr;
}

HRESULT WINAPI SHSetTemporaryPropertyForItem(IShellItem *psi, REFPROPERTYKEY propkey, REFPROPVARIANT propvar)
{
    TRACE("%p %p %p\n", psi, propkey, propvar);
    return S_OK;
}
