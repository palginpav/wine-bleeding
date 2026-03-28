/*
 * Restart Manager implementation
 *
 * Copyright 2010 Louis Lenders
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

#include "windef.h"
#include "winbase.h"
#include "ntstatus.h"
#define WIN32_NO_STATUS
#include "winternl.h"
#include "winsvc.h"
#include "winuser.h"
#include "tlhelp32.h"
#include "objbase.h"
#include "wine/debug.h"

#include "restartmanager.h"

WINE_DEFAULT_DEBUG_CHANNEL(rstrtmgr);

#define RM_MAX_SESSIONS 64
#define RM_SHUTDOWN_TIMEOUT 5000

struct rm_filter
{
    WCHAR *module_name;
    RM_UNIQUE_PROCESS *process;
    WCHAR *service_name;
    RM_FILTER_ACTION action;
    struct rm_filter *next;
};

struct rm_session
{
    BOOL in_use;
    WCHAR key[CCH_RM_SESSION_KEY + 1];
    CRITICAL_SECTION cs;

    /* registered resources */
    WCHAR **files;
    UINT file_count;
    UINT file_capacity;

    RM_UNIQUE_PROCESS *processes;
    UINT process_count;
    UINT process_capacity;

    WCHAR **services;
    UINT service_count;
    UINT service_capacity;

    /* affected apps found by RmGetList */
    RM_PROCESS_INFO *affected;
    UINT affected_count;
    DWORD reboot_reasons;

    /* filters */
    struct rm_filter *filters;

    /* processes shut down by RmShutdown (for RmRestart) */
    RM_PROCESS_INFO *shutdown_apps;
    UINT shutdown_count;
};

static struct rm_session sessions[RM_MAX_SESSIONS];
static CRITICAL_SECTION sessions_cs;
static CRITICAL_SECTION_DEBUG sessions_cs_debug =
{
    0, 0, &sessions_cs,
    { &sessions_cs_debug.ProcessLocksList, &sessions_cs_debug.ProcessLocksList },
    0, 0, { (DWORD_PTR)(__FILE__ ": sessions_cs") }
};
static CRITICAL_SECTION sessions_cs = { &sessions_cs_debug, -1, 0, 0, 0, 0 };

static struct rm_session *get_session(DWORD handle)
{
    struct rm_session *session;
    if (handle >= RM_MAX_SESSIONS) return NULL;
    session = &sessions[handle];
    if (!session->in_use) return NULL;
    return session;
}

static void free_string_array(WCHAR **arr, UINT count)
{
    UINT i;
    for (i = 0; i < count; i++)
        free(arr[i]);
    free(arr);
}

static void free_filters(struct rm_filter *f)
{
    while (f)
    {
        struct rm_filter *next = f->next;
        free(f->module_name);
        free(f->process);
        free(f->service_name);
        free(f);
        f = next;
    }
}

static void session_cleanup(struct rm_session *session)
{
    free_string_array(session->files, session->file_count);
    free(session->processes);
    free_string_array(session->services, session->service_count);
    free(session->affected);
    free_filters(session->filters);
    free(session->shutdown_apps);
    DeleteCriticalSection(&session->cs);
    memset(session, 0, sizeof(*session));
}

static WCHAR *wstr_dup(const WCHAR *src)
{
    SIZE_T len;
    WCHAR *dst;
    if (!src) return NULL;
    len = (lstrlenW(src) + 1) * sizeof(WCHAR);
    dst = malloc(len);
    if (dst) memcpy(dst, src, len);
    return dst;
}

static BOOL add_file(struct rm_session *session, const WCHAR *path)
{
    if (session->file_count >= session->file_capacity)
    {
        UINT new_cap = session->file_capacity ? session->file_capacity * 2 : 16;
        WCHAR **new_arr = realloc(session->files, new_cap * sizeof(WCHAR *));
        if (!new_arr) return FALSE;
        session->files = new_arr;
        session->file_capacity = new_cap;
    }
    session->files[session->file_count] = wstr_dup(path);
    if (!session->files[session->file_count]) return FALSE;
    session->file_count++;
    return TRUE;
}

static BOOL add_process(struct rm_session *session, const RM_UNIQUE_PROCESS *proc)
{
    if (session->process_count >= session->process_capacity)
    {
        UINT new_cap = session->process_capacity ? session->process_capacity * 2 : 16;
        RM_UNIQUE_PROCESS *new_arr = realloc(session->processes, new_cap * sizeof(RM_UNIQUE_PROCESS));
        if (!new_arr) return FALSE;
        session->processes = new_arr;
        session->process_capacity = new_cap;
    }
    session->processes[session->process_count++] = *proc;
    return TRUE;
}

static BOOL add_service(struct rm_session *session, const WCHAR *name)
{
    if (session->service_count >= session->service_capacity)
    {
        UINT new_cap = session->service_capacity ? session->service_capacity * 2 : 16;
        WCHAR **new_arr = realloc(session->services, new_cap * sizeof(WCHAR *));
        if (!new_arr) return FALSE;
        session->services = new_arr;
        session->service_capacity = new_cap;
    }
    session->services[session->service_count] = wstr_dup(name);
    if (!session->services[session->service_count]) return FALSE;
    session->service_count++;
    return TRUE;
}

/* Add an affected app to the list, growing as needed */
static BOOL add_affected(struct rm_session *session, const RM_PROCESS_INFO *info)
{
    RM_PROCESS_INFO *new_arr;
    new_arr = realloc(session->affected, (session->affected_count + 1) * sizeof(RM_PROCESS_INFO));
    if (!new_arr) return FALSE;
    session->affected = new_arr;
    session->affected[session->affected_count++] = *info;
    return TRUE;
}

/* Check if a filter blocks shutdown/restart for a given process */
static RM_FILTER_ACTION check_filter(struct rm_session *session, const RM_PROCESS_INFO *info)
{
    struct rm_filter *f;
    for (f = session->filters; f; f = f->next)
    {
        if (f->service_name && info->strServiceShortName[0] &&
            !lstrcmpiW(f->service_name, info->strServiceShortName))
            return f->action;
        if (f->process && f->process->dwProcessId == info->Process.dwProcessId)
            return f->action;
        if (f->module_name && info->strAppName[0] &&
            !lstrcmpiW(f->module_name, info->strAppName))
            return f->action;
    }
    return RmInvalidFilterAction;
}

/* Try to get process name and fill RM_PROCESS_INFO for a given PID */
static BOOL fill_process_info(RM_PROCESS_INFO *info, DWORD pid)
{
    HANDLE process;
    WCHAR name[MAX_PATH];
    DWORD name_size = MAX_PATH;
    FILETIME creation, exit_time, kernel, user;

    memset(info, 0, sizeof(*info));
    info->Process.dwProcessId = pid;
    info->TSSessionID = RM_INVALID_TS_SESSION;

    process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return FALSE;

    if (GetProcessTimes(process, &creation, &exit_time, &kernel, &user))
        info->Process.ProcessStartTime = creation;

    if (QueryFullProcessImageNameW(process, 0, name, &name_size))
    {
        /* Extract just the filename part */
        const WCHAR *slash = wcsrchr(name, '\\');
        if (slash) slash++;
        else slash = name;
        lstrcpynW(info->strAppName, slash, CCH_RM_MAX_APP_NAME + 1);
    }

    CloseHandle(process);

    info->ApplicationType = RmMainWindow;
    info->bRestartable = FALSE;
    return TRUE;
}

/* Fill RM_PROCESS_INFO for a running service */
static BOOL fill_service_info(RM_PROCESS_INFO *info, const WCHAR *service_name,
                              SC_HANDLE scm)
{
    SC_HANDLE svc;
    SERVICE_STATUS_PROCESS ssp;
    DWORD needed;

    svc = OpenServiceW(scm, service_name, SERVICE_QUERY_STATUS);
    if (!svc) return FALSE;

    memset(info, 0, sizeof(*info));
    if (QueryServiceStatusEx(svc, SC_STATUS_PROCESS_INFO, (BYTE *)&ssp,
                             sizeof(ssp), &needed))
    {
        if (ssp.dwCurrentState == SERVICE_STOPPED)
        {
            CloseServiceHandle(svc);
            return FALSE;
        }
        info->Process.dwProcessId = ssp.dwProcessId;
        info->ApplicationType = RmService;
        lstrcpynW(info->strServiceShortName, service_name, CH_RM_MAX_SVC_NAME + 1);
        lstrcpynW(info->strAppName, service_name, CCH_RM_MAX_APP_NAME + 1);
        info->TSSessionID = RM_INVALID_TS_SESSION;
        info->bRestartable = TRUE;

        /* Get process start time */
        if (ssp.dwProcessId)
        {
            HANDLE proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, ssp.dwProcessId);
            if (proc)
            {
                FILETIME creation, exit_time, kernel, user;
                if (GetProcessTimes(proc, &creation, &exit_time, &kernel, &user))
                    info->Process.ProcessStartTime = creation;
                CloseHandle(proc);
            }
        }
    }

    CloseServiceHandle(svc);
    return TRUE;
}

/* Get file name from an NT handle via NtQueryObject(ObjectNameInformation) */
static BOOL get_handle_name(HANDLE h, WCHAR *buf, UINT buf_len)
{
    BYTE buffer[sizeof(UNICODE_STRING) + MAX_PATH * sizeof(WCHAR)];
    UNICODE_STRING *name = (UNICODE_STRING *)buffer;
    ULONG ret_len;
    NTSTATUS status;

    status = NtQueryObject(h, ObjectNameInformation, buffer, sizeof(buffer), &ret_len);
    if (status) return FALSE;
    if (!name->Length) return FALSE;

    lstrcpynW(buf, name->Buffer, min(buf_len, name->Length / sizeof(WCHAR) + 1));
    return TRUE;
}

/* Check if handle name matches any registered file (case-insensitive suffix match) */
static BOOL name_matches_file(const WCHAR *handle_name, const WCHAR *registered_file)
{
    const WCHAR *file_part;
    int handle_len, file_len;

    /* Registered file is a Win32 path like C:\foo\bar.exe
     * Handle name is an NT path like \Device\HarddiskVolume3\foo\bar.exe
     * We match by comparing the path from the first backslash after the volume prefix */

    /* Skip drive letter from registered path: "C:\foo" → "\foo" */
    if (registered_file[0] && registered_file[1] == ':')
        file_part = registered_file + 2;
    else
        file_part = registered_file;

    file_len = lstrlenW(file_part);
    handle_len = lstrlenW(handle_name);

    if (handle_len < file_len) return FALSE;

    /* Compare suffix of handle_name with file_part (case-insensitive) */
    return !lstrcmpiW(handle_name + handle_len - file_len, file_part);
}

/* Find which processes have registered files open using NtQuerySystemInformation */
static void detect_file_locks(struct rm_session *session)
{
    SYSTEM_HANDLE_INFORMATION_EX *info = NULL;
    ULONG size = 0x10000;
    NTSTATUS status;
    ULONG_PTR i;
    DWORD my_pid = GetCurrentProcessId();

    /* Allocate and query all system handles */
    for (;;)
    {
        info = malloc(size);
        if (!info) return;

        status = NtQuerySystemInformation(SystemExtendedHandleInformation, info, size, NULL);
        if (!status) break;
        free(info);
        if (status != STATUS_INFO_LENGTH_MISMATCH)
        {
            WARN("NtQuerySystemInformation failed %#lx, falling back to sharing check\n", status);
            return;
        }
        size *= 2;
        if (size > 64 * 1024 * 1024) return; /* safety limit */
    }

    TRACE("Got %Iu system handles\n", info->NumberOfHandles);

    for (i = 0; i < info->NumberOfHandles; i++)
    {
        SYSTEM_HANDLE_TABLE_ENTRY_INFO_EX *entry = &info->Handles[i];
        HANDLE dup_handle, proc_handle;
        WCHAR name_buf[MAX_PATH];
        UINT f;
        DWORD pid;
        BOOL already_listed;
        UINT a;

        pid = (DWORD)entry->UniqueProcessId;
        if (pid == my_pid) continue;
        if (pid == 0 || pid == 4) continue; /* system/idle */

        /* Only check handles with file access bits */
        if (!(entry->GrantedAccess & (FILE_READ_DATA | FILE_WRITE_DATA | FILE_APPEND_DATA)))
            continue;

        proc_handle = OpenProcess(PROCESS_DUP_HANDLE, FALSE, pid);
        if (!proc_handle) continue;

        if (!DuplicateHandle(proc_handle, (HANDLE)entry->HandleValue,
                             GetCurrentProcess(), &dup_handle, 0, FALSE,
                             DUPLICATE_SAME_ACCESS))
        {
            CloseHandle(proc_handle);
            continue;
        }

        if (get_handle_name(dup_handle, name_buf, MAX_PATH))
        {
            for (f = 0; f < session->file_count; f++)
            {
                if (name_matches_file(name_buf, session->files[f]))
                {
                    /* Check if this PID is already in our affected list */
                    already_listed = FALSE;
                    for (a = 0; a < session->affected_count; a++)
                    {
                        if (session->affected[a].Process.dwProcessId == pid)
                        {
                            already_listed = TRUE;
                            break;
                        }
                    }
                    if (!already_listed)
                    {
                        RM_PROCESS_INFO pi;
                        if (fill_process_info(&pi, pid))
                        {
                            TRACE("Process %lu (%s) holds file %s\n", pid,
                                  debugstr_w(pi.strAppName), debugstr_w(session->files[f]));
                            add_affected(session, &pi);
                        }
                    }
                    break;
                }
            }
        }

        CloseHandle(dup_handle);
        CloseHandle(proc_handle);
    }

    free(info);
}

/* Detect registered services that are currently running */
static void detect_running_services(struct rm_session *session)
{
    SC_HANDLE scm;
    UINT i;

    if (!session->service_count) return;

    scm = OpenSCManagerW(NULL, NULL, SC_MANAGER_CONNECT);
    if (!scm) return;

    for (i = 0; i < session->service_count; i++)
    {
        RM_PROCESS_INFO pi;
        if (fill_service_info(&pi, session->services[i], scm))
        {
            TRACE("Service %s is running (pid %lu)\n",
                  debugstr_w(session->services[i]), pi.Process.dwProcessId);
            add_affected(session, &pi);
        }
    }

    CloseServiceHandle(scm);
}

/* Detect registered processes that are still running */
static void detect_running_processes(struct rm_session *session)
{
    UINT i;

    for (i = 0; i < session->process_count; i++)
    {
        HANDLE proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                                  session->processes[i].dwProcessId);
        if (proc)
        {
            DWORD exit_code;
            if (GetExitCodeProcess(proc, &exit_code) && exit_code == STILL_ACTIVE)
            {
                RM_PROCESS_INFO pi;
                if (fill_process_info(&pi, session->processes[i].dwProcessId))
                {
                    TRACE("Registered process %lu still running\n",
                          session->processes[i].dwProcessId);
                    add_affected(session, &pi);
                }
            }
            CloseHandle(proc);
        }
    }
}

struct enum_windows_data
{
    DWORD pid;
    HWND hwnd;
};

static BOOL CALLBACK find_main_window(HWND hwnd, LPARAM lparam)
{
    struct enum_windows_data *data = (struct enum_windows_data *)lparam;
    DWORD wnd_pid;

    GetWindowThreadProcessId(hwnd, &wnd_pid);
    if (wnd_pid == data->pid && IsWindowVisible(hwnd) && GetWindow(hwnd, GW_OWNER) == NULL)
    {
        data->hwnd = hwnd;
        return FALSE;
    }
    return TRUE;
}

/***********************************************************************
 * RmStartSession (rstrtmgr.@)
 */
DWORD WINAPI RmStartSession(DWORD *session_handle, DWORD flags, WCHAR session_key[])
{
    DWORD i;
    GUID guid;
    struct rm_session *session;

    TRACE("(%p, %lu, %p)\n", session_handle, flags, session_key);

    if (!session_handle) return ERROR_INVALID_PARAMETER;

    EnterCriticalSection(&sessions_cs);

    for (i = 0; i < RM_MAX_SESSIONS; i++)
    {
        if (!sessions[i].in_use) break;
    }

    if (i >= RM_MAX_SESSIONS)
    {
        LeaveCriticalSection(&sessions_cs);
        return ERROR_MAX_SESSIONS_REACHED;
    }

    session = &sessions[i];
    memset(session, 0, sizeof(*session));
    session->in_use = TRUE;
    InitializeCriticalSection(&session->cs);

    /* Generate session key as GUID hex string */
    if (session_key)
    {
        if (SUCCEEDED(CoCreateGuid(&guid)))
        {
            swprintf(session->key, CCH_RM_SESSION_KEY + 1,
                     L"%08lx%04x%04x%02x%02x%02x%02x%02x%02x%02x%02x",
                     guid.Data1, guid.Data2, guid.Data3,
                     guid.Data4[0], guid.Data4[1], guid.Data4[2], guid.Data4[3],
                     guid.Data4[4], guid.Data4[5], guid.Data4[6], guid.Data4[7]);
        }
        else
        {
            /* Fallback: use session index and tick count */
            swprintf(session->key, CCH_RM_SESSION_KEY + 1,
                     L"%08lx%08lx%08lx%08lx", i, GetTickCount(),
                     GetCurrentProcessId(), GetCurrentThreadId());
        }
        memcpy(session_key, session->key, (CCH_RM_SESSION_KEY + 1) * sizeof(WCHAR));
    }

    *session_handle = i;

    LeaveCriticalSection(&sessions_cs);

    TRACE("Created session %lu, key %s\n", i, debugstr_w(session->key));
    return ERROR_SUCCESS;
}

/***********************************************************************
 * RmRegisterResources (rstrtmgr.@)
 */
DWORD WINAPI RmRegisterResources(DWORD handle, UINT nFiles, LPCWSTR rgsFilenames[],
                                 UINT nApplications, RM_UNIQUE_PROCESS *rgApplications,
                                 UINT nServices, LPCWSTR rgsServiceNames[])
{
    struct rm_session *session;
    UINT i;

    TRACE("(%lu, %u, %p, %u, %p, %u, %p)\n", handle, nFiles, rgsFilenames,
          nApplications, rgApplications, nServices, rgsServiceNames);

    EnterCriticalSection(&sessions_cs);
    session = get_session(handle);
    if (!session)
    {
        LeaveCriticalSection(&sessions_cs);
        return ERROR_INVALID_HANDLE;
    }
    EnterCriticalSection(&session->cs);
    LeaveCriticalSection(&sessions_cs);

    for (i = 0; i < nFiles; i++)
    {
        if (rgsFilenames[i])
        {
            TRACE("  file[%u]: %s\n", i, debugstr_w(rgsFilenames[i]));
            if (!add_file(session, rgsFilenames[i]))
            {
                LeaveCriticalSection(&session->cs);
                return ERROR_OUTOFMEMORY;
            }
        }
    }

    for (i = 0; i < nApplications; i++)
    {
        TRACE("  process[%u]: pid %lu\n", i, rgApplications[i].dwProcessId);
        if (!add_process(session, &rgApplications[i]))
        {
            LeaveCriticalSection(&session->cs);
            return ERROR_OUTOFMEMORY;
        }
    }

    for (i = 0; i < nServices; i++)
    {
        if (rgsServiceNames[i])
        {
            TRACE("  service[%u]: %s\n", i, debugstr_w(rgsServiceNames[i]));
            if (!add_service(session, rgsServiceNames[i]))
            {
                LeaveCriticalSection(&session->cs);
                return ERROR_OUTOFMEMORY;
            }
        }
    }

    LeaveCriticalSection(&session->cs);
    return ERROR_SUCCESS;
}

/***********************************************************************
 * RmGetList (rstrtmgr.@)
 */
DWORD WINAPI RmGetList(DWORD handle, UINT *pnProcInfoNeeded, UINT *pnProcInfo,
                       RM_PROCESS_INFO *rgAffectedApps[], LPDWORD lpdwRebootReasons)
{
    struct rm_session *session;
    DWORD ret = ERROR_SUCCESS;

    TRACE("(%lu, %p, %p, %p, %p)\n", handle, pnProcInfoNeeded, pnProcInfo,
          rgAffectedApps, lpdwRebootReasons);

    if (!pnProcInfoNeeded || !pnProcInfo) return ERROR_INVALID_PARAMETER;

    EnterCriticalSection(&sessions_cs);
    session = get_session(handle);
    if (!session)
    {
        LeaveCriticalSection(&sessions_cs);
        return ERROR_INVALID_HANDLE;
    }
    EnterCriticalSection(&session->cs);
    LeaveCriticalSection(&sessions_cs);

    /* Clear previous results */
    free(session->affected);
    session->affected = NULL;
    session->affected_count = 0;
    session->reboot_reasons = RmRebootReasonNone;

    /* Detect affected apps */
    detect_file_locks(session);
    detect_running_processes(session);
    detect_running_services(session);

    *pnProcInfoNeeded = session->affected_count;
    if (lpdwRebootReasons)
        *lpdwRebootReasons = session->reboot_reasons;

    if (session->affected_count == 0)
    {
        *pnProcInfo = 0;
    }
    else if (*pnProcInfo < session->affected_count)
    {
        /* Buffer too small */
        ret = ERROR_MORE_DATA;
    }
    else
    {
        *pnProcInfo = session->affected_count;
        if (rgAffectedApps && *rgAffectedApps)
            memcpy(*rgAffectedApps, session->affected,
                   session->affected_count * sizeof(RM_PROCESS_INFO));
    }

    TRACE("Found %u affected apps, reboot reasons %#lx\n",
          session->affected_count, session->reboot_reasons);

    LeaveCriticalSection(&session->cs);
    return ret;
}

/***********************************************************************
 * RmShutdown (rstrtmgr.@)
 */
DWORD WINAPI RmShutdown(DWORD handle, ULONG flags, RM_WRITE_STATUS_CALLBACK status_cb)
{
    struct rm_session *session;
    UINT i;
    SC_HANDLE scm = NULL;

    TRACE("(%lu, %#lx, %p)\n", handle, flags, status_cb);

    EnterCriticalSection(&sessions_cs);
    session = get_session(handle);
    if (!session)
    {
        LeaveCriticalSection(&sessions_cs);
        return ERROR_INVALID_HANDLE;
    }
    EnterCriticalSection(&session->cs);
    LeaveCriticalSection(&sessions_cs);

    /* Save affected list for RmRestart */
    free(session->shutdown_apps);
    session->shutdown_apps = NULL;
    session->shutdown_count = 0;

    if (session->affected_count)
    {
        session->shutdown_apps = malloc(session->affected_count * sizeof(RM_PROCESS_INFO));
        if (session->shutdown_apps)
        {
            memcpy(session->shutdown_apps, session->affected,
                   session->affected_count * sizeof(RM_PROCESS_INFO));
            session->shutdown_count = session->affected_count;
        }
    }

    for (i = 0; i < session->affected_count; i++)
    {
        RM_PROCESS_INFO *app = &session->affected[i];
        RM_FILTER_ACTION filter = check_filter(session, app);

        if (filter == RmNoShutdown)
        {
            TRACE("Skipping shutdown of %s (filtered)\n", debugstr_w(app->strAppName));
            continue;
        }

        if (status_cb) status_cb(i * 100 / session->affected_count);

        if (app->ApplicationType == RmService)
        {
            /* Stop service */
            SC_HANDLE svc;
            SERVICE_STATUS ss;

            if (!scm) scm = OpenSCManagerW(NULL, NULL, SC_MANAGER_CONNECT);
            if (scm)
            {
                svc = OpenServiceW(scm, app->strServiceShortName, SERVICE_STOP | SERVICE_QUERY_STATUS);
                if (svc)
                {
                    TRACE("Stopping service %s\n", debugstr_w(app->strServiceShortName));
                    if (ControlService(svc, SERVICE_CONTROL_STOP, &ss))
                    {
                        /* Wait for service to stop */
                        DWORD start_tick = GetTickCount();
                        while (GetTickCount() - start_tick < RM_SHUTDOWN_TIMEOUT)
                        {
                            SERVICE_STATUS_PROCESS ssp;
                            DWORD needed;
                            if (QueryServiceStatusEx(svc, SC_STATUS_PROCESS_INFO, (BYTE *)&ssp,
                                                     sizeof(ssp), &needed))
                            {
                                if (ssp.dwCurrentState == SERVICE_STOPPED) break;
                            }
                            Sleep(200);
                        }
                    }
                    CloseServiceHandle(svc);
                }
            }
        }
        else
        {
            /* Try graceful shutdown via WM_CLOSE, then force if needed */
            struct enum_windows_data data = { app->Process.dwProcessId, NULL };
            HANDLE proc;

            EnumWindows(find_main_window, (LPARAM)&data);
            if (data.hwnd)
            {
                TRACE("Sending WM_CLOSE to pid %lu window %p\n",
                      app->Process.dwProcessId, data.hwnd);
                PostMessageW(data.hwnd, WM_CLOSE, 0, 0);
            }

            /* Wait for process to exit */
            proc = OpenProcess(SYNCHRONIZE | PROCESS_TERMINATE, FALSE, app->Process.dwProcessId);
            if (proc)
            {
                if (WaitForSingleObject(proc, RM_SHUTDOWN_TIMEOUT) != WAIT_OBJECT_0)
                {
                    if (flags & RmForceShutdown)
                    {
                        TRACE("Force-terminating pid %lu\n", app->Process.dwProcessId);
                        TerminateProcess(proc, 1);
                    }
                    else
                    {
                        WARN("Process %lu did not exit within timeout\n",
                             app->Process.dwProcessId);
                    }
                }
                CloseHandle(proc);
            }
        }
    }

    if (scm) CloseServiceHandle(scm);
    if (status_cb) status_cb(100);

    LeaveCriticalSection(&session->cs);
    return ERROR_SUCCESS;
}

/***********************************************************************
 * RmRestart (rstrtmgr.@)
 */
DWORD WINAPI RmRestart(DWORD handle, DWORD flags, RM_WRITE_STATUS_CALLBACK status_cb)
{
    struct rm_session *session;
    UINT i;
    SC_HANDLE scm = NULL;

    TRACE("(%lu, %#lx, %p)\n", handle, flags, status_cb);

    EnterCriticalSection(&sessions_cs);
    session = get_session(handle);
    if (!session)
    {
        LeaveCriticalSection(&sessions_cs);
        return ERROR_INVALID_HANDLE;
    }
    EnterCriticalSection(&session->cs);
    LeaveCriticalSection(&sessions_cs);

    for (i = 0; i < session->shutdown_count; i++)
    {
        RM_PROCESS_INFO *app = &session->shutdown_apps[i];
        RM_FILTER_ACTION filter = check_filter(session, app);

        if (filter == RmNoRestart || !app->bRestartable)
            continue;

        if (status_cb) status_cb(i * 100 / session->shutdown_count);

        if (app->ApplicationType == RmService)
        {
            SC_HANDLE svc;
            if (!scm) scm = OpenSCManagerW(NULL, NULL, SC_MANAGER_CONNECT);
            if (scm)
            {
                svc = OpenServiceW(scm, app->strServiceShortName, SERVICE_START);
                if (svc)
                {
                    TRACE("Starting service %s\n", debugstr_w(app->strServiceShortName));
                    StartServiceW(svc, 0, NULL);
                    CloseServiceHandle(svc);
                }
            }
        }
        /* Non-service processes: we don't have the command line to restart them,
         * Windows uses RegisterApplicationRestart for this. Skip silently. */
    }

    if (scm) CloseServiceHandle(scm);
    if (status_cb) status_cb(100);

    LeaveCriticalSection(&session->cs);
    return ERROR_SUCCESS;
}

/***********************************************************************
 * RmEndSession (rstrtmgr.@)
 */
DWORD WINAPI RmEndSession(DWORD handle)
{
    struct rm_session *session;

    TRACE("(%lu)\n", handle);

    EnterCriticalSection(&sessions_cs);
    session = get_session(handle);
    if (!session)
    {
        LeaveCriticalSection(&sessions_cs);
        return ERROR_INVALID_HANDLE;
    }
    session_cleanup(session);
    LeaveCriticalSection(&sessions_cs);

    return ERROR_SUCCESS;
}

/***********************************************************************
 * RmAddFilter (rstrtmgr.@)
 */
DWORD WINAPI RmAddFilter(DWORD handle, LPCWSTR moduleName, RM_UNIQUE_PROCESS *process,
                         LPCWSTR serviceShortName, RM_FILTER_ACTION filter)
{
    struct rm_session *session;
    struct rm_filter *f;

    TRACE("(%lu, %s, %p, %s, %#x)\n", handle, debugstr_w(moduleName), process,
          debugstr_w(serviceShortName), filter);

    if (filter != RmNoRestart && filter != RmNoShutdown)
        return ERROR_INVALID_PARAMETER;

    EnterCriticalSection(&sessions_cs);
    session = get_session(handle);
    if (!session)
    {
        LeaveCriticalSection(&sessions_cs);
        return ERROR_INVALID_HANDLE;
    }
    EnterCriticalSection(&session->cs);
    LeaveCriticalSection(&sessions_cs);

    f = calloc(1, sizeof(*f));
    if (!f)
    {
        LeaveCriticalSection(&session->cs);
        return ERROR_OUTOFMEMORY;
    }

    f->action = filter;
    if (moduleName) f->module_name = wstr_dup(moduleName);
    if (serviceShortName) f->service_name = wstr_dup(serviceShortName);
    if (process)
    {
        f->process = malloc(sizeof(*process));
        if (f->process) *f->process = *process;
    }

    f->next = session->filters;
    session->filters = f;

    LeaveCriticalSection(&session->cs);
    return ERROR_SUCCESS;
}

/***********************************************************************
 * RmRemoveFilter (rstrtmgr.@)
 */
DWORD WINAPI RmRemoveFilter(DWORD handle, LPCWSTR moduleName, RM_UNIQUE_PROCESS *process,
                            LPCWSTR serviceShortName)
{
    struct rm_session *session;
    struct rm_filter **pp, *f;

    TRACE("(%lu, %s, %p, %s)\n", handle, debugstr_w(moduleName), process,
          debugstr_w(serviceShortName));

    EnterCriticalSection(&sessions_cs);
    session = get_session(handle);
    if (!session)
    {
        LeaveCriticalSection(&sessions_cs);
        return ERROR_INVALID_HANDLE;
    }
    EnterCriticalSection(&session->cs);
    LeaveCriticalSection(&sessions_cs);

    for (pp = &session->filters; *pp; pp = &(*pp)->next)
    {
        BOOL match = FALSE;
        f = *pp;

        if (moduleName && f->module_name && !lstrcmpiW(moduleName, f->module_name))
            match = TRUE;
        if (serviceShortName && f->service_name && !lstrcmpiW(serviceShortName, f->service_name))
            match = TRUE;
        if (process && f->process && process->dwProcessId == f->process->dwProcessId)
            match = TRUE;

        if (match)
        {
            *pp = f->next;
            free(f->module_name);
            free(f->process);
            free(f->service_name);
            free(f);
            LeaveCriticalSection(&session->cs);
            return ERROR_SUCCESS;
        }
    }

    LeaveCriticalSection(&session->cs);
    return ERROR_SUCCESS;
}
