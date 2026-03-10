/*
 * Copyright 2017 Jactry Zeng for CodeWeavers
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
#include <stdlib.h>
#include "wine/debug.h"

WINE_DEFAULT_DEBUG_CHANNEL(powershell);

int __cdecl wmain(int argc, WCHAR *argv[])
{
    int i;

    /* Installers (e.g. BarTender) call powershell with (Get-WinUserLanguageList).LanguageTag
     * and read stdout; the stub must return a BCP-47 tag or the caller gets IOException. */
    for (i = 1; i < argc; i++)
    {
        if (argv[i] && (wcsstr(argv[i], L"LanguageTag") || wcsstr(argv[i], L"Get-WinUserLanguageList")))
        {
            const char *tag = "en-US";
            const char *lang = getenv("LANG");
            if (lang && (lang[0] == 'r' || lang[0] == 'R') && lang[1] == 'u' && (lang[2] == '_' || lang[2] == '.'))
                tag = "ru-RU";
            else if (lang && lang[0] == 'e' && lang[1] == 'n' && (lang[2] == '_' || lang[2] == '.' || !lang[2]))
                tag = "en-US";
            printf("%s\n", tag);
            fflush(stdout);
            return 0;
        }
    }

    WINE_FIXME("stub.\n");
    for (i = 0; i < argc; i++)
    {
        WINE_FIXME("argv[%d] %s\n", i, wine_dbgstr_w(argv[i]));
        if (!wcsicmp(argv[i], L"-command") && i < argc - 1 && !wcscmp(argv[i + 1], L"-"))
        {
            char command[4096], *p;

            ++i;
            while (fgets(command, sizeof(command), stdin))
            {
                WINE_FIXME("command %s.\n", debugstr_a(command));
                p = command;
                while (*p && !isspace(*p)) ++p;
                *p = 0;
                if (!stricmp(command, "exit"))
                    break;
            }
        }
    }
    return 0;
}
