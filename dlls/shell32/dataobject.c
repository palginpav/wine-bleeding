/*
 *	IEnumFORMATETC, IDataObject
 *
 * selecting and dropping objects within the shell and/or common dialogs
 *
 *	Copyright 1998, 1999	<juergen.schmied@metronet.de>
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
#include <string.h>

#define COBJMACROS
#include "windef.h"
#include "wingdi.h"
#include "pidl.h"
#include "winerror.h"
#include "shell32_main.h"
#include "wine/debug.h"

WINE_DEFAULT_DEBUG_CHANNEL(shell);

/***********************************************************************
*   IEnumFORMATETC implementation
*/

typedef struct
{
    /* IUnknown fields */
    IEnumFORMATETC IEnumFORMATETC_iface;
    LONG           ref;
    /* IEnumFORMATETC fields */
    UINT        posFmt;
    UINT        countFmt;
    LPFORMATETC pFmt;
} IEnumFORMATETCImpl;

static inline IEnumFORMATETCImpl *impl_from_IEnumFORMATETC(IEnumFORMATETC *iface)
{
	return CONTAINING_RECORD(iface, IEnumFORMATETCImpl, IEnumFORMATETC_iface);
}

static HRESULT WINAPI IEnumFORMATETC_fnQueryInterface(
               LPENUMFORMATETC iface, REFIID riid, LPVOID* ppvObj)
{
	IEnumFORMATETCImpl *This = impl_from_IEnumFORMATETC(iface);
	TRACE("(%p)->(\n\tIID:\t%s,%p)\n",This,debugstr_guid(riid),ppvObj);

        if (!ppvObj) return E_POINTER;
	*ppvObj = NULL;

	if(IsEqualIID(riid, &IID_IUnknown) ||
           IsEqualIID(riid, &IID_IEnumFORMATETC))
	{
	  *ppvObj = &This->IEnumFORMATETC_iface;
	}

	if(*ppvObj)
	{
	  IUnknown_AddRef((IUnknown*)(*ppvObj));
	  TRACE("-- Interface: (%p)->(%p)\n",ppvObj,*ppvObj);
	  return S_OK;
	}
	TRACE("-- Interface: E_NOINTERFACE\n");
	return E_NOINTERFACE;
}

static ULONG WINAPI IEnumFORMATETC_fnAddRef(LPENUMFORMATETC iface)
{
	IEnumFORMATETCImpl *This = impl_from_IEnumFORMATETC(iface);
	ULONG refCount = InterlockedIncrement(&This->ref);

	TRACE("(%p)->(count=%lu)\n", This, refCount - 1);

	return refCount;
}

static ULONG WINAPI IEnumFORMATETC_fnRelease(LPENUMFORMATETC iface)
{
	IEnumFORMATETCImpl *This = impl_from_IEnumFORMATETC(iface);
	ULONG refCount = InterlockedDecrement(&This->ref);

	TRACE("(%p)->(%lu)\n", This, refCount + 1);

	if (!refCount)
	{
	  TRACE(" destroying IEnumFORMATETC(%p)\n",This);
	  SHFree (This->pFmt);
	  free(This);
	}
	return refCount;
}

static HRESULT WINAPI IEnumFORMATETC_fnNext(LPENUMFORMATETC iface, ULONG celt, FORMATETC *rgelt, ULONG *pceltFethed)
{
	IEnumFORMATETCImpl *This = impl_from_IEnumFORMATETC(iface);
	UINT i;

	TRACE("(%p)->(%lu,%p)\n", This, celt, rgelt);

	if(!This->pFmt)return S_FALSE;
	if(!rgelt) return E_INVALIDARG;
	if (celt > 1 && !pceltFethed) return E_INVALIDARG;
	if (pceltFethed)  *pceltFethed = 0;

	for(i = 0; This->posFmt < This->countFmt && celt > i; i++)
   	{
	  *rgelt++ = This->pFmt[This->posFmt++];
	}

	if (pceltFethed) *pceltFethed = i;

	return ((i == celt) ? S_OK : S_FALSE);
}

static HRESULT WINAPI IEnumFORMATETC_fnSkip(LPENUMFORMATETC iface, ULONG celt)
{
	IEnumFORMATETCImpl *This = impl_from_IEnumFORMATETC(iface);
        UINT remaining;
	TRACE("(%p)->(num=%lu)\n", This, celt);

        if (This->posFmt >= This->countFmt) return S_FALSE;

        remaining = This->countFmt - This->posFmt;
        if (celt >= remaining)
        {
            This->posFmt = This->countFmt;
            return S_FALSE;
        }

	This->posFmt += celt;
	return S_OK;
}

static HRESULT WINAPI IEnumFORMATETC_fnReset(LPENUMFORMATETC iface)
{
	IEnumFORMATETCImpl *This = impl_from_IEnumFORMATETC(iface);
	TRACE("(%p)->()\n", This);

        This->posFmt = 0;
        return S_OK;
}

static HRESULT WINAPI IEnumFORMATETC_fnClone(LPENUMFORMATETC iface, LPENUMFORMATETC* ppenum)
{
	IEnumFORMATETCImpl *This = impl_from_IEnumFORMATETC(iface);
	TRACE("(%p)->(ppenum=%p)\n", This, ppenum);

	if (!ppenum) return E_INVALIDARG;
	*ppenum = IEnumFORMATETC_Constructor(This->countFmt, This->pFmt);
        if (!*ppenum) return E_OUTOFMEMORY;

        IEnumFORMATETC_fnSkip(*ppenum, This->posFmt);
	return S_OK;
}

static const IEnumFORMATETCVtbl efvt =
{
    IEnumFORMATETC_fnQueryInterface,
    IEnumFORMATETC_fnAddRef,
    IEnumFORMATETC_fnRelease,
    IEnumFORMATETC_fnNext,
    IEnumFORMATETC_fnSkip,
    IEnumFORMATETC_fnReset,
    IEnumFORMATETC_fnClone
};

LPENUMFORMATETC IEnumFORMATETC_Constructor(UINT cfmt, const FORMATETC afmt[])
{
    IEnumFORMATETCImpl* ef;
    DWORD size=cfmt * sizeof(FORMATETC);

    ef = calloc(1, sizeof(*ef));
    if (!ef) return NULL;

    ef->ref = 1;
    ef->IEnumFORMATETC_iface.lpVtbl = &efvt;
    ef->countFmt = cfmt;

    if (cfmt)
    {
        ef->pFmt = SHAlloc(size);
        if (!ef->pFmt)
        {
            free(ef);
            return NULL;
        }

        memcpy(ef->pFmt, afmt, size);
    }

    TRACE("(%p)->(%u,%p)\n",ef, cfmt, afmt);
    return &ef->IEnumFORMATETC_iface;
}

struct data
{
    UINT cf;
    HGLOBAL global;
};

typedef struct
{
    IDataObject IDataObject_iface;
    LONG ref;

    struct data *data;
    size_t data_count;
} IDataObjectImpl;

static inline IDataObjectImpl *impl_from_IDataObject(IDataObject *iface)
{
	return CONTAINING_RECORD(iface, IDataObjectImpl, IDataObject_iface);
}

static void release_data_entries(struct data *data, size_t count)
{
    if (!data) return;

    for (size_t i = 0; i < count; ++i)
        GlobalFree(data[i].global);
    free(data);
}

static BOOL data_object_format_matches(const struct data *data, const FORMATETC *format)
{
    return data->cf == format->cfFormat && !format->ptd
            && format->dwAspect == DVASPECT_CONTENT && format->lindex == -1;
}

static HRESULT data_object_validate_format(const FORMATETC *format)
{
    if (format->ptd)
        return DV_E_DVTARGETDEVICE;
    if (format->dwAspect != DVASPECT_CONTENT)
        return DV_E_DVASPECT;
    if (format->lindex != -1)
        return DV_E_LINDEX;
    if (!(format->tymed & TYMED_HGLOBAL))
        return DV_E_TYMED;
    return S_OK;
}

static HGLOBAL render_preferred_drop_effect(DWORD effect)
{
    DWORD *value;
    HGLOBAL global;

    if (!(global = GlobalAlloc(GMEM_MOVEABLE, sizeof(*value))))
        return NULL;

    value = GlobalLock(global);
    if (!value)
    {
        GlobalFree(global);
        return NULL;
    }

    *value = effect;
    GlobalUnlock(global);
    return global;
}

static HGLOBAL duplicate_hglobal(HGLOBAL source)
{
    size_t size;
    HGLOBAL copy;
    const void *src;
    void *dst;

    if (!source) return NULL;

    size = GlobalSize(source);
    if (!(copy = GlobalAlloc(GMEM_MOVEABLE, size)))
        return NULL;

    src = GlobalLock(source);
    dst = GlobalLock(copy);
    if (!src || !dst)
    {
        if (src) GlobalUnlock(source);
        if (dst) GlobalUnlock(copy);
        GlobalFree(copy);
        return NULL;
    }

    memcpy(dst, src, size);
    GlobalUnlock(source);
    GlobalUnlock(copy);
    return copy;
}

/***************************************************************************
*  IDataObject_QueryInterface
*/
static HRESULT WINAPI IDataObject_fnQueryInterface(IDataObject *iface, REFIID riid, LPVOID * ppvObj)
{
	IDataObjectImpl *This = impl_from_IDataObject(iface);
	TRACE("(%p)->(\n\tIID:\t%s,%p)\n",This,debugstr_guid(riid),ppvObj);

        if (!ppvObj) return E_POINTER;
	*ppvObj = NULL;

	if(IsEqualIID(riid, &IID_IUnknown) ||
           IsEqualIID(riid, &IID_IDataObject))
	{
	  *ppvObj = &This->IDataObject_iface;
	}

	if(*ppvObj)
	{
	  IUnknown_AddRef((IUnknown*)*ppvObj);
	  TRACE("-- Interface: (%p)->(%p)\n",ppvObj,*ppvObj);
	  return S_OK;
	}
	TRACE("-- Interface: E_NOINTERFACE\n");
	return E_NOINTERFACE;
}

/**************************************************************************
*  IDataObject_AddRef
*/
static ULONG WINAPI IDataObject_fnAddRef(IDataObject *iface)
{
	IDataObjectImpl *This = impl_from_IDataObject(iface);
	ULONG refCount = InterlockedIncrement(&This->ref);

	TRACE("(%p)->(count=%lu)\n", This, refCount - 1);

	return refCount;
}

/**************************************************************************
*  IDataObject_Release
*/
static ULONG WINAPI IDataObject_fnRelease(IDataObject *iface)
{
    IDataObjectImpl *obj = impl_from_IDataObject(iface);
    ULONG refcount = InterlockedDecrement(&obj->ref);

    TRACE("%p decreasing refcount to %lu.\n", obj, refcount);

    if (!refcount)
    {
        release_data_entries(obj->data, obj->data_count);
        free(obj);
    }
    return refcount;
}

/**************************************************************************
* IDataObject_fnGetData
*/
static HRESULT WINAPI IDataObject_fnGetData(IDataObject *iface, FORMATETC *format, STGMEDIUM *medium)
{
    IDataObjectImpl *obj = impl_from_IDataObject(iface);
    HRESULT hr;

    TRACE("iface %p, format %p, medium %p.\n", iface, format, medium);

    if (!format || !medium) return E_INVALIDARG;
    memset(medium, 0, sizeof(*medium));

    hr = data_object_validate_format(format);
    if (FAILED(hr))
        return hr;

    for (size_t i = 0; i < obj->data_count; ++i)
    {
        if (data_object_format_matches(&obj->data[i], format))
        {
            HGLOBAL src_global = obj->data[i].global;
            size_t size = GlobalSize(src_global);
            HGLOBAL dst_global;
            const void *src;
            void *dst;

            if (!(dst_global = GlobalAlloc(GMEM_MOVEABLE, size)))
                return E_OUTOFMEMORY;
            src = GlobalLock(src_global);
            dst = GlobalLock(dst_global);
            memcpy(dst, src, size);
            GlobalUnlock(src_global);
            GlobalUnlock(dst_global);

            medium->tymed = TYMED_HGLOBAL;
            medium->pUnkForRelease = NULL;
            medium->hGlobal = dst_global;
            return S_OK;
        }
    }

    return DV_E_FORMATETC;
}

static HRESULT WINAPI IDataObject_fnGetDataHere(IDataObject *iface, LPFORMATETC pformatetc, STGMEDIUM *pmedium)
{
	IDataObjectImpl *This = impl_from_IDataObject(iface);
        HRESULT hr;
	TRACE("(%p)->(%p,%p)\n", This, pformatetc, pmedium);

        if (!pformatetc || !pmedium) return E_INVALIDARG;
        if (pmedium->tymed != TYMED_HGLOBAL) return DV_E_TYMED;
        if (!pmedium->hGlobal) return STG_E_MEDIUMFULL;

        hr = data_object_validate_format(pformatetc);
        if (FAILED(hr))
            return hr;

        for (size_t i = 0; i < This->data_count; ++i)
        {
            if (data_object_format_matches(&This->data[i], pformatetc))
            {
                HGLOBAL src_global = This->data[i].global;
                size_t size = GlobalSize(src_global);
                size_t dst_size = GlobalSize(pmedium->hGlobal);
                const void *src;
                void *dst;

                if (dst_size < size) return STG_E_MEDIUMFULL;

                src = GlobalLock(src_global);
                dst = GlobalLock(pmedium->hGlobal);
                if (!src || !dst)
                {
                    if (src) GlobalUnlock(src_global);
                    if (dst) GlobalUnlock(pmedium->hGlobal);
                    return STG_E_MEDIUMFULL;
                }

                memcpy(dst, src, size);
                GlobalUnlock(src_global);
                GlobalUnlock(pmedium->hGlobal);
                pmedium->pUnkForRelease = NULL;
                return S_OK;
            }
        }

	return DV_E_FORMATETC;
}

static HRESULT WINAPI IDataObject_fnQueryGetData(IDataObject *iface, FORMATETC *format)
{
    IDataObjectImpl *obj = impl_from_IDataObject(iface);
    HRESULT hr;

    TRACE("iface %p, format %p.\n", iface, format);

    if (!format) return E_INVALIDARG;
    hr = data_object_validate_format(format);
    if (FAILED(hr))
        return hr;

    for (size_t i = 0; i < obj->data_count; ++i)
    {
        if (data_object_format_matches(&obj->data[i], format))
            return S_OK;
    }

    return DV_E_FORMATETC;
}

static HRESULT WINAPI IDataObject_fnGetCanonicalFormatEtc(IDataObject *iface, LPFORMATETC pformatectIn, LPFORMATETC pformatetcOut)
{
	IDataObjectImpl *This = impl_from_IDataObject(iface);
	TRACE("(%p)->(%p,%p)\n", This, pformatectIn, pformatetcOut);

        if (!pformatectIn || !pformatetcOut) return E_INVALIDARG;

        *pformatetcOut = *pformatectIn;
        pformatetcOut->ptd = NULL;
	return DATA_S_SAMEFORMATETC;
}

static HRESULT WINAPI IDataObject_fnSetData(IDataObject *iface,
        FORMATETC *format, STGMEDIUM *medium, BOOL release)
{
    IDataObjectImpl *obj = impl_from_IDataObject(iface);
    struct data *new_array;
    HGLOBAL global;

    TRACE("iface %p, format %p, medium %p, release %d.\n", iface, format, medium, release);

    if (!format || !medium) return E_INVALIDARG;

    if (!(format->tymed & TYMED_HGLOBAL))
        return DV_E_TYMED;

    if (medium->tymed != TYMED_HGLOBAL)
        return DV_E_TYMED;

    if (medium->pUnkForRelease)
        FIXME("Ignoring IUnknown %p.\n", medium->pUnkForRelease);

    if (!medium->hGlobal)
        return E_INVALIDARG;
    if (format->ptd)
        return DV_E_DVTARGETDEVICE;
    if (format->dwAspect != DVASPECT_CONTENT)
        return DV_E_DVASPECT;
    if (format->lindex != -1)
        return DV_E_LINDEX;

    if (release) global = medium->hGlobal;
    else if (!(global = duplicate_hglobal(medium->hGlobal))) return E_OUTOFMEMORY;

    for (size_t i = 0; i < obj->data_count; ++i)
    {
        if (obj->data[i].cf == format->cfFormat)
        {
            GlobalFree(obj->data[i].global);
            obj->data[i].global = global;
            return S_OK;
        }
    }

    if (!(new_array = realloc(obj->data, (obj->data_count + 1) * sizeof(*obj->data))))
    {
        if (!release) GlobalFree(global);
        return E_OUTOFMEMORY;
    }
    obj->data = new_array;
    obj->data[obj->data_count].cf = format->cfFormat;
    obj->data[obj->data_count].global = global;
    ++obj->data_count;
    return S_OK;
}

static HRESULT WINAPI IDataObject_fnEnumFormatEtc(IDataObject *iface, DWORD direction, IEnumFORMATETC **out)
{
    IDataObjectImpl *obj = impl_from_IDataObject(iface);
    FORMATETC *formats;

    TRACE("iface %p, direction %#lx, out %p.\n", iface, direction, out);

    if (!out) return E_POINTER;
    *out = NULL;

    if (!(formats = calloc(obj->data_count, sizeof(*formats))))
        return E_OUTOFMEMORY;
    for (size_t i = 0; i < obj->data_count; ++i)
        InitFormatEtc(formats[i], obj->data[i].cf, TYMED_HGLOBAL);

    if (!(*out = IEnumFORMATETC_Constructor(obj->data_count, formats)))
    {
        free(formats);
        return E_OUTOFMEMORY;
    }
    free(formats);
    return S_OK;
}

static HRESULT WINAPI IDataObject_fnDAdvise(IDataObject *iface, FORMATETC *pformatetc, DWORD advf, IAdviseSink *pAdvSink, DWORD *pdwConnection)
{
	IDataObjectImpl *This = impl_from_IDataObject(iface);
	TRACE("(%p)->(%p,%#lx,%p,%p)\n", This, pformatetc, advf, pAdvSink, pdwConnection);

        if (pdwConnection) *pdwConnection = 0;
	return OLE_E_ADVISENOTSUPPORTED;
}
static HRESULT WINAPI IDataObject_fnDUnadvise(IDataObject *iface, DWORD dwConnection)
{
	IDataObjectImpl *This = impl_from_IDataObject(iface);
	TRACE("(%p)->(%#lx)\n", This, dwConnection);
	return OLE_E_ADVISENOTSUPPORTED;
}
static HRESULT WINAPI IDataObject_fnEnumDAdvise(IDataObject *iface, IEnumSTATDATA **ppenumAdvise)
{
	IDataObjectImpl *This = impl_from_IDataObject(iface);
	TRACE("(%p)->(%p)\n", This, ppenumAdvise);

        if (ppenumAdvise) *ppenumAdvise = NULL;
	return OLE_E_ADVISENOTSUPPORTED;
}

static const IDataObjectVtbl dtovt =
{
	IDataObject_fnQueryInterface,
	IDataObject_fnAddRef,
	IDataObject_fnRelease,
	IDataObject_fnGetData,
	IDataObject_fnGetDataHere,
	IDataObject_fnQueryGetData,
	IDataObject_fnGetCanonicalFormatEtc,
	IDataObject_fnSetData,
	IDataObject_fnEnumFormatEtc,
	IDataObject_fnDAdvise,
	IDataObject_fnDUnadvise,
	IDataObject_fnEnumDAdvise
};

/**************************************************************************
*  IDataObject_Constructor
*/
IDataObject *IDataObject_Constructor(HWND hwnd, const ITEMIDLIST *root_pidl,
        const ITEMIDLIST **pidls, UINT pidl_count)
{
    IDataObjectImpl *obj;

    if (!(obj = calloc(1, sizeof(*obj))))
        return NULL;

    obj->ref = 1;
    obj->IDataObject_iface.lpVtbl = &dtovt;
    obj->data = calloc(5, sizeof(*obj->data));
    if (!obj->data)
    {
        free(obj);
        return NULL;
    }

    obj->data[0].cf = RegisterClipboardFormatW(CFSTR_SHELLIDLISTW);
    obj->data[0].global = RenderSHELLIDLIST(root_pidl, pidls, pidl_count);
    obj->data[1].cf = CF_HDROP;
    obj->data[1].global = RenderHDROP(root_pidl, pidls, pidl_count);
    obj->data[2].cf = RegisterClipboardFormatA(CFSTR_FILENAMEA);
    obj->data[2].global = RenderFILENAMEA(root_pidl, pidls, pidl_count);
    obj->data[3].cf = RegisterClipboardFormatW(CFSTR_FILENAMEW);
    obj->data[3].global = RenderFILENAMEW(root_pidl, pidls, pidl_count);
    obj->data[4].cf = RegisterClipboardFormatW(CFSTR_PREFERREDDROPEFFECTW);
    obj->data[4].global = render_preferred_drop_effect(DROPEFFECT_LINK);
    obj->data_count = 5;

    for (size_t i = 0; i < obj->data_count; ++i)
    {
        if (!obj->data[i].global)
        {
            release_data_entries(obj->data, obj->data_count);
            free(obj);
            return NULL;
        }
    }

    TRACE("Created data object %p.\n", obj);
    return &obj->IDataObject_iface;
}
