@ cdecl -arch=i386 _CIacos() ucrtbase._CIacos
@ cdecl -arch=i386 _CIasin() ucrtbase._CIasin
@ cdecl -arch=i386 _CIatan() ucrtbase._CIatan
@ cdecl -arch=i386 _CIatan2() ucrtbase._CIatan2
@ cdecl -arch=i386 _CIcos() ucrtbase._CIcos
@ cdecl -arch=i386 _CIcosh() ucrtbase._CIcosh
@ cdecl -arch=i386 _CIexp() ucrtbase._CIexp
@ cdecl -arch=i386 _CIfmod() ucrtbase._CIfmod
@ cdecl -arch=i386 _CIlog() ucrtbase._CIlog
@ cdecl -arch=i386 _CIlog10() ucrtbase._CIlog10
@ cdecl -arch=i386 _CIpow() ucrtbase._CIpow
@ cdecl -arch=i386 _CIsin() ucrtbase._CIsin
@ cdecl -arch=i386 _CIsinh() ucrtbase._CIsinh
@ cdecl -arch=i386 _CIsqrt() ucrtbase._CIsqrt
@ cdecl -arch=i386 _CItan() ucrtbase._CItan
@ cdecl -arch=i386 _CItanh() ucrtbase._CItanh
@ cdecl -norelay _Cbuild(double double) ucrtbase._Cbuild
@ stub _Cmulcc
@ stub _Cmulcr
@ cdecl _CreateFrameInfo(ptr ptr) ucrtbase._CreateFrameInfo
@ stdcall _CxxThrowException(ptr ptr) ucrtbase._CxxThrowException
@ cdecl -arch=i386 -norelay _EH_prolog() ucrtbase._EH_prolog
@ cdecl _Exit(long) ucrtbase._Exit
@ cdecl -norelay _FCbuild(float float) ucrtbase._FCbuild
@ stub _FCmulcc
@ stub _FCmulcr
@ cdecl _FindAndUnlinkFrame(ptr) ucrtbase._FindAndUnlinkFrame
@ stub _GetImageBase
@ stub _GetThrowImageBase
@ cdecl _Getdays() ucrtbase._Getdays
@ cdecl _Getmonths() ucrtbase._Getmonths
@ cdecl _Gettnames() ucrtbase._Gettnames
@ cdecl _IsExceptionObjectToBeDestroyed(ptr) ucrtbase._IsExceptionObjectToBeDestroyed
@ stub _LCbuild
@ stub _LCmulcc
@ stub _LCmulcr
@ stub _SetImageBase
@ stub _SetThrowImageBase
@ stub _NLG_Dispatch2
@ stub _NLG_Return
@ stub _NLG_Return2
@ cdecl _SetWinRTOutOfMemoryExceptionCallback(ptr) ucrtbase._SetWinRTOutOfMemoryExceptionCallback
@ cdecl _Strftime(ptr long str ptr ptr) ucrtbase._Strftime
@ cdecl _W_Getdays() ucrtbase._W_Getdays
@ cdecl _W_Getmonths() ucrtbase._W_Getmonths
@ cdecl _W_Gettnames() ucrtbase._W_Gettnames
@ cdecl _Wcsftime(ptr long wstr ptr ptr) ucrtbase._Wcsftime
@ cdecl __AdjustPointer(ptr ptr) ucrtbase.__AdjustPointer
@ stub __BuildCatchObject
@ stub __BuildCatchObjectHelper
@ stdcall -arch=!i386 __C_specific_handler(ptr long ptr ptr) ucrtbase.__C_specific_handler
@ cdecl __CxxDetectRethrow(ptr) ucrtbase.__CxxDetectRethrow
@ cdecl __CxxExceptionFilter(ptr ptr long ptr) ucrtbase.__CxxExceptionFilter
@ cdecl -norelay __CxxFrameHandler(ptr ptr ptr ptr) ucrtbase.__CxxFrameHandler
@ cdecl -norelay __CxxFrameHandler2(ptr ptr ptr ptr) ucrtbase.__CxxFrameHandler2
@ cdecl -norelay __CxxFrameHandler3(ptr ptr ptr ptr) ucrtbase.__CxxFrameHandler3
@ cdecl -arch=x86_64 __CxxFrameHandler4(ptr long ptr ptr) ucrtbase.__CxxFrameHandler4
@ stdcall -arch=i386 __CxxLongjmpUnwind(ptr) ucrtbase.__CxxLongjmpUnwind
@ cdecl __CxxQueryExceptionSize() ucrtbase.__CxxQueryExceptionSize
@ cdecl __CxxRegisterExceptionObject(ptr ptr) ucrtbase.__CxxRegisterExceptionObject
@ cdecl __CxxUnregisterExceptionObject(ptr long) ucrtbase.__CxxUnregisterExceptionObject
@ cdecl __DestructExceptionObject(ptr) ucrtbase.__DestructExceptionObject
@ stub __FrameUnwindFilter
@ stub __GetPlatformExceptionInfo
@ stub __NLG_Dispatch2
@ stub __NLG_Return2
@ cdecl __RTCastToVoid(ptr) ucrtbase.__RTCastToVoid
@ cdecl __RTDynamicCast(ptr long ptr ptr long) ucrtbase.__RTDynamicCast
@ cdecl __RTtypeid(ptr) ucrtbase.__RTtypeid
@ stub __TypeMatch
@ cdecl ___lc_codepage_func() ucrtbase.___lc_codepage_func
@ cdecl ___lc_collate_cp_func() ucrtbase.___lc_collate_cp_func
@ cdecl ___lc_locale_name_func() ucrtbase.___lc_locale_name_func
@ cdecl ___mb_cur_max_func() ucrtbase.___mb_cur_max_func
@ cdecl ___mb_cur_max_l_func(ptr) ucrtbase.___mb_cur_max_l_func
@ cdecl __acrt_iob_func(long) ucrtbase.__acrt_iob_func
@ cdecl __conio_common_vcprintf(int64 str ptr ptr) ucrtbase.__conio_common_vcprintf
@ stub __conio_common_vcprintf_p
@ stub __conio_common_vcprintf_s
@ stub __conio_common_vcscanf
@ cdecl __conio_common_vcwprintf(int64 wstr ptr ptr) ucrtbase.__conio_common_vcwprintf
@ stub __conio_common_vcwprintf_p
@ stub __conio_common_vcwprintf_s
@ stub __conio_common_vcwscanf
@ cdecl -arch=i386 __control87_2(long long ptr ptr) ucrtbase.__control87_2
@ cdecl __current_exception() ucrtbase.__current_exception
@ cdecl __current_exception_context() ucrtbase.__current_exception_context
@ cdecl __daylight() ucrtbase.__daylight
@ stub __dcrt_get_wide_environment_from_os
@ stub __dcrt_initial_narrow_environment
@ cdecl __doserrno() ucrtbase.__doserrno
@ cdecl __dstbias() ucrtbase.__dstbias
@ cdecl __fpe_flt_rounds() ucrtbase.__fpe_flt_rounds
@ cdecl __fpecode() ucrtbase.__fpecode
@ cdecl __initialize_lconv_for_unsigned_char() ucrtbase.__initialize_lconv_for_unsigned_char
@ cdecl __intrinsic_abnormal_termination() ucrtbase.__intrinsic_abnormal_termination
@ cdecl -norelay __intrinsic_setjmp(ptr) ucrtbase.__intrinsic_setjmp
@ cdecl -arch=!i386 -norelay __intrinsic_setjmpex(ptr ptr) ucrtbase.__intrinsic_setjmpex
@ cdecl __isascii(long) ucrtbase.__isascii
@ cdecl __iscsym(long) ucrtbase.__iscsym
@ cdecl __iscsymf(long) ucrtbase.__iscsymf
@ cdecl __iswcsym(long) ucrtbase.__iswcsym
@ cdecl __iswcsymf(long) ucrtbase.__iswcsymf
@ stdcall -arch=arm __jump_unwind(ptr ptr) ucrtbase.__jump_unwind
@ cdecl -arch=i386 -norelay __libm_sse2_acos() ucrtbase.__libm_sse2_acos
@ cdecl -arch=i386 -norelay __libm_sse2_acosf() ucrtbase.__libm_sse2_acosf
@ cdecl -arch=i386 -norelay __libm_sse2_asin() ucrtbase.__libm_sse2_asin
@ cdecl -arch=i386 -norelay __libm_sse2_asinf() ucrtbase.__libm_sse2_asinf
@ cdecl -arch=i386 -norelay __libm_sse2_atan() ucrtbase.__libm_sse2_atan
@ cdecl -arch=i386 -norelay __libm_sse2_atan2() ucrtbase.__libm_sse2_atan2
@ cdecl -arch=i386 -norelay __libm_sse2_atanf() ucrtbase.__libm_sse2_atanf
@ cdecl -arch=i386 -norelay __libm_sse2_cos() ucrtbase.__libm_sse2_cos
@ cdecl -arch=i386 -norelay __libm_sse2_cosf() ucrtbase.__libm_sse2_cosf
@ cdecl -arch=i386 -norelay __libm_sse2_exp() ucrtbase.__libm_sse2_exp
@ cdecl -arch=i386 -norelay __libm_sse2_expf() ucrtbase.__libm_sse2_expf
@ cdecl -arch=i386 -norelay __libm_sse2_log() ucrtbase.__libm_sse2_log
@ cdecl -arch=i386 -norelay __libm_sse2_log10() ucrtbase.__libm_sse2_log10
@ cdecl -arch=i386 -norelay __libm_sse2_log10f() ucrtbase.__libm_sse2_log10f
@ cdecl -arch=i386 -norelay __libm_sse2_logf() ucrtbase.__libm_sse2_logf
@ cdecl -arch=i386 -norelay __libm_sse2_pow() ucrtbase.__libm_sse2_pow
@ cdecl -arch=i386 -norelay __libm_sse2_powf() ucrtbase.__libm_sse2_powf
@ cdecl -arch=i386 -norelay __libm_sse2_sin() ucrtbase.__libm_sse2_sin
@ cdecl -arch=i386 -norelay __libm_sse2_sinf() ucrtbase.__libm_sse2_sinf
@ cdecl -arch=i386 -norelay __libm_sse2_tan() ucrtbase.__libm_sse2_tan
@ cdecl -arch=i386 -norelay __libm_sse2_tanf() ucrtbase.__libm_sse2_tanf
@ cdecl __p___argc() ucrtbase.__p___argc
@ cdecl __p___argv() ucrtbase.__p___argv
@ cdecl __p___wargv() ucrtbase.__p___wargv
@ cdecl __p__acmdln() ucrtbase.__p__acmdln
@ cdecl __p__commode() ucrtbase.__p__commode
@ cdecl __p__environ() ucrtbase.__p__environ
@ cdecl __p__fmode() ucrtbase.__p__fmode
@ stub __p__mbcasemap()
@ cdecl __p__mbctype() ucrtbase.__p__mbctype
@ cdecl __p__pgmptr() ucrtbase.__p__pgmptr
@ cdecl __p__wcmdln() ucrtbase.__p__wcmdln
@ cdecl __p__wenviron() ucrtbase.__p__wenviron
@ cdecl __p__wpgmptr() ucrtbase.__p__wpgmptr
@ cdecl __pctype_func() ucrtbase.__pctype_func
@ cdecl __processing_throw() ucrtbase.__processing_throw
@ cdecl __pwctype_func() ucrtbase.__pwctype_func
@ cdecl __pxcptinfoptrs() ucrtbase.__pxcptinfoptrs
@ stub __report_gsfailure
@ cdecl __setusermatherr(ptr) ucrtbase.__setusermatherr
@ cdecl __std_exception_copy(ptr ptr) ucrtbase.__std_exception_copy
@ cdecl __std_exception_destroy(ptr) ucrtbase.__std_exception_destroy
@ cdecl __std_terminate() ucrtbase.__std_terminate
@ cdecl __std_type_info_compare(ptr ptr) ucrtbase.__std_type_info_compare
@ cdecl __std_type_info_destroy_list(ptr) ucrtbase.__std_type_info_destroy_list
@ cdecl __std_type_info_hash(ptr) ucrtbase.__std_type_info_hash
@ cdecl __std_type_info_name(ptr ptr) ucrtbase.__std_type_info_name
@ cdecl __stdio_common_vfprintf(int64 ptr str ptr ptr) ucrtbase.__stdio_common_vfprintf
@ cdecl __stdio_common_vfprintf_p(int64 ptr str ptr ptr) ucrtbase.__stdio_common_vfprintf_p
@ cdecl __stdio_common_vfprintf_s(int64 ptr str ptr ptr) ucrtbase.__stdio_common_vfprintf_s
@ cdecl __stdio_common_vfscanf(int64 ptr str ptr ptr) ucrtbase.__stdio_common_vfscanf
@ cdecl __stdio_common_vfwprintf(int64 ptr wstr ptr ptr) ucrtbase.__stdio_common_vfwprintf
@ cdecl __stdio_common_vfwprintf_p(int64 ptr wstr ptr ptr) ucrtbase.__stdio_common_vfwprintf_p
@ cdecl __stdio_common_vfwprintf_s(int64 ptr wstr ptr ptr) ucrtbase.__stdio_common_vfwprintf_s
@ cdecl __stdio_common_vfwscanf(int64 ptr wstr ptr ptr) ucrtbase.__stdio_common_vfwscanf
@ cdecl __stdio_common_vsnprintf_s(int64 ptr long long str ptr ptr) ucrtbase.__stdio_common_vsnprintf_s
@ cdecl __stdio_common_vsnwprintf_s(int64 ptr long long wstr ptr ptr) ucrtbase.__stdio_common_vsnwprintf_s
@ cdecl -norelay __stdio_common_vsprintf(int64 ptr long str ptr ptr) ucrtbase.__stdio_common_vsprintf
@ cdecl __stdio_common_vsprintf_p(int64 ptr long str ptr ptr) ucrtbase.__stdio_common_vsprintf_p
@ cdecl __stdio_common_vsprintf_s(int64 ptr long str ptr ptr) ucrtbase.__stdio_common_vsprintf_s
@ cdecl __stdio_common_vsscanf(int64 ptr long str ptr ptr) ucrtbase.__stdio_common_vsscanf
@ cdecl __stdio_common_vswprintf(int64 ptr long wstr ptr ptr) ucrtbase.__stdio_common_vswprintf
@ cdecl __stdio_common_vswprintf_p(int64 ptr long wstr ptr ptr) ucrtbase.__stdio_common_vswprintf_p
@ cdecl __stdio_common_vswprintf_s(int64 ptr long wstr ptr ptr) ucrtbase.__stdio_common_vswprintf_s
@ cdecl __stdio_common_vswscanf(int64 ptr long wstr ptr ptr) ucrtbase.__stdio_common_vswscanf
@ cdecl __strncnt(str long) ucrtbase.__strncnt
@ cdecl __sys_errlist() ucrtbase.__sys_errlist
@ cdecl __sys_nerr() ucrtbase.__sys_nerr
@ cdecl __threadhandle() ucrtbase.__threadhandle
@ cdecl __threadid() ucrtbase.__threadid
@ cdecl __timezone() ucrtbase.__timezone
@ cdecl __toascii(long) ucrtbase.__toascii
@ cdecl __tzname() ucrtbase.__tzname
@ cdecl __unDName(ptr str long ptr ptr long) ucrtbase.__unDName
@ cdecl __unDNameEx(ptr str long ptr ptr ptr long) ucrtbase.__unDNameEx
@ cdecl __uncaught_exception() ucrtbase.__uncaught_exception
@ cdecl __wcserror(wstr) ucrtbase.__wcserror
@ cdecl __wcserror_s(ptr long wstr) ucrtbase.__wcserror_s
@ stub __wcsncnt
@ cdecl -ret64 _abs64(int64) ucrtbase._abs64
@ cdecl _access(str long) ucrtbase._access
@ cdecl _access_s(str long) ucrtbase._access_s
@ cdecl _aligned_free(ptr) ucrtbase._aligned_free
@ cdecl _aligned_malloc(long long) ucrtbase._aligned_malloc
@ cdecl _aligned_msize(ptr long long) ucrtbase._aligned_msize
@ cdecl _aligned_offset_malloc(long long long) ucrtbase._aligned_offset_malloc
@ cdecl _aligned_offset_realloc(ptr long long long) ucrtbase._aligned_offset_realloc
@ stub _aligned_offset_recalloc
@ cdecl _aligned_realloc(ptr long long) ucrtbase._aligned_realloc
@ stub _aligned_recalloc
@ cdecl _assert(str str long) ucrtbase._assert
@ cdecl _atodbl(ptr str) ucrtbase._atodbl
@ cdecl _atodbl_l(ptr str ptr) ucrtbase._atodbl_l
@ cdecl _atof_l(str ptr) ucrtbase._atof_l
@ cdecl _atoflt(ptr str) ucrtbase._atoflt
@ cdecl _atoflt_l(ptr str ptr) ucrtbase._atoflt_l
@ cdecl -ret64 _atoi64(str) ucrtbase._atoi64
@ cdecl -ret64 _atoi64_l(str ptr) ucrtbase._atoi64_l
@ cdecl _atoi_l(str ptr) ucrtbase._atoi_l
@ cdecl _atol_l(str ptr) ucrtbase._atol_l
@ cdecl _atoldbl(ptr str) ucrtbase._atoldbl
@ cdecl _atoldbl_l(ptr str ptr) ucrtbase._atoldbl_l
@ cdecl -ret64 _atoll_l(str ptr) ucrtbase._atoll_l
@ cdecl _beep(long long) ucrtbase._beep
@ cdecl _beginthread(ptr long ptr) ucrtbase._beginthread
@ cdecl _beginthreadex(ptr long ptr ptr long ptr) ucrtbase._beginthreadex
@ cdecl _byteswap_uint64(int64) ucrtbase._byteswap_uint64
@ cdecl _byteswap_ulong(long) ucrtbase._byteswap_ulong
@ cdecl _byteswap_ushort(long) ucrtbase._byteswap_ushort
@ cdecl _c_exit() ucrtbase._c_exit
@ cdecl _cabs(long) ucrtbase._cabs
@ cdecl _callnewh(long) ucrtbase._callnewh
@ cdecl _calloc_base(long long) ucrtbase._calloc_base
@ cdecl _cexit() ucrtbase._cexit
@ cdecl _cgets(ptr) ucrtbase._cgets
@ stub _cgets_s
@ stub _cgetws
@ stub _cgetws_s
@ cdecl _chdir(str) ucrtbase._chdir
@ cdecl _chdrive(long) ucrtbase._chdrive
@ cdecl _chgsign(double) ucrtbase._chgsign
@ cdecl _chgsignf(float) ucrtbase._chgsignf
@ cdecl -arch=i386 -norelay _chkesp() ucrtbase._chkesp
@ cdecl _chmod(str long) ucrtbase._chmod
@ cdecl _chsize(long long) ucrtbase._chsize
@ cdecl _chsize_s(long int64) ucrtbase._chsize_s
@ cdecl _clearfp() ucrtbase._clearfp
@ cdecl _close(long) ucrtbase._close
@ cdecl _commit(long) ucrtbase._commit
@ cdecl _configthreadlocale(long) ucrtbase._configthreadlocale
@ cdecl _configure_narrow_argv(long) ucrtbase._configure_narrow_argv
@ cdecl _configure_wide_argv(long) ucrtbase._configure_wide_argv
@ cdecl _control87(long long) ucrtbase._control87
@ cdecl _controlfp(long long) ucrtbase._controlfp
@ cdecl _controlfp_s(ptr long long) ucrtbase._controlfp_s
@ cdecl _copysign(double double) ucrtbase._copysign
@ cdecl _copysignf(float float) ucrtbase._copysignf
@ cdecl _cputs(str) ucrtbase._cputs
@ cdecl _cputws(wstr) ucrtbase._cputws
@ cdecl _creat(str long) ucrtbase._creat
@ cdecl _create_locale(long str) ucrtbase._create_locale
@ cdecl _crt_at_quick_exit(ptr) ucrtbase._crt_at_quick_exit
@ cdecl _crt_atexit(ptr) ucrtbase._crt_atexit
@ cdecl _crt_debugger_hook(long) ucrtbase._crt_debugger_hook
@ cdecl _ctime32(ptr) ucrtbase._ctime32
@ cdecl _ctime32_s(str long ptr) ucrtbase._ctime32_s
@ cdecl _ctime64(ptr) ucrtbase._ctime64
@ cdecl _ctime64_s(str long ptr) ucrtbase._ctime64_s
@ cdecl _cwait(ptr long long) ucrtbase._cwait
@ stub _d_int
@ cdecl _dclass(double) ucrtbase._dclass
@ stub _dexp
@ cdecl _difftime32(long long) ucrtbase._difftime32
@ cdecl _difftime64(int64 int64) ucrtbase._difftime64
@ stub _dlog
@ stub _dnorm
@ cdecl _dpcomp(double double) ucrtbase._dpcomp
@ stub _dpoly
@ stub _dscale
@ cdecl _dsign(double) ucrtbase._dsign
@ stub _dsin
@ cdecl _dtest(ptr) ucrtbase._dtest
@ stub _dunscale
@ cdecl _dup(long) ucrtbase._dup
@ cdecl _dup2(long long) ucrtbase._dup2
@ cdecl _dupenv_s(ptr ptr str) ucrtbase._dupenv_s
@ cdecl _ecvt(double long ptr ptr) ucrtbase._ecvt
@ cdecl _ecvt_s(str long double long ptr ptr) ucrtbase._ecvt_s
@ cdecl _endthread() ucrtbase._endthread
@ cdecl _endthreadex(long) ucrtbase._endthreadex
@ cdecl _eof(long) ucrtbase._eof
@ cdecl _errno() ucrtbase._errno
@ cdecl _except1(long long double double long ptr) ucrtbase._except1
@ cdecl -arch=i386 _except_handler2(ptr ptr ptr ptr) ucrtbase._except_handler2
@ cdecl -arch=i386 _except_handler3(ptr ptr ptr ptr) ucrtbase._except_handler3
@ cdecl -arch=i386 _except_handler4_common(ptr ptr ptr ptr ptr ptr) ucrtbase._except_handler4_common
@ varargs _execl(str str) ucrtbase._execl
@ varargs _execle(str str) ucrtbase._execle
@ varargs _execlp(str str) ucrtbase._execlp
@ varargs _execlpe(str str) ucrtbase._execlpe
@ cdecl _execute_onexit_table(ptr) ucrtbase._execute_onexit_table
@ cdecl _execv(str ptr) ucrtbase._execv
@ cdecl _execve(str ptr ptr) ucrtbase._execve
@ cdecl _execvp(str ptr) ucrtbase._execvp
@ cdecl _execvpe(str ptr ptr) ucrtbase._execvpe
@ cdecl _exit(long) ucrtbase._exit
@ cdecl _expand(ptr long) ucrtbase._expand
@ cdecl _fclose_nolock(ptr) ucrtbase._fclose_nolock
@ cdecl _fcloseall() ucrtbase._fcloseall
@ cdecl _fcvt(double long ptr ptr) ucrtbase._fcvt
@ cdecl _fcvt_s(ptr long double long ptr ptr) ucrtbase._fcvt_s
@ stub _fd_int
@ cdecl _fdclass(float) ucrtbase._fdclass
@ stub _fdexp
@ stub _fdlog
@ stub _fdnorm
@ cdecl _fdopen(long str) ucrtbase._fdopen
@ cdecl _fdpcomp(float float) ucrtbase._fdpcomp
@ stub _fdpoly
@ stub _fdscale
@ cdecl _fdsign(float) ucrtbase._fdsign
@ stub _fdsin
@ cdecl _fdtest(ptr) ucrtbase._fdtest
@ stub _fdunscale
@ cdecl _fflush_nolock(ptr) ucrtbase._fflush_nolock
@ cdecl _fgetc_nolock(ptr) ucrtbase._fgetc_nolock
@ cdecl _fgetchar() ucrtbase._fgetchar
@ cdecl _fgetwc_nolock(ptr) ucrtbase._fgetwc_nolock
@ cdecl _fgetwchar() ucrtbase._fgetwchar
@ cdecl _filelength(long) ucrtbase._filelength
@ cdecl -ret64 _filelengthi64(long) ucrtbase._filelengthi64
@ cdecl _fileno(ptr) ucrtbase._fileno
@ cdecl _findclose(long) ucrtbase._findclose
@ cdecl _findfirst32(str ptr) ucrtbase._findfirst32
@ stub _findfirst32i64
@ cdecl _findfirst64(str ptr) ucrtbase._findfirst64
@ cdecl _findfirst64i32(str ptr) ucrtbase._findfirst64i32
@ cdecl _findnext32(long ptr) ucrtbase._findnext32
@ stub _findnext32i64
@ cdecl _findnext64(long ptr) ucrtbase._findnext64
@ cdecl _findnext64i32(long ptr) ucrtbase._findnext64i32
@ cdecl _finite(double) ucrtbase._finite
@ cdecl -arch=!i386 _finitef(float) ucrtbase._finitef
@ cdecl _flushall() ucrtbase._flushall
@ cdecl _fpclass(double) ucrtbase._fpclass
@ cdecl -arch=!i386 _fpclassf(float) ucrtbase._fpclassf
@ cdecl _fpieee_flt(long ptr ptr) ucrtbase._fpieee_flt
@ cdecl _fpreset() ucrtbase._fpreset
@ cdecl _fputc_nolock(long ptr) ucrtbase._fputc_nolock
@ cdecl _fputchar(long) ucrtbase._fputchar
@ cdecl _fputwc_nolock(long ptr) ucrtbase._fputwc_nolock
@ cdecl _fputwchar(long) ucrtbase._fputwchar
@ cdecl _fread_nolock(ptr long long ptr) ucrtbase._fread_nolock
@ cdecl _fread_nolock_s(ptr long long long ptr) ucrtbase._fread_nolock_s
@ cdecl _free_base(ptr) ucrtbase._free_base
@ cdecl _free_locale(ptr) ucrtbase._free_locale
@ cdecl _fseek_nolock(ptr long long) ucrtbase._fseek_nolock
@ cdecl _fseeki64(ptr int64 long) ucrtbase._fseeki64
@ cdecl _fseeki64_nolock(ptr int64 long) ucrtbase._fseeki64_nolock
@ cdecl _fsopen(str str long) ucrtbase._fsopen
@ cdecl _fstat32(long ptr) ucrtbase._fstat32
@ cdecl _fstat32i64(long ptr) ucrtbase._fstat32i64
@ cdecl _fstat64(long ptr) ucrtbase._fstat64
@ cdecl _fstat64i32(long ptr) ucrtbase._fstat64i32
@ cdecl _ftell_nolock(ptr) ucrtbase._ftell_nolock
@ cdecl -ret64 _ftelli64(ptr) ucrtbase._ftelli64
@ cdecl -ret64 _ftelli64_nolock(ptr) ucrtbase._ftelli64_nolock
@ cdecl _ftime32(ptr) ucrtbase._ftime32
@ cdecl _ftime32_s(ptr) ucrtbase._ftime32_s
@ cdecl _ftime64(ptr) ucrtbase._ftime64
@ cdecl _ftime64_s(ptr) ucrtbase._ftime64_s
@ cdecl -arch=i386 -ret64 _ftol() ucrtbase._ftol
@ cdecl _fullpath(ptr str long) ucrtbase._fullpath
@ cdecl _futime32(long ptr) ucrtbase._futime32
@ cdecl _futime64(long ptr) ucrtbase._futime64
@ cdecl _fwrite_nolock(ptr long long ptr) ucrtbase._fwrite_nolock
@ cdecl _gcvt(double long str) ucrtbase._gcvt
@ cdecl _gcvt_s(ptr long double long) ucrtbase._gcvt_s
@ cdecl -arch=win64 _get_FMA3_enable() ucrtbase._get_FMA3_enable
@ cdecl _get_current_locale() ucrtbase._get_current_locale
@ cdecl _get_daylight(ptr) ucrtbase._get_daylight
@ cdecl _get_doserrno(ptr) ucrtbase._get_doserrno
@ cdecl _get_dstbias(ptr) ucrtbase._get_dstbias
@ cdecl _get_errno(ptr) ucrtbase._get_errno
@ cdecl _get_fmode(ptr) ucrtbase._get_fmode
@ cdecl _get_heap_handle() ucrtbase._get_heap_handle
@ cdecl _get_initial_narrow_environment() ucrtbase._get_initial_narrow_environment
@ cdecl _get_initial_wide_environment() ucrtbase._get_initial_wide_environment
@ cdecl _get_invalid_parameter_handler() ucrtbase._get_invalid_parameter_handler
@ cdecl _get_narrow_winmain_command_line() ucrtbase._get_narrow_winmain_command_line
@ cdecl _get_osfhandle(long) ucrtbase._get_osfhandle
@ cdecl _get_pgmptr(ptr) ucrtbase._get_pgmptr
@ cdecl _get_printf_count_output() ucrtbase._get_printf_count_output
@ cdecl _get_purecall_handler() ucrtbase._get_purecall_handler
@ cdecl _get_stream_buffer_pointers(ptr ptr ptr ptr) ucrtbase._get_stream_buffer_pointers
@ cdecl _get_terminate() ucrtbase._get_terminate
@ cdecl _get_thread_local_invalid_parameter_handler() ucrtbase._get_thread_local_invalid_parameter_handler
@ cdecl _get_timezone(ptr) ucrtbase._get_timezone
@ cdecl _get_tzname(ptr str long long) ucrtbase._get_tzname
@ cdecl _get_unexpected() ucrtbase._get_unexpected
@ cdecl _get_wide_winmain_command_line() ucrtbase._get_wide_winmain_command_line
@ cdecl _get_wpgmptr(ptr) ucrtbase._get_wpgmptr
@ cdecl _getc_nolock(ptr) ucrtbase._getc_nolock
@ cdecl _getch() ucrtbase._getch
@ cdecl _getch_nolock() ucrtbase._getch_nolock
@ cdecl _getche() ucrtbase._getche
@ cdecl _getche_nolock() ucrtbase._getche_nolock
@ cdecl _getcwd(str long) ucrtbase._getcwd
@ cdecl _getdcwd(long str long) ucrtbase._getdcwd
@ cdecl _getdiskfree(long ptr) ucrtbase._getdiskfree
@ cdecl _getdllprocaddr(long str long) ucrtbase._getdllprocaddr
@ cdecl _getdrive() ucrtbase._getdrive
@ cdecl _getdrives() ucrtbase._getdrives
@ cdecl _getmaxstdio() ucrtbase._getmaxstdio
@ cdecl _getmbcp() ucrtbase._getmbcp
@ cdecl _getpid() ucrtbase._getpid
@ stub _getsystime(ptr)
@ cdecl _getw(ptr) ucrtbase._getw
@ cdecl _getwc_nolock(ptr) ucrtbase._getwc_nolock
@ cdecl _getwch() ucrtbase._getwch
@ cdecl _getwch_nolock() ucrtbase._getwch_nolock
@ cdecl _getwche() ucrtbase._getwche
@ cdecl _getwche_nolock() ucrtbase._getwche_nolock
@ cdecl _getws(ptr) ucrtbase._getws
@ stub _getws_s
@ cdecl -arch=i386 _global_unwind2(ptr) ucrtbase._global_unwind2
@ cdecl _gmtime32(ptr) ucrtbase._gmtime32
@ cdecl _gmtime32_s(ptr ptr) ucrtbase._gmtime32_s
@ cdecl _gmtime64(ptr) ucrtbase._gmtime64
@ cdecl _gmtime64_s(ptr ptr) ucrtbase._gmtime64_s
@ cdecl _heapchk() ucrtbase._heapchk
@ cdecl _heapmin() ucrtbase._heapmin
@ cdecl _heapwalk(ptr) ucrtbase._heapwalk
@ cdecl _hypot(double double) ucrtbase._hypot
@ cdecl _hypotf(float float) ucrtbase._hypotf
@ cdecl _i64toa(int64 ptr long) ucrtbase._i64toa
@ cdecl _i64toa_s(int64 ptr long long) ucrtbase._i64toa_s
@ cdecl _i64tow(int64 ptr long) ucrtbase._i64tow
@ cdecl _i64tow_s(int64 ptr long long) ucrtbase._i64tow_s
@ cdecl _initialize_narrow_environment() ucrtbase._initialize_narrow_environment
@ cdecl _initialize_onexit_table(ptr) ucrtbase._initialize_onexit_table
@ cdecl _initialize_wide_environment() ucrtbase._initialize_wide_environment
@ cdecl _initterm(ptr ptr) ucrtbase._initterm
@ cdecl _initterm_e(ptr ptr) ucrtbase._initterm_e
@ cdecl _invalid_parameter_noinfo() ucrtbase._invalid_parameter_noinfo
@ cdecl _invalid_parameter_noinfo_noreturn() ucrtbase._invalid_parameter_noinfo_noreturn
@ stub _invoke_watson
@ stub _is_exception_typeof
@ cdecl _isalnum_l(long ptr) ucrtbase._isalnum_l
@ cdecl _isalpha_l(long ptr) ucrtbase._isalpha_l
@ cdecl _isatty(long) ucrtbase._isatty
@ cdecl _isblank_l(long ptr) ucrtbase._isblank_l
@ cdecl _iscntrl_l(long ptr) ucrtbase._iscntrl_l
@ cdecl _isctype(long long) ucrtbase._isctype
@ cdecl _isctype_l(long long ptr) ucrtbase._isctype_l
@ cdecl _isdigit_l(long ptr) ucrtbase._isdigit_l
@ cdecl _isgraph_l(long ptr) ucrtbase._isgraph_l
@ cdecl _isleadbyte_l(long ptr) ucrtbase._isleadbyte_l
@ cdecl _islower_l(long ptr) ucrtbase._islower_l
@ stub _ismbbalnum(long)
@ stub _ismbbalnum_l
@ stub _ismbbalpha(long)
@ stub _ismbbalpha_l
@ stub _ismbbblank
@ stub _ismbbblank_l
@ stub _ismbbgraph(long)
@ stub _ismbbgraph_l
@ stub _ismbbkalnum(long)
@ stub _ismbbkalnum_l
@ cdecl _ismbbkana(long) ucrtbase._ismbbkana
@ cdecl _ismbbkana_l(long ptr) ucrtbase._ismbbkana_l
@ stub _ismbbkprint(long)
@ stub _ismbbkprint_l
@ stub _ismbbkpunct(long)
@ stub _ismbbkpunct_l
@ cdecl _ismbblead(long) ucrtbase._ismbblead
@ cdecl _ismbblead_l(long ptr) ucrtbase._ismbblead_l
@ stub _ismbbprint(long)
@ stub _ismbbprint_l
@ stub _ismbbpunct(long)
@ stub _ismbbpunct_l
@ cdecl _ismbbtrail(long) ucrtbase._ismbbtrail
@ cdecl _ismbbtrail_l(long ptr) ucrtbase._ismbbtrail_l
@ cdecl _ismbcalnum(long) ucrtbase._ismbcalnum
@ cdecl _ismbcalnum_l(long ptr) ucrtbase._ismbcalnum_l
@ cdecl _ismbcalpha(long) ucrtbase._ismbcalpha
@ cdecl _ismbcalpha_l(long ptr) ucrtbase._ismbcalpha_l
@ stub _ismbcblank
@ stub _ismbcblank_l
@ cdecl _ismbcdigit(long) ucrtbase._ismbcdigit
@ cdecl _ismbcdigit_l(long ptr) ucrtbase._ismbcdigit_l
@ cdecl _ismbcgraph(long) ucrtbase._ismbcgraph
@ cdecl _ismbcgraph_l(long ptr) ucrtbase._ismbcgraph_l
@ cdecl _ismbchira(long) ucrtbase._ismbchira
@ cdecl _ismbchira_l(long ptr) ucrtbase._ismbchira_l
@ cdecl _ismbckata(long) ucrtbase._ismbckata
@ cdecl _ismbckata_l(long ptr) ucrtbase._ismbckata_l
@ cdecl _ismbcl0(long) ucrtbase._ismbcl0
@ cdecl _ismbcl0_l(long ptr) ucrtbase._ismbcl0_l
@ cdecl _ismbcl1(long) ucrtbase._ismbcl1
@ cdecl _ismbcl1_l(long ptr) ucrtbase._ismbcl1_l
@ cdecl _ismbcl2(long) ucrtbase._ismbcl2
@ cdecl _ismbcl2_l(long ptr) ucrtbase._ismbcl2_l
@ cdecl _ismbclegal(long) ucrtbase._ismbclegal
@ cdecl _ismbclegal_l(long ptr) ucrtbase._ismbclegal_l
@ cdecl _ismbclower(long) ucrtbase._ismbclower
@ cdecl _ismbclower_l(long ptr) ucrtbase._ismbclower_l
@ cdecl _ismbcprint(long) ucrtbase._ismbcprint
@ cdecl _ismbcprint_l(long ptr) ucrtbase._ismbcprint_l
@ cdecl _ismbcpunct(long) ucrtbase._ismbcpunct
@ cdecl _ismbcpunct_l(long ptr) ucrtbase._ismbcpunct_l
@ cdecl _ismbcspace(long) ucrtbase._ismbcspace
@ cdecl _ismbcspace_l(long ptr) ucrtbase._ismbcspace_l
@ cdecl _ismbcsymbol(long) ucrtbase._ismbcsymbol
@ cdecl _ismbcsymbol_l(long ptr) ucrtbase._ismbcsymbol_l
@ cdecl _ismbcupper(long) ucrtbase._ismbcupper
@ cdecl _ismbcupper_l(long ptr) ucrtbase._ismbcupper_l
@ cdecl _ismbslead(ptr ptr) ucrtbase._ismbslead
@ cdecl _ismbslead_l(ptr ptr ptr) ucrtbase._ismbslead_l
@ cdecl _ismbstrail(ptr ptr) ucrtbase._ismbstrail
@ cdecl _ismbstrail_l(ptr ptr ptr) ucrtbase._ismbstrail_l
@ cdecl _isnan(double) ucrtbase._isnan
@ cdecl -arch=x86_64 _isnanf(float) ucrtbase._isnanf
@ cdecl _isprint_l(long ptr) ucrtbase._isprint_l
@ cdecl _ispunct_l(long ptr) ucrtbase._ispunct_l
@ cdecl _isspace_l(long ptr) ucrtbase._isspace_l
@ cdecl _isupper_l(long ptr) ucrtbase._isupper_l
@ cdecl _iswalnum_l(long ptr) ucrtbase._iswalnum_l
@ cdecl _iswalpha_l(long ptr) ucrtbase._iswalpha_l
@ cdecl _iswblank_l(long ptr) ucrtbase._iswblank_l
@ cdecl _iswcntrl_l(long ptr) ucrtbase._iswcntrl_l
@ stub _iswcsym_l
@ stub _iswcsymf_l
@ cdecl _iswctype_l(long long ptr) ucrtbase._iswctype_l
@ cdecl _iswdigit_l(long ptr) ucrtbase._iswdigit_l
@ cdecl _iswgraph_l(long ptr) ucrtbase._iswgraph_l
@ cdecl _iswlower_l(long ptr) ucrtbase._iswlower_l
@ cdecl _iswprint_l(long ptr) ucrtbase._iswprint_l
@ cdecl _iswpunct_l(long ptr) ucrtbase._iswpunct_l
@ cdecl _iswspace_l(long ptr) ucrtbase._iswspace_l
@ cdecl _iswupper_l(long ptr) ucrtbase._iswupper_l
@ cdecl _iswxdigit_l(long ptr) ucrtbase._iswxdigit_l
@ cdecl _isxdigit_l(long ptr) ucrtbase._isxdigit_l
@ cdecl _itoa(long ptr long) ucrtbase._itoa
@ cdecl _itoa_s(long ptr long long) ucrtbase._itoa_s
@ cdecl _itow(long ptr long) ucrtbase._itow
@ cdecl _itow_s(long ptr long long) ucrtbase._itow_s
@ cdecl _j0(double) ucrtbase._j0
@ cdecl _j1(double) ucrtbase._j1
@ cdecl _jn(long double) ucrtbase._jn
@ cdecl _kbhit() ucrtbase._kbhit
@ stub _ld_int
@ cdecl _ldclass(double) ucrtbase._ldclass
@ stub _ldexp
@ stub _ldlog
@ cdecl _ldpcomp(double double) ucrtbase._ldpcomp
@ stub _ldpoly
@ stub _ldscale
@ cdecl _ldsign(double) ucrtbase._ldsign
@ stub _ldsin
@ cdecl _ldtest(ptr) ucrtbase._ldtest
@ stub _ldunscale
@ cdecl _lfind(ptr ptr ptr long ptr) ucrtbase._lfind
@ cdecl _lfind_s(ptr ptr ptr long ptr ptr) ucrtbase._lfind_s
@ cdecl -arch=i386 -norelay _libm_sse2_acos_precise() ucrtbase._libm_sse2_acos_precise
@ cdecl -arch=i386 -norelay _libm_sse2_asin_precise() ucrtbase._libm_sse2_asin_precise
@ cdecl -arch=i386 -norelay _libm_sse2_atan_precise() ucrtbase._libm_sse2_atan_precise
@ cdecl -arch=i386 -norelay _libm_sse2_cos_precise() ucrtbase._libm_sse2_cos_precise
@ cdecl -arch=i386 -norelay _libm_sse2_exp_precise() ucrtbase._libm_sse2_exp_precise
@ cdecl -arch=i386 -norelay _libm_sse2_log10_precise() ucrtbase._libm_sse2_log10_precise
@ cdecl -arch=i386 -norelay _libm_sse2_log_precise() ucrtbase._libm_sse2_log_precise
@ cdecl -arch=i386 -norelay _libm_sse2_pow_precise() ucrtbase._libm_sse2_pow_precise
@ cdecl -arch=i386 -norelay _libm_sse2_sin_precise() ucrtbase._libm_sse2_sin_precise
@ cdecl -arch=i386 -norelay _libm_sse2_sqrt_precise() ucrtbase._libm_sse2_sqrt_precise
@ cdecl -arch=i386 -norelay _libm_sse2_tan_precise() ucrtbase._libm_sse2_tan_precise
@ cdecl _loaddll(str) ucrtbase._loaddll
@ cdecl -arch=win64 _local_unwind(ptr ptr) ucrtbase._local_unwind
@ cdecl -arch=i386 _local_unwind2(ptr long) ucrtbase._local_unwind2
@ cdecl -arch=i386 _local_unwind4(ptr ptr long) ucrtbase._local_unwind4
@ cdecl _localtime32(ptr) ucrtbase._localtime32
@ cdecl _localtime32_s(ptr ptr) ucrtbase._localtime32_s
@ cdecl _localtime64(ptr) ucrtbase._localtime64
@ cdecl _localtime64_s(ptr ptr) ucrtbase._localtime64_s
@ cdecl _lock_file(ptr) ucrtbase._lock_file
@ cdecl _lock_locales() ucrtbase._lock_locales
@ cdecl _locking(long long long) ucrtbase._locking
@ cdecl _logb(double) ucrtbase._logb
@ cdecl -arch=!i386 _logbf(float) ucrtbase._logbf
@ cdecl -arch=i386 _longjmpex(ptr long) ucrtbase._longjmpex
@ cdecl _lrotl(long long) ucrtbase._lrotl
@ cdecl _lrotr(long long) ucrtbase._lrotr
@ cdecl _lsearch(ptr ptr ptr long ptr) ucrtbase._lsearch
@ stub _lsearch_s
@ cdecl _lseek(long long long) ucrtbase._lseek
@ cdecl -ret64 _lseeki64(long int64 long) ucrtbase._lseeki64
@ cdecl _ltoa(long ptr long) ucrtbase._ltoa
@ cdecl _ltoa_s(long ptr long long) ucrtbase._ltoa_s
@ cdecl _ltow(long ptr long) ucrtbase._ltow
@ cdecl _ltow_s(long ptr long long) ucrtbase._ltow_s
@ cdecl _makepath(ptr str str str str) ucrtbase._makepath
@ cdecl _makepath_s(ptr long str str str str) ucrtbase._makepath_s
@ cdecl _malloc_base(long) ucrtbase._malloc_base
@ cdecl _mbbtombc(long) ucrtbase._mbbtombc
@ cdecl _mbbtombc_l(long ptr) ucrtbase._mbbtombc_l
@ cdecl _mbbtype(long long) ucrtbase._mbbtype
@ cdecl _mbbtype_l(long long ptr) ucrtbase._mbbtype_l
@ stub _mbcasemap
@ cdecl _mbccpy(ptr ptr) ucrtbase._mbccpy
@ cdecl _mbccpy_l(ptr ptr ptr) ucrtbase._mbccpy_l
@ cdecl _mbccpy_s(ptr long ptr ptr) ucrtbase._mbccpy_s
@ cdecl _mbccpy_s_l(ptr long ptr ptr ptr) ucrtbase._mbccpy_s_l
@ cdecl _mbcjistojms(long) ucrtbase._mbcjistojms
@ cdecl _mbcjistojms_l(long ptr) ucrtbase._mbcjistojms_l
@ cdecl _mbcjmstojis(long) ucrtbase._mbcjmstojis
@ cdecl _mbcjmstojis_l(long ptr) ucrtbase._mbcjmstojis_l
@ cdecl _mbclen(ptr) ucrtbase._mbclen
@ cdecl _mbclen_l(ptr ptr) ucrtbase._mbclen_l
@ cdecl _mbctohira(long) ucrtbase._mbctohira
@ cdecl _mbctohira_l(long ptr) ucrtbase._mbctohira_l
@ cdecl _mbctokata(long) ucrtbase._mbctokata
@ cdecl _mbctokata_l(long ptr) ucrtbase._mbctokata_l
@ cdecl _mbctolower(long) ucrtbase._mbctolower
@ cdecl _mbctolower_l(long ptr) ucrtbase._mbctolower_l
@ cdecl _mbctombb(long) ucrtbase._mbctombb
@ cdecl _mbctombb_l(long ptr) ucrtbase._mbctombb_l
@ cdecl _mbctoupper(long) ucrtbase._mbctoupper
@ cdecl _mbctoupper_l(long ptr) ucrtbase._mbctoupper_l
@ cdecl _mblen_l(str long ptr) ucrtbase._mblen_l
@ cdecl _mbsbtype(str long) ucrtbase._mbsbtype
@ cdecl _mbsbtype_l(str long ptr) ucrtbase._mbsbtype_l
@ cdecl _mbscat_s(ptr long str) ucrtbase._mbscat_s
@ cdecl _mbscat_s_l(ptr long str ptr) ucrtbase._mbscat_s_l
@ cdecl _mbschr(str long) ucrtbase._mbschr
@ cdecl _mbschr_l(str long ptr) ucrtbase._mbschr_l
@ cdecl _mbscmp(str str) ucrtbase._mbscmp
@ cdecl _mbscmp_l(str str ptr) ucrtbase._mbscmp_l
@ cdecl _mbscoll(str str) ucrtbase._mbscoll
@ cdecl _mbscoll_l(str str ptr) ucrtbase._mbscoll_l
@ cdecl _mbscpy_s(ptr long str) ucrtbase._mbscpy_s
@ cdecl _mbscpy_s_l(ptr long str ptr) ucrtbase._mbscpy_s_l
@ cdecl _mbscspn(str str) ucrtbase._mbscspn
@ cdecl _mbscspn_l(str str ptr) ucrtbase._mbscspn_l
@ cdecl _mbsdec(ptr ptr) ucrtbase._mbsdec
@ cdecl _mbsdec_l(ptr ptr ptr) ucrtbase._mbsdec_l
@ cdecl _mbsdup(str) ucrtbase._mbsdup
@ cdecl _mbsicmp(str str) ucrtbase._mbsicmp
@ cdecl _mbsicmp_l(str str ptr) ucrtbase._mbsicmp_l
@ cdecl _mbsicoll(str str) ucrtbase._mbsicoll
@ cdecl _mbsicoll_l(str str ptr) ucrtbase._mbsicoll_l
@ cdecl _mbsinc(str) ucrtbase._mbsinc
@ cdecl _mbsinc_l(str ptr) ucrtbase._mbsinc_l
@ cdecl _mbslen(str) ucrtbase._mbslen
@ cdecl _mbslen_l(str ptr) ucrtbase._mbslen_l
@ cdecl _mbslwr(str) ucrtbase._mbslwr
@ cdecl _mbslwr_l(str ptr) ucrtbase._mbslwr_l
@ cdecl _mbslwr_s(str long) ucrtbase._mbslwr_s
@ cdecl _mbslwr_s_l(str long ptr) ucrtbase._mbslwr_s_l
@ cdecl _mbsnbcat(str str long) ucrtbase._mbsnbcat
@ cdecl _mbsnbcat_l(str str long ptr) ucrtbase._mbsnbcat_l
@ cdecl _mbsnbcat_s(str long ptr long) ucrtbase._mbsnbcat_s
@ cdecl _mbsnbcat_s_l(str long ptr long ptr) ucrtbase._mbsnbcat_s_l
@ cdecl _mbsnbcmp(str str long) ucrtbase._mbsnbcmp
@ cdecl _mbsnbcmp_l(str str long ptr) ucrtbase._mbsnbcmp_l
@ cdecl _mbsnbcnt(ptr long) ucrtbase._mbsnbcnt
@ cdecl _mbsnbcnt_l(ptr long ptr) ucrtbase._mbsnbcnt_l
@ cdecl _mbsnbcoll(str str long) ucrtbase._mbsnbcoll
@ cdecl _mbsnbcoll_l(str str long ptr) ucrtbase._mbsnbcoll_l
@ cdecl _mbsnbcpy(ptr str long) ucrtbase._mbsnbcpy
@ cdecl _mbsnbcpy_l(ptr str long ptr) ucrtbase._mbsnbcpy_l
@ cdecl _mbsnbcpy_s(ptr long str long) ucrtbase._mbsnbcpy_s
@ cdecl _mbsnbcpy_s_l(ptr long str long ptr) ucrtbase._mbsnbcpy_s_l
@ cdecl _mbsnbicmp(str str long) ucrtbase._mbsnbicmp
@ cdecl _mbsnbicmp_l(str str long ptr) ucrtbase._mbsnbicmp_l
@ cdecl _mbsnbicoll(str str long) ucrtbase._mbsnbicoll
@ cdecl _mbsnbicoll_l(str str long ptr) ucrtbase._mbsnbicoll_l
@ cdecl _mbsnbset(ptr long long) ucrtbase._mbsnbset
@ cdecl _mbsnbset_l(str long long ptr) ucrtbase._mbsnbset_l
@ stub _mbsnbset_s
@ stub _mbsnbset_s_l
@ cdecl _mbsncat(str str long) ucrtbase._mbsncat
@ cdecl _mbsncat_l(str str long ptr) ucrtbase._mbsncat_l
@ stub _mbsncat_s
@ stub _mbsncat_s_l
@ cdecl _mbsnccnt(str long) ucrtbase._mbsnccnt
@ cdecl _mbsnccnt_l(str long ptr) ucrtbase._mbsnccnt_l
@ cdecl _mbsncmp(str str long) ucrtbase._mbsncmp
@ cdecl _mbsncmp_l(str str long ptr) ucrtbase._mbsncmp_l
@ stub _mbsncoll(str str long)
@ stub _mbsncoll_l
@ cdecl _mbsncpy(ptr str long) ucrtbase._mbsncpy
@ cdecl _mbsncpy_l(ptr str long ptr) ucrtbase._mbsncpy_l
@ cdecl _mbsncpy_s(ptr long str long) ucrtbase._mbsncpy_s
@ cdecl _mbsncpy_s_l(ptr long str long ptr) ucrtbase._mbsncpy_s_l
@ cdecl _mbsnextc(str) ucrtbase._mbsnextc
@ cdecl _mbsnextc_l(str ptr) ucrtbase._mbsnextc_l
@ cdecl _mbsnicmp(str str long) ucrtbase._mbsnicmp
@ cdecl _mbsnicmp_l(str str long ptr) ucrtbase._mbsnicmp_l
@ stub _mbsnicoll(str str long)
@ stub _mbsnicoll_l
@ cdecl _mbsninc(str long) ucrtbase._mbsninc
@ stub _mbsninc_l
@ cdecl _mbsnlen(str long) ucrtbase._mbsnlen
@ cdecl _mbsnlen_l(str long ptr) ucrtbase._mbsnlen_l
@ cdecl _mbsnset(ptr long long) ucrtbase._mbsnset
@ cdecl _mbsnset_l(ptr long long ptr) ucrtbase._mbsnset_l
@ stub _mbsnset_s
@ stub _mbsnset_s_l
@ cdecl _mbspbrk(str str) ucrtbase._mbspbrk
@ cdecl _mbspbrk_l(str str ptr) ucrtbase._mbspbrk_l
@ cdecl _mbsrchr(str long) ucrtbase._mbsrchr
@ cdecl _mbsrchr_l(str long ptr) ucrtbase._mbsrchr_l
@ cdecl _mbsrev(str) ucrtbase._mbsrev
@ cdecl _mbsrev_l(str ptr) ucrtbase._mbsrev_l
@ cdecl _mbsset(ptr long) ucrtbase._mbsset
@ cdecl _mbsset_l(ptr long ptr) ucrtbase._mbsset_l
@ stub _mbsset_s
@ stub _mbsset_s_l
@ cdecl _mbsspn(str str) ucrtbase._mbsspn
@ cdecl _mbsspn_l(str str ptr) ucrtbase._mbsspn_l
@ cdecl _mbsspnp(str str) ucrtbase._mbsspnp
@ cdecl _mbsspnp_l(str str ptr) ucrtbase._mbsspnp_l
@ cdecl _mbsstr(str str) ucrtbase._mbsstr
@ stub _mbsstr_l
@ cdecl _mbstok(str str) ucrtbase._mbstok
@ cdecl _mbstok_l(str str ptr) ucrtbase._mbstok_l
@ cdecl _mbstok_s(str str ptr) ucrtbase._mbstok_s
@ cdecl _mbstok_s_l(str str ptr ptr) ucrtbase._mbstok_s_l
@ cdecl _mbstowcs_l(ptr str long ptr) ucrtbase._mbstowcs_l
@ cdecl _mbstowcs_s_l(ptr ptr long str long ptr) ucrtbase._mbstowcs_s_l
@ cdecl _mbstrlen(str) ucrtbase._mbstrlen
@ cdecl _mbstrlen_l(str ptr) ucrtbase._mbstrlen_l
@ stub _mbstrnlen
@ stub _mbstrnlen_l
@ cdecl _mbsupr(str) ucrtbase._mbsupr
@ cdecl _mbsupr_l(str ptr) ucrtbase._mbsupr_l
@ cdecl _mbsupr_s(str long) ucrtbase._mbsupr_s
@ cdecl _mbsupr_s_l(str long ptr) ucrtbase._mbsupr_s_l
@ cdecl _mbtowc_l(ptr str long ptr) ucrtbase._mbtowc_l
@ cdecl _memccpy(ptr ptr long long) ucrtbase._memccpy
@ cdecl _memicmp(str str long) ucrtbase._memicmp
@ cdecl _memicmp_l(str str long ptr) ucrtbase._memicmp_l
@ cdecl _mkdir(str) ucrtbase._mkdir
@ cdecl _mkgmtime32(ptr) ucrtbase._mkgmtime32
@ cdecl _mkgmtime64(ptr) ucrtbase._mkgmtime64
@ cdecl _mktemp(str) ucrtbase._mktemp
@ cdecl _mktemp_s(str long) ucrtbase._mktemp_s
@ cdecl _mktime32(ptr) ucrtbase._mktime32
@ cdecl _mktime64(ptr) ucrtbase._mktime64
@ cdecl _msize(ptr) ucrtbase._msize
@ cdecl _nextafter(double double) ucrtbase._nextafter
@ cdecl -arch=x86_64 _nextafterf(float float) ucrtbase._nextafterf
@ cdecl -arch=i386 _o__CIacos() ucrtbase._o__CIacos
@ cdecl -arch=i386 _o__CIasin() ucrtbase._o__CIasin
@ cdecl -arch=i386 _o__CIatan() ucrtbase._o__CIatan
@ cdecl -arch=i386 _o__CIatan2() ucrtbase._o__CIatan2
@ cdecl -arch=i386 _o__CIcos() ucrtbase._o__CIcos
@ cdecl -arch=i386 _o__CIcosh() ucrtbase._o__CIcosh
@ cdecl -arch=i386 _o__CIexp() ucrtbase._o__CIexp
@ cdecl -arch=i386 _o__CIfmod() ucrtbase._o__CIfmod
@ cdecl -arch=i386 _o__CIlog() ucrtbase._o__CIlog
@ cdecl -arch=i386 _o__CIlog10() ucrtbase._o__CIlog10
@ cdecl -arch=i386 _o__CIpow() ucrtbase._o__CIpow
@ cdecl -arch=i386 _o__CIsin() ucrtbase._o__CIsin
@ cdecl -arch=i386 _o__CIsinh() ucrtbase._o__CIsinh
@ cdecl -arch=i386 _o__CIsqrt() ucrtbase._o__CIsqrt
@ cdecl -arch=i386 _o__CItan() ucrtbase._o__CItan
@ cdecl -arch=i386 _o__CItanh() ucrtbase._o__CItanh
@ cdecl _o__Getdays() ucrtbase._o__Getdays
@ cdecl _o__Getmonths() ucrtbase._o__Getmonths
@ cdecl _o__Gettnames() ucrtbase._o__Gettnames
@ cdecl _o__Strftime(ptr long str ptr ptr) ucrtbase._o__Strftime
@ cdecl _o__W_Getdays() ucrtbase._o__W_Getdays
@ cdecl _o__W_Getmonths() ucrtbase._o__W_Getmonths
@ cdecl _o__W_Gettnames() ucrtbase._o__W_Gettnames
@ cdecl _o__Wcsftime(ptr long wstr ptr ptr) ucrtbase._o__Wcsftime
@ cdecl _o____lc_codepage_func() ucrtbase._o____lc_codepage_func
@ cdecl _o____lc_collate_cp_func() ucrtbase._o____lc_collate_cp_func
@ cdecl _o____lc_locale_name_func() ucrtbase._o____lc_locale_name_func
@ cdecl _o____mb_cur_max_func() ucrtbase._o____mb_cur_max_func
@ cdecl _o___acrt_iob_func(long) ucrtbase._o___acrt_iob_func
@ cdecl _o___conio_common_vcprintf(int64 str ptr ptr) ucrtbase._o___conio_common_vcprintf
@ stub _o___conio_common_vcprintf_p
@ stub _o___conio_common_vcprintf_s
@ stub _o___conio_common_vcscanf
@ cdecl _o___conio_common_vcwprintf(int64 wstr ptr ptr) ucrtbase._o___conio_common_vcwprintf
@ stub _o___conio_common_vcwprintf_p
@ stub _o___conio_common_vcwprintf_s
@ stub _o___conio_common_vcwscanf
@ cdecl _o___daylight() ucrtbase._o___daylight
@ cdecl _o___dstbias() ucrtbase._o___dstbias
@ cdecl _o___fpe_flt_rounds() ucrtbase._o___fpe_flt_rounds
@ cdecl -arch=i386 -norelay _o___libm_sse2_acos() ucrtbase._o___libm_sse2_acos
@ cdecl -arch=i386 -norelay _o___libm_sse2_acosf() ucrtbase._o___libm_sse2_acosf
@ cdecl -arch=i386 -norelay _o___libm_sse2_asin() ucrtbase._o___libm_sse2_asin
@ cdecl -arch=i386 -norelay _o___libm_sse2_asinf() ucrtbase._o___libm_sse2_asinf
@ cdecl -arch=i386 -norelay _o___libm_sse2_atan() ucrtbase._o___libm_sse2_atan
@ cdecl -arch=i386 -norelay _o___libm_sse2_atan2() ucrtbase._o___libm_sse2_atan2
@ cdecl -arch=i386 -norelay _o___libm_sse2_atanf() ucrtbase._o___libm_sse2_atanf
@ cdecl -arch=i386 -norelay _o___libm_sse2_cos() ucrtbase._o___libm_sse2_cos
@ cdecl -arch=i386 -norelay _o___libm_sse2_cosf() ucrtbase._o___libm_sse2_cosf
@ cdecl -arch=i386 -norelay _o___libm_sse2_exp() ucrtbase._o___libm_sse2_exp
@ cdecl -arch=i386 -norelay _o___libm_sse2_expf() ucrtbase._o___libm_sse2_expf
@ cdecl -arch=i386 -norelay _o___libm_sse2_log() ucrtbase._o___libm_sse2_log
@ cdecl -arch=i386 -norelay _o___libm_sse2_log10() ucrtbase._o___libm_sse2_log10
@ cdecl -arch=i386 -norelay _o___libm_sse2_log10f() ucrtbase._o___libm_sse2_log10f
@ cdecl -arch=i386 -norelay _o___libm_sse2_logf() ucrtbase._o___libm_sse2_logf
@ cdecl -arch=i386 -norelay _o___libm_sse2_pow() ucrtbase._o___libm_sse2_pow
@ cdecl -arch=i386 -norelay _o___libm_sse2_powf() ucrtbase._o___libm_sse2_powf
@ cdecl -arch=i386 -norelay _o___libm_sse2_sin() ucrtbase._o___libm_sse2_sin
@ cdecl -arch=i386 -norelay _o___libm_sse2_sinf() ucrtbase._o___libm_sse2_sinf
@ cdecl -arch=i386 -norelay _o___libm_sse2_tan() ucrtbase._o___libm_sse2_tan
@ cdecl -arch=i386 -norelay _o___libm_sse2_tanf() ucrtbase._o___libm_sse2_tanf
@ cdecl _o___p___argc() ucrtbase._o___p___argc
@ cdecl _o___p___argv() ucrtbase._o___p___argv
@ cdecl _o___p___wargv() ucrtbase._o___p___wargv
@ cdecl _o___p__acmdln() ucrtbase._o___p__acmdln
@ cdecl _o___p__commode() ucrtbase._o___p__commode
@ cdecl _o___p__environ() ucrtbase._o___p__environ
@ cdecl _o___p__fmode() ucrtbase._o___p__fmode
@ stub _o___p__mbcasemap
@ cdecl _o___p__mbctype() ucrtbase._o___p__mbctype
@ cdecl _o___p__pgmptr() ucrtbase._o___p__pgmptr
@ cdecl _o___p__wcmdln() ucrtbase._o___p__wcmdln
@ cdecl _o___p__wenviron() ucrtbase._o___p__wenviron
@ cdecl _o___p__wpgmptr() ucrtbase._o___p__wpgmptr
@ cdecl _o___pctype_func() ucrtbase._o___pctype_func
@ stub _o___pwctype_func
@ cdecl _o___std_exception_copy(ptr ptr) ucrtbase._o___std_exception_copy
@ cdecl _o___std_exception_destroy(ptr) ucrtbase._o___std_exception_destroy
@ cdecl _o___std_type_info_destroy_list(ptr) ucrtbase._o___std_type_info_destroy_list
@ cdecl _o___std_type_info_name(ptr ptr) ucrtbase._o___std_type_info_name
@ cdecl _o___stdio_common_vfprintf(int64 ptr str ptr ptr) ucrtbase._o___stdio_common_vfprintf
@ cdecl _o___stdio_common_vfprintf_p(int64 ptr str ptr ptr) ucrtbase._o___stdio_common_vfprintf_p
@ cdecl _o___stdio_common_vfprintf_s(int64 ptr str ptr ptr) ucrtbase._o___stdio_common_vfprintf_s
@ cdecl _o___stdio_common_vfscanf(int64 ptr str ptr ptr) ucrtbase._o___stdio_common_vfscanf
@ cdecl _o___stdio_common_vfwprintf(int64 ptr wstr ptr ptr) ucrtbase._o___stdio_common_vfwprintf
@ cdecl _o___stdio_common_vfwprintf_p(int64 ptr wstr ptr ptr) ucrtbase._o___stdio_common_vfwprintf_p
@ cdecl _o___stdio_common_vfwprintf_s(int64 ptr wstr ptr ptr) ucrtbase._o___stdio_common_vfwprintf_s
@ cdecl _o___stdio_common_vfwscanf(int64 ptr wstr ptr ptr) ucrtbase._o___stdio_common_vfwscanf
@ cdecl _o___stdio_common_vsnprintf_s(int64 ptr long long str ptr ptr) ucrtbase._o___stdio_common_vsnprintf_s
@ cdecl _o___stdio_common_vsnwprintf_s(int64 ptr long long wstr ptr ptr) ucrtbase._o___stdio_common_vsnwprintf_s
@ cdecl _o___stdio_common_vsprintf(int64 ptr long str ptr ptr) ucrtbase._o___stdio_common_vsprintf
@ cdecl _o___stdio_common_vsprintf_p(int64 ptr long str ptr ptr) ucrtbase._o___stdio_common_vsprintf_p
@ cdecl _o___stdio_common_vsprintf_s(int64 ptr long str ptr ptr) ucrtbase._o___stdio_common_vsprintf_s
@ cdecl _o___stdio_common_vsscanf(int64 ptr long str ptr ptr) ucrtbase._o___stdio_common_vsscanf
@ cdecl _o___stdio_common_vswprintf(int64 ptr long wstr ptr ptr) ucrtbase._o___stdio_common_vswprintf
@ cdecl _o___stdio_common_vswprintf_p(int64 ptr long wstr ptr ptr) ucrtbase._o___stdio_common_vswprintf_p
@ cdecl _o___stdio_common_vswprintf_s(int64 ptr long wstr ptr ptr) ucrtbase._o___stdio_common_vswprintf_s
@ cdecl _o___stdio_common_vswscanf(int64 ptr long wstr ptr ptr) ucrtbase._o___stdio_common_vswscanf
@ cdecl _o___timezone() ucrtbase._o___timezone
@ cdecl _o___tzname() ucrtbase._o___tzname
@ cdecl _o___wcserror(wstr) ucrtbase._o___wcserror
@ cdecl _o__access(str long) ucrtbase._o__access
@ cdecl _o__access_s(str long) ucrtbase._o__access_s
@ cdecl _o__aligned_free(ptr) ucrtbase._o__aligned_free
@ cdecl _o__aligned_malloc(long long) ucrtbase._o__aligned_malloc
@ cdecl _o__aligned_msize(ptr long long) ucrtbase._o__aligned_msize
@ cdecl _o__aligned_offset_malloc(long long long) ucrtbase._o__aligned_offset_malloc
@ cdecl _o__aligned_offset_realloc(ptr long long long) ucrtbase._o__aligned_offset_realloc
@ stub _o__aligned_offset_recalloc
@ cdecl _o__aligned_realloc(ptr long long) ucrtbase._o__aligned_realloc
@ stub _o__aligned_recalloc
@ cdecl _o__atodbl(ptr str) ucrtbase._o__atodbl
@ cdecl _o__atodbl_l(ptr str ptr) ucrtbase._o__atodbl_l
@ cdecl _o__atof_l(str ptr) ucrtbase._o__atof_l
@ cdecl _o__atoflt(ptr str) ucrtbase._o__atoflt
@ cdecl _o__atoflt_l(ptr str ptr) ucrtbase._o__atoflt_l
@ cdecl -ret64 _o__atoi64(str) ucrtbase._o__atoi64
@ cdecl -ret64 _o__atoi64_l(str ptr) ucrtbase._o__atoi64_l
@ cdecl _o__atoi_l(str ptr) ucrtbase._o__atoi_l
@ cdecl _o__atol_l(str ptr) ucrtbase._o__atol_l
@ cdecl _o__atoldbl(ptr str) ucrtbase._o__atoldbl
@ cdecl _o__atoldbl_l(ptr str ptr) ucrtbase._o__atoldbl_l
@ cdecl -ret64 _o__atoll_l(str ptr) ucrtbase._o__atoll_l
@ cdecl _o__beep(long long) ucrtbase._o__beep
@ cdecl _o__beginthread(ptr long ptr) ucrtbase._o__beginthread
@ cdecl _o__beginthreadex(ptr long ptr ptr long ptr) ucrtbase._o__beginthreadex
@ cdecl _o__cabs(long) ucrtbase._o__cabs
@ cdecl _o__callnewh(long) ucrtbase._o__callnewh
@ cdecl _o__calloc_base(long long) ucrtbase._o__calloc_base
@ cdecl _o__cexit() ucrtbase._o__cexit
@ cdecl _o__cgets(ptr) ucrtbase._o__cgets
@ stub _o__cgets_s
@ stub _o__cgetws
@ stub _o__cgetws_s
@ cdecl _o__chdir(str) ucrtbase._o__chdir
@ cdecl _o__chdrive(long) ucrtbase._o__chdrive
@ cdecl _o__chmod(str long) ucrtbase._o__chmod
@ cdecl _o__chsize(long long) ucrtbase._o__chsize
@ cdecl _o__chsize_s(long int64) ucrtbase._o__chsize_s
@ cdecl _o__close(long) ucrtbase._o__close
@ cdecl _o__commit(long) ucrtbase._o__commit
@ cdecl _o__configthreadlocale(long) ucrtbase._o__configthreadlocale
@ cdecl _o__configure_narrow_argv(long) ucrtbase._o__configure_narrow_argv
@ cdecl _o__configure_wide_argv(long) ucrtbase._o__configure_wide_argv
@ cdecl _o__controlfp_s(ptr long long) ucrtbase._o__controlfp_s
@ cdecl _o__cputs(str) ucrtbase._o__cputs
@ cdecl _o__cputws(wstr) ucrtbase._o__cputws
@ cdecl _o__creat(str long) ucrtbase._o__creat
@ cdecl _o__create_locale(long str) ucrtbase._o__create_locale
@ cdecl _o__crt_atexit(ptr) ucrtbase._o__crt_atexit
@ cdecl _o__ctime32_s(str long ptr) ucrtbase._o__ctime32_s
@ cdecl _o__ctime64_s(str long ptr) ucrtbase._o__ctime64_s
@ cdecl _o__cwait(ptr long long) ucrtbase._o__cwait
@ stub _o__d_int
@ cdecl _o__dclass(double) ucrtbase._o__dclass
@ cdecl _o__difftime32(long long) ucrtbase._o__difftime32
@ cdecl _o__difftime64(int64 int64) ucrtbase._o__difftime64
@ stub _o__dlog
@ stub _o__dnorm
@ cdecl _o__dpcomp(double double) ucrtbase._o__dpcomp
@ stub _o__dpoly
@ stub _o__dscale
@ cdecl _o__dsign(double) ucrtbase._o__dsign
@ stub _o__dsin
@ cdecl _o__dtest(ptr) ucrtbase._o__dtest
@ stub _o__dunscale
@ cdecl _o__dup(long) ucrtbase._o__dup
@ cdecl _o__dup2(long long) ucrtbase._o__dup2
@ cdecl _o__dupenv_s(ptr ptr str) ucrtbase._o__dupenv_s
@ cdecl _o__ecvt(double long ptr ptr) ucrtbase._o__ecvt
@ cdecl _o__ecvt_s(str long double long ptr ptr) ucrtbase._o__ecvt_s
@ cdecl _o__endthread() ucrtbase._o__endthread
@ cdecl _o__endthreadex(long) ucrtbase._o__endthreadex
@ cdecl _o__eof(long) ucrtbase._o__eof
@ cdecl _o__errno() ucrtbase._o__errno
@ cdecl _o__except1(long long double double long ptr) ucrtbase._o__except1
@ cdecl _o__execute_onexit_table(ptr) ucrtbase._o__execute_onexit_table
@ cdecl _o__execv(str ptr) ucrtbase._o__execv
@ cdecl _o__execve(str ptr ptr) ucrtbase._o__execve
@ cdecl _o__execvp(str ptr) ucrtbase._o__execvp
@ cdecl _o__execvpe(str ptr ptr) ucrtbase._o__execvpe
@ cdecl _o__exit(long) ucrtbase._o__exit
@ cdecl _o__expand(ptr long) ucrtbase._o__expand
@ cdecl _o__fclose_nolock(ptr) ucrtbase._o__fclose_nolock
@ cdecl _o__fcloseall() ucrtbase._o__fcloseall
@ cdecl _o__fcvt(double long ptr ptr) ucrtbase._o__fcvt
@ cdecl _o__fcvt_s(ptr long double long ptr ptr) ucrtbase._o__fcvt_s
@ stub _o__fd_int
@ cdecl _o__fdclass(float) ucrtbase._o__fdclass
@ stub _o__fdexp
@ stub _o__fdlog
@ cdecl _o__fdopen(long str) ucrtbase._o__fdopen
@ cdecl _o__fdpcomp(float float) ucrtbase._o__fdpcomp
@ stub _o__fdpoly
@ stub _o__fdscale
@ cdecl _o__fdsign(float) ucrtbase._o__fdsign
@ stub _o__fdsin
@ cdecl _o__fflush_nolock(ptr) ucrtbase._o__fflush_nolock
@ cdecl _o__fgetc_nolock(ptr) ucrtbase._o__fgetc_nolock
@ cdecl _o__fgetchar() ucrtbase._o__fgetchar
@ cdecl _o__fgetwc_nolock(ptr) ucrtbase._o__fgetwc_nolock
@ cdecl _o__fgetwchar() ucrtbase._o__fgetwchar
@ cdecl _o__filelength(long) ucrtbase._o__filelength
@ cdecl -ret64 _o__filelengthi64(long) ucrtbase._o__filelengthi64
@ cdecl _o__fileno(ptr) ucrtbase._o__fileno
@ cdecl _o__findclose(long) ucrtbase._o__findclose
@ cdecl _o__findfirst32(str ptr) ucrtbase._o__findfirst32
@ stub _o__findfirst32i64
@ cdecl _o__findfirst64(str ptr) ucrtbase._o__findfirst64
@ cdecl _o__findfirst64i32(str ptr) ucrtbase._o__findfirst64i32
@ cdecl _o__findnext32(long ptr) ucrtbase._o__findnext32
@ stub _o__findnext32i64
@ cdecl _o__findnext64(long ptr) ucrtbase._o__findnext64
@ cdecl _o__findnext64i32(long ptr) ucrtbase._o__findnext64i32
@ cdecl _o__flushall() ucrtbase._o__flushall
@ cdecl _o__fpclass(double) ucrtbase._o__fpclass
@ cdecl -arch=!i386 _o__fpclassf(float) ucrtbase._o__fpclassf
@ cdecl _o__fputc_nolock(long ptr) ucrtbase._o__fputc_nolock
@ cdecl _o__fputchar(long) ucrtbase._o__fputchar
@ cdecl _o__fputwc_nolock(long ptr) ucrtbase._o__fputwc_nolock
@ cdecl _o__fputwchar(long) ucrtbase._o__fputwchar
@ cdecl _o__fread_nolock(ptr long long ptr) ucrtbase._o__fread_nolock
@ cdecl _o__fread_nolock_s(ptr long long long ptr) ucrtbase._o__fread_nolock_s
@ cdecl _o__free_base(ptr) ucrtbase._o__free_base
@ cdecl _o__free_locale(ptr) ucrtbase._o__free_locale
@ cdecl _o__fseek_nolock(ptr long long) ucrtbase._o__fseek_nolock
@ cdecl _o__fseeki64(ptr int64 long) ucrtbase._o__fseeki64
@ cdecl _o__fseeki64_nolock(ptr int64 long) ucrtbase._o__fseeki64_nolock
@ cdecl _o__fsopen(str str long) ucrtbase._o__fsopen
@ cdecl _o__fstat32(long ptr) ucrtbase._o__fstat32
@ cdecl _o__fstat32i64(long ptr) ucrtbase._o__fstat32i64
@ cdecl _o__fstat64(long ptr) ucrtbase._o__fstat64
@ cdecl _o__fstat64i32(long ptr) ucrtbase._o__fstat64i32
@ cdecl _o__ftell_nolock(ptr) ucrtbase._o__ftell_nolock
@ cdecl -ret64 _o__ftelli64(ptr) ucrtbase._o__ftelli64
@ cdecl -ret64 _o__ftelli64_nolock(ptr) ucrtbase._o__ftelli64_nolock
@ cdecl _o__ftime32(ptr) ucrtbase._o__ftime32
@ cdecl _o__ftime32_s(ptr) ucrtbase._o__ftime32_s
@ cdecl _o__ftime64(ptr) ucrtbase._o__ftime64
@ cdecl _o__ftime64_s(ptr) ucrtbase._o__ftime64_s
@ cdecl _o__fullpath(ptr str long) ucrtbase._o__fullpath
@ cdecl _o__futime32(long ptr) ucrtbase._o__futime32
@ cdecl _o__futime64(long ptr) ucrtbase._o__futime64
@ cdecl _o__fwrite_nolock(ptr long long ptr) ucrtbase._o__fwrite_nolock
@ cdecl _o__gcvt(double long str) ucrtbase._o__gcvt
@ cdecl _o__gcvt_s(ptr long double long) ucrtbase._o__gcvt_s
@ cdecl _o__get_daylight(ptr) ucrtbase._o__get_daylight
@ cdecl _o__get_doserrno(ptr) ucrtbase._o__get_doserrno
@ cdecl _o__get_dstbias(ptr) ucrtbase._o__get_dstbias
@ cdecl _o__get_errno(ptr) ucrtbase._o__get_errno
@ cdecl _o__get_fmode(ptr) ucrtbase._o__get_fmode
@ cdecl _o__get_heap_handle() ucrtbase._o__get_heap_handle
@ cdecl _o__get_initial_narrow_environment() ucrtbase._o__get_initial_narrow_environment
@ cdecl _o__get_initial_wide_environment() ucrtbase._o__get_initial_wide_environment
@ cdecl _o__get_invalid_parameter_handler() ucrtbase._o__get_invalid_parameter_handler
@ cdecl _o__get_narrow_winmain_command_line() ucrtbase._o__get_narrow_winmain_command_line
@ cdecl _o__get_osfhandle(long) ucrtbase._o__get_osfhandle
@ cdecl _o__get_pgmptr(ptr) ucrtbase._o__get_pgmptr
@ cdecl _o__get_stream_buffer_pointers(ptr ptr ptr ptr) ucrtbase._o__get_stream_buffer_pointers
@ cdecl _o__get_terminate() ucrtbase._o__get_terminate
@ cdecl _o__get_thread_local_invalid_parameter_handler() ucrtbase._o__get_thread_local_invalid_parameter_handler
@ cdecl _o__get_timezone(ptr) ucrtbase._o__get_timezone
@ cdecl _o__get_tzname(ptr str long long) ucrtbase._o__get_tzname
@ cdecl _o__get_wide_winmain_command_line() ucrtbase._o__get_wide_winmain_command_line
@ cdecl _o__get_wpgmptr(ptr) ucrtbase._o__get_wpgmptr
@ cdecl _o__getc_nolock(ptr) ucrtbase._o__getc_nolock
@ cdecl _o__getch() ucrtbase._o__getch
@ cdecl _o__getch_nolock() ucrtbase._o__getch_nolock
@ cdecl _o__getche() ucrtbase._o__getche
@ cdecl _o__getche_nolock() ucrtbase._o__getche_nolock
@ cdecl _o__getcwd(str long) ucrtbase._o__getcwd
@ cdecl _o__getdcwd(long str long) ucrtbase._o__getdcwd
@ cdecl _o__getdiskfree(long ptr) ucrtbase._o__getdiskfree
@ cdecl _o__getdllprocaddr(long str long) ucrtbase._o__getdllprocaddr
@ cdecl _o__getdrive() ucrtbase._o__getdrive
@ cdecl _o__getdrives() ucrtbase._o__getdrives
@ cdecl _o__getmbcp() ucrtbase._o__getmbcp
@ stub _o__getsystime
@ cdecl _o__getw(ptr) ucrtbase._o__getw
@ cdecl _o__getwc_nolock(ptr) ucrtbase._o__getwc_nolock
@ cdecl _o__getwch() ucrtbase._o__getwch
@ cdecl _o__getwch_nolock() ucrtbase._o__getwch_nolock
@ cdecl _o__getwche() ucrtbase._o__getwche
@ cdecl _o__getwche_nolock() ucrtbase._o__getwche_nolock
@ cdecl _o__getws(ptr) ucrtbase._o__getws
@ stub _o__getws_s
@ cdecl _o__gmtime32(ptr) ucrtbase._o__gmtime32
@ cdecl _o__gmtime32_s(ptr ptr) ucrtbase._o__gmtime32_s
@ cdecl _o__gmtime64(ptr) ucrtbase._o__gmtime64
@ cdecl _o__gmtime64_s(ptr ptr) ucrtbase._o__gmtime64_s
@ cdecl _o__heapchk() ucrtbase._o__heapchk
@ cdecl _o__heapmin() ucrtbase._o__heapmin
@ cdecl _o__hypot(double double) ucrtbase._o__hypot
@ cdecl _o__hypotf(float float) ucrtbase._o__hypotf
@ cdecl _o__i64toa(int64 ptr long) ucrtbase._o__i64toa
@ cdecl _o__i64toa_s(int64 ptr long long) ucrtbase._o__i64toa_s
@ cdecl _o__i64tow(int64 ptr long) ucrtbase._o__i64tow
@ cdecl _o__i64tow_s(int64 ptr long long) ucrtbase._o__i64tow_s
@ cdecl _o__initialize_narrow_environment() ucrtbase._o__initialize_narrow_environment
@ cdecl _o__initialize_onexit_table(ptr) ucrtbase._o__initialize_onexit_table
@ cdecl _o__initialize_wide_environment() ucrtbase._o__initialize_wide_environment
@ cdecl _o__invalid_parameter_noinfo() ucrtbase._o__invalid_parameter_noinfo
@ cdecl _o__invalid_parameter_noinfo_noreturn() ucrtbase._o__invalid_parameter_noinfo_noreturn
@ cdecl _o__isatty(long) ucrtbase._o__isatty
@ cdecl _o__isctype(long long) ucrtbase._o__isctype
@ cdecl _o__isctype_l(long long ptr) ucrtbase._o__isctype_l
@ cdecl _o__isleadbyte_l(long ptr) ucrtbase._o__isleadbyte_l
@ stub _o__ismbbalnum
@ stub _o__ismbbalnum_l
@ stub _o__ismbbalpha
@ stub _o__ismbbalpha_l
@ stub _o__ismbbblank
@ stub _o__ismbbblank_l
@ stub _o__ismbbgraph
@ stub _o__ismbbgraph_l
@ stub _o__ismbbkalnum
@ stub _o__ismbbkalnum_l
@ cdecl _o__ismbbkana(long) ucrtbase._o__ismbbkana
@ cdecl _o__ismbbkana_l(long ptr) ucrtbase._o__ismbbkana_l
@ stub _o__ismbbkprint
@ stub _o__ismbbkprint_l
@ stub _o__ismbbkpunct
@ stub _o__ismbbkpunct_l
@ cdecl _o__ismbblead(long) ucrtbase._o__ismbblead
@ cdecl _o__ismbblead_l(long ptr) ucrtbase._o__ismbblead_l
@ stub _o__ismbbprint
@ stub _o__ismbbprint_l
@ stub _o__ismbbpunct
@ stub _o__ismbbpunct_l
@ cdecl _o__ismbbtrail(long) ucrtbase._o__ismbbtrail
@ cdecl _o__ismbbtrail_l(long ptr) ucrtbase._o__ismbbtrail_l
@ cdecl _o__ismbcalnum(long) ucrtbase._o__ismbcalnum
@ cdecl _o__ismbcalnum_l(long ptr) ucrtbase._o__ismbcalnum_l
@ cdecl _o__ismbcalpha(long) ucrtbase._o__ismbcalpha
@ cdecl _o__ismbcalpha_l(long ptr) ucrtbase._o__ismbcalpha_l
@ stub _o__ismbcblank
@ stub _o__ismbcblank_l
@ cdecl _o__ismbcdigit(long) ucrtbase._o__ismbcdigit
@ cdecl _o__ismbcdigit_l(long ptr) ucrtbase._o__ismbcdigit_l
@ cdecl _o__ismbcgraph(long) ucrtbase._o__ismbcgraph
@ cdecl _o__ismbcgraph_l(long ptr) ucrtbase._o__ismbcgraph_l
@ cdecl _o__ismbchira(long) ucrtbase._o__ismbchira
@ cdecl _o__ismbchira_l(long ptr) ucrtbase._o__ismbchira_l
@ cdecl _o__ismbckata(long) ucrtbase._o__ismbckata
@ cdecl _o__ismbckata_l(long ptr) ucrtbase._o__ismbckata_l
@ cdecl _o__ismbcl0(long) ucrtbase._o__ismbcl0
@ cdecl _o__ismbcl0_l(long ptr) ucrtbase._o__ismbcl0_l
@ cdecl _o__ismbcl1(long) ucrtbase._o__ismbcl1
@ cdecl _o__ismbcl1_l(long ptr) ucrtbase._o__ismbcl1_l
@ cdecl _o__ismbcl2(long) ucrtbase._o__ismbcl2
@ cdecl _o__ismbcl2_l(long ptr) ucrtbase._o__ismbcl2_l
@ cdecl _o__ismbclegal(long) ucrtbase._o__ismbclegal
@ cdecl _o__ismbclegal_l(long ptr) ucrtbase._o__ismbclegal_l
@ stub _o__ismbclower
@ cdecl _o__ismbclower_l(long ptr) ucrtbase._o__ismbclower_l
@ cdecl _o__ismbcprint(long) ucrtbase._o__ismbcprint
@ cdecl _o__ismbcprint_l(long ptr) ucrtbase._o__ismbcprint_l
@ cdecl _o__ismbcpunct(long) ucrtbase._o__ismbcpunct
@ cdecl _o__ismbcpunct_l(long ptr) ucrtbase._o__ismbcpunct_l
@ cdecl _o__ismbcspace(long) ucrtbase._o__ismbcspace
@ cdecl _o__ismbcspace_l(long ptr) ucrtbase._o__ismbcspace_l
@ cdecl _o__ismbcsymbol(long) ucrtbase._o__ismbcsymbol
@ cdecl _o__ismbcsymbol_l(long ptr) ucrtbase._o__ismbcsymbol_l
@ cdecl _o__ismbcupper(long) ucrtbase._o__ismbcupper
@ cdecl _o__ismbcupper_l(long ptr) ucrtbase._o__ismbcupper_l
@ cdecl _o__ismbslead(ptr ptr) ucrtbase._o__ismbslead
@ cdecl _o__ismbslead_l(ptr ptr ptr) ucrtbase._o__ismbslead_l
@ cdecl _o__ismbstrail(ptr ptr) ucrtbase._o__ismbstrail
@ cdecl _o__ismbstrail_l(ptr ptr ptr) ucrtbase._o__ismbstrail_l
@ cdecl _o__iswctype_l(long long ptr) ucrtbase._o__iswctype_l
@ cdecl _o__itoa(long ptr long) ucrtbase._o__itoa
@ cdecl _o__itoa_s(long ptr long long) ucrtbase._o__itoa_s
@ cdecl _o__itow(long ptr long) ucrtbase._o__itow
@ cdecl _o__itow_s(long ptr long long) ucrtbase._o__itow_s
@ cdecl _o__j0(double) ucrtbase._o__j0
@ cdecl _o__j1(double) ucrtbase._o__j1
@ cdecl _o__jn(long double) ucrtbase._o__jn
@ cdecl _o__kbhit() ucrtbase._o__kbhit
@ stub _o__ld_int
@ cdecl _o__ldclass(double) ucrtbase._o__ldclass
@ stub _o__ldexp
@ stub _o__ldlog
@ cdecl _o__ldpcomp(double double) ucrtbase._o__ldpcomp
@ stub _o__ldpoly
@ stub _o__ldscale
@ cdecl _o__ldsign(double) ucrtbase._o__ldsign
@ stub _o__ldsin
@ cdecl _o__ldtest(ptr) ucrtbase._o__ldtest
@ stub _o__ldunscale
@ cdecl _o__lfind(ptr ptr ptr long ptr) ucrtbase._o__lfind
@ cdecl _o__lfind_s(ptr ptr ptr long ptr ptr) ucrtbase._o__lfind_s
@ cdecl -arch=i386 -norelay _o__libm_sse2_acos_precise() ucrtbase._o__libm_sse2_acos_precise
@ cdecl -arch=i386 -norelay _o__libm_sse2_asin_precise() ucrtbase._o__libm_sse2_asin_precise
@ cdecl -arch=i386 -norelay _o__libm_sse2_atan_precise() ucrtbase._o__libm_sse2_atan_precise
@ cdecl -arch=i386 -norelay _o__libm_sse2_cos_precise() ucrtbase._o__libm_sse2_cos_precise
@ cdecl -arch=i386 -norelay _o__libm_sse2_exp_precise() ucrtbase._o__libm_sse2_exp_precise
@ cdecl -arch=i386 -norelay _o__libm_sse2_log10_precise() ucrtbase._o__libm_sse2_log10_precise
@ cdecl -arch=i386 -norelay _o__libm_sse2_log_precise() ucrtbase._o__libm_sse2_log_precise
@ cdecl -arch=i386 -norelay _o__libm_sse2_pow_precise() ucrtbase._o__libm_sse2_pow_precise
@ cdecl -arch=i386 -norelay _o__libm_sse2_sin_precise() ucrtbase._o__libm_sse2_sin_precise
@ cdecl -arch=i386 -norelay _o__libm_sse2_sqrt_precise() ucrtbase._o__libm_sse2_sqrt_precise
@ cdecl -arch=i386 -norelay _o__libm_sse2_tan_precise() ucrtbase._o__libm_sse2_tan_precise
@ cdecl _o__loaddll(str) ucrtbase._o__loaddll
@ cdecl _o__localtime32(ptr) ucrtbase._o__localtime32
@ cdecl _o__localtime32_s(ptr ptr) ucrtbase._o__localtime32_s
@ cdecl _o__localtime64(ptr) ucrtbase._o__localtime64
@ cdecl _o__localtime64_s(ptr ptr) ucrtbase._o__localtime64_s
@ cdecl _o__lock_file(ptr) ucrtbase._o__lock_file
@ cdecl _o__locking(long long long) ucrtbase._o__locking
@ cdecl _o__logb(double) ucrtbase._o__logb
@ cdecl -arch=!i386 _o__logbf(float) ucrtbase._o__logbf
@ cdecl _o__lsearch(ptr ptr ptr long ptr) ucrtbase._o__lsearch
@ stub _o__lsearch_s
@ cdecl _o__lseek(long long long) ucrtbase._o__lseek
@ cdecl -ret64 _o__lseeki64(long int64 long) ucrtbase._o__lseeki64
@ cdecl _o__ltoa(long ptr long) ucrtbase._o__ltoa
@ cdecl _o__ltoa_s(long ptr long long) ucrtbase._o__ltoa_s
@ cdecl _o__ltow(long ptr long) ucrtbase._o__ltow
@ cdecl _o__ltow_s(long ptr long long) ucrtbase._o__ltow_s
@ cdecl _o__makepath(ptr str str str str) ucrtbase._o__makepath
@ cdecl _o__makepath_s(ptr long str str str str) ucrtbase._o__makepath_s
@ cdecl _o__malloc_base(long) ucrtbase._o__malloc_base
@ cdecl _o__mbbtombc(long) ucrtbase._o__mbbtombc
@ cdecl _o__mbbtombc_l(long ptr) ucrtbase._o__mbbtombc_l
@ cdecl _o__mbbtype(long long) ucrtbase._o__mbbtype
@ cdecl _o__mbbtype_l(long long ptr) ucrtbase._o__mbbtype_l
@ cdecl _o__mbccpy(ptr ptr) ucrtbase._o__mbccpy
@ cdecl _o__mbccpy_l(ptr ptr ptr) ucrtbase._o__mbccpy_l
@ cdecl _o__mbccpy_s(ptr long ptr ptr) ucrtbase._o__mbccpy_s
@ cdecl _o__mbccpy_s_l(ptr long ptr ptr ptr) ucrtbase._o__mbccpy_s_l
@ cdecl _o__mbcjistojms(long) ucrtbase._o__mbcjistojms
@ cdecl _o__mbcjistojms_l(long ptr) ucrtbase._o__mbcjistojms_l
@ cdecl _o__mbcjmstojis(long) ucrtbase._o__mbcjmstojis
@ cdecl _o__mbcjmstojis_l(long ptr) ucrtbase._o__mbcjmstojis_l
@ cdecl _o__mbclen(ptr) ucrtbase._o__mbclen
@ cdecl _o__mbclen_l(ptr ptr) ucrtbase._o__mbclen_l
@ cdecl _o__mbctohira(long) ucrtbase._o__mbctohira
@ cdecl _o__mbctohira_l(long ptr) ucrtbase._o__mbctohira_l
@ cdecl _o__mbctokata(long) ucrtbase._o__mbctokata
@ cdecl _o__mbctokata_l(long ptr) ucrtbase._o__mbctokata_l
@ cdecl _o__mbctolower(long) ucrtbase._o__mbctolower
@ cdecl _o__mbctolower_l(long ptr) ucrtbase._o__mbctolower_l
@ cdecl _o__mbctombb(long) ucrtbase._o__mbctombb
@ cdecl _o__mbctombb_l(long ptr) ucrtbase._o__mbctombb_l
@ cdecl _o__mbctoupper(long) ucrtbase._o__mbctoupper
@ cdecl _o__mbctoupper_l(long ptr) ucrtbase._o__mbctoupper_l
@ cdecl _o__mblen_l(str long ptr) ucrtbase._o__mblen_l
@ cdecl _o__mbsbtype(str long) ucrtbase._o__mbsbtype
@ cdecl _o__mbsbtype_l(str long ptr) ucrtbase._o__mbsbtype_l
@ cdecl _o__mbscat_s(ptr long str) ucrtbase._o__mbscat_s
@ cdecl _o__mbscat_s_l(ptr long str ptr) ucrtbase._o__mbscat_s_l
@ cdecl _o__mbschr(str long) ucrtbase._o__mbschr
@ cdecl _o__mbschr_l(str long ptr) ucrtbase._o__mbschr_l
@ cdecl _o__mbscmp(str str) ucrtbase._o__mbscmp
@ cdecl _o__mbscmp_l(str str ptr) ucrtbase._o__mbscmp_l
@ cdecl _o__mbscoll(str str) ucrtbase._o__mbscoll
@ cdecl _o__mbscoll_l(str str ptr) ucrtbase._o__mbscoll_l
@ cdecl _o__mbscpy_s(ptr long str) ucrtbase._o__mbscpy_s
@ cdecl _o__mbscpy_s_l(ptr long str ptr) ucrtbase._o__mbscpy_s_l
@ cdecl _o__mbscspn(str str) ucrtbase._o__mbscspn
@ cdecl _o__mbscspn_l(str str ptr) ucrtbase._o__mbscspn_l
@ cdecl _o__mbsdec(ptr ptr) ucrtbase._o__mbsdec
@ cdecl _o__mbsdec_l(ptr ptr ptr) ucrtbase._o__mbsdec_l
@ cdecl _o__mbsicmp(str str) ucrtbase._o__mbsicmp
@ cdecl _o__mbsicmp_l(str str ptr) ucrtbase._o__mbsicmp_l
@ cdecl _o__mbsicoll(str str) ucrtbase._o__mbsicoll
@ cdecl _o__mbsicoll_l(str str ptr) ucrtbase._o__mbsicoll_l
@ cdecl _o__mbsinc(str) ucrtbase._o__mbsinc
@ cdecl _o__mbsinc_l(str ptr) ucrtbase._o__mbsinc_l
@ cdecl _o__mbslen(str) ucrtbase._o__mbslen
@ cdecl _o__mbslen_l(str ptr) ucrtbase._o__mbslen_l
@ cdecl _o__mbslwr(str) ucrtbase._o__mbslwr
@ cdecl _o__mbslwr_l(str ptr) ucrtbase._o__mbslwr_l
@ cdecl _o__mbslwr_s(str long) ucrtbase._o__mbslwr_s
@ cdecl _o__mbslwr_s_l(str long ptr) ucrtbase._o__mbslwr_s_l
@ cdecl _o__mbsnbcat(str str long) ucrtbase._o__mbsnbcat
@ cdecl _o__mbsnbcat_l(str str long ptr) ucrtbase._o__mbsnbcat_l
@ cdecl _o__mbsnbcat_s(str long ptr long) ucrtbase._o__mbsnbcat_s
@ cdecl _o__mbsnbcat_s_l(str long ptr long ptr) ucrtbase._o__mbsnbcat_s_l
@ cdecl _o__mbsnbcmp(str str long) ucrtbase._o__mbsnbcmp
@ cdecl _o_mbsnbcmp_l(str str long ptr) ucrtbase._o_mbsnbcmp_l
@ cdecl _o__mbsnbcnt(ptr long) ucrtbase._o__mbsnbcnt
@ cdecl _o__mbsnbcnt_l(ptr long ptr) ucrtbase._o__mbsnbcnt_l
@ cdecl _o__mbsnbcoll(str str long) ucrtbase._o__mbsnbcoll
@ cdecl _o__mbsnbcoll_l(str str long ptr) ucrtbase._o__mbsnbcoll_l
@ cdecl _o__mbsnbcpy(ptr str long) ucrtbase._o__mbsnbcpy
@ cdecl _o__mbsnbcpy_l(ptr str long ptr) ucrtbase._o__mbsnbcpy_l
@ cdecl _o__mbsnbcpy_s(ptr long str long) ucrtbase._o__mbsnbcpy_s
@ cdecl _o__mbsnbcpy_s_l(ptr long str long ptr) ucrtbase._o__mbsnbcpy_s_l
@ cdecl _o__mbsnbicmp(str str long) ucrtbase._o__mbsnbicmp
@ cdecl _o__mbsnbicmp_l(str str long ptr) ucrtbase._o__mbsnbicmp_l
@ cdecl _o__mbsnbicoll(str str long) ucrtbase._o__mbsnbicoll
@ cdecl _o__mbsnbicoll_l(str str long ptr) ucrtbase._o__mbsnbicoll_l
@ cdecl _o__mbsnbset(ptr long long) ucrtbase._o__mbsnbset
@ cdecl _o__mbsnbset_l(str long long ptr) ucrtbase._o__mbsnbset_l
@ stub _o__mbsnbset_s
@ stub _o__mbsnbset_s_l
@ cdecl _o__mbsncat(str str long) ucrtbase._o__mbsncat
@ cdecl _o__mbsncat_l(str str long ptr) ucrtbase._o__mbsncat_l
@ stub _o__mbsncat_s
@ stub _o__mbsncat_s_l
@ cdecl _o__mbsnccnt(str long) ucrtbase._o__mbsnccnt
@ cdecl _o__mbsnccnt_l(str long ptr) ucrtbase._o__mbsnccnt_l
@ cdecl _o__mbsncmp(str str long) ucrtbase._o__mbsncmp
@ cdecl _o__mbsncmp_l(str str long ptr) ucrtbase._o__mbsncmp_l
@ stub _o__mbsncoll
@ stub _o__mbsncoll_l
@ cdecl _o__mbsncpy(ptr str long) ucrtbase._o__mbsncpy
@ cdecl _o__mbsncpy_l(ptr str long ptr) ucrtbase._o__mbsncpy_l
@ cdecl _o__mbsncpy_s(ptr long str long) ucrtbase._o__mbsncpy_s
@ cdecl _o__mbsncpy_s_l(ptr long str long ptr) ucrtbase._o__mbsncpy_s_l
@ cdecl _o__mbsnextc(str) ucrtbase._o__mbsnextc
@ cdecl _o__mbsnextc_l(str ptr) ucrtbase._o__mbsnextc_l
@ cdecl _o__mbsnicmp(str str long) ucrtbase._o__mbsnicmp
@ cdecl _o__mbsnicmp_l(str str long ptr) ucrtbase._o__mbsnicmp_l
@ stub _o__mbsnicoll
@ stub _o__mbsnicoll_l
@ cdecl _o__mbsninc(str long) ucrtbase._o__mbsninc
@ stub _o__mbsninc_l
@ cdecl _o__mbsnlen(str long) ucrtbase._o__mbsnlen
@ cdecl _o__mbsnlen_l(str long ptr) ucrtbase._o__mbsnlen_l
@ cdecl _o__mbsnset(ptr long long) ucrtbase._o__mbsnset
@ cdecl _o__mbsnset_l(ptr long long ptr) ucrtbase._o__mbsnset_l
@ stub _o__mbsnset_s
@ stub _o__mbsnset_s_l
@ cdecl _o__mbspbrk(str str) ucrtbase._o__mbspbrk
@ cdecl _o__mbspbrk_l(str str ptr) ucrtbase._o__mbspbrk_l
@ cdecl _o__mbsrchr(str long) ucrtbase._o__mbsrchr
@ cdecl _o__mbsrchr_l(str long ptr) ucrtbase._o__mbsrchr_l
@ cdecl _o__mbsrev(str) ucrtbase._o__mbsrev
@ cdecl _o__mbsrev_l(str ptr) ucrtbase._o__mbsrev_l
@ cdecl _o__mbsset(ptr long) ucrtbase._o__mbsset
@ cdecl _o__mbsset_l(ptr long ptr) ucrtbase._o__mbsset_l
@ stub _o__mbsset_s
@ stub _o__mbsset_s_l
@ cdecl _o__mbsspn(str str) ucrtbase._o__mbsspn
@ cdecl _o__mbsspn_l(str str ptr) ucrtbase._o__mbsspn_l
@ cdecl _o__mbsspnp(str str) ucrtbase._o__mbsspnp
@ cdecl _o__mbsspnp_l(str str ptr) ucrtbase._o__mbsspnp_l
@ cdecl _o__mbsstr(str str) ucrtbase._o__mbsstr
@ stub _o__mbsstr_l
@ cdecl _o__mbstok(str str) ucrtbase._o__mbstok
@ cdecl _o__mbstok_l(str str ptr) ucrtbase._o__mbstok_l
@ cdecl _o__mbstok_s(str str ptr) ucrtbase._o__mbstok_s
@ cdecl _o__mbstok_s_l(str str ptr ptr) ucrtbase._o__mbstok_s_l
@ cdecl _o__mbstowcs_l(ptr str long ptr) ucrtbase._o__mbstowcs_l
@ cdecl _o__mbstowcs_s_l(ptr ptr long str long ptr) ucrtbase._o__mbstowcs_s_l
@ cdecl _o__mbstrlen(str) ucrtbase._o__mbstrlen
@ cdecl _o__mbstrlen_l(str ptr) ucrtbase._o__mbstrlen_l
@ stub _o__mbstrnlen
@ stub _o__mbstrnlen_l
@ cdecl _o__mbsupr(str) ucrtbase._o__mbsupr
@ cdecl _o__mbsupr_l(str ptr) ucrtbase._o__mbsupr_l
@ cdecl _o__mbsupr_s(str long) ucrtbase._o__mbsupr_s
@ cdecl _o__mbsupr_s_l(str long ptr) ucrtbase._o__mbsupr_s_l
@ cdecl _o__mbtowc_l(ptr str long ptr) ucrtbase._o__mbtowc_l
@ cdecl _o__memicmp(str str long) ucrtbase._o__memicmp
@ cdecl _o__memicmp_l(str str long ptr) ucrtbase._o__memicmp_l
@ cdecl _o__mkdir(str) ucrtbase._o__mkdir
@ cdecl _o__mkgmtime32(ptr) ucrtbase._o__mkgmtime32
@ cdecl _o__mkgmtime64(ptr) ucrtbase._o__mkgmtime64
@ cdecl _o__mktemp(str) ucrtbase._o__mktemp
@ cdecl _o__mktemp_s(str long) ucrtbase._o__mktemp_s
@ cdecl _o__mktime32(ptr) ucrtbase._o__mktime32
@ cdecl _o__mktime64(ptr) ucrtbase._o__mktime64
@ cdecl _o__msize(ptr) ucrtbase._o__msize
@ cdecl _o__nextafter(double double) ucrtbase._o__nextafter
@ cdecl -arch=x86_64 _o__nextafterf(float float) ucrtbase._o__nextafterf
@ cdecl _o__open_osfhandle(long long) ucrtbase._o__open_osfhandle
@ cdecl _o__pclose(ptr) ucrtbase._o__pclose
@ cdecl _o__pipe(ptr long long) ucrtbase._o__pipe
@ cdecl _o__popen(str str) ucrtbase._o__popen
@ cdecl _o__purecall() ucrtbase._o__purecall
@ cdecl _o__putc_nolock(long ptr) ucrtbase._o__putc_nolock
@ cdecl _o__putch(long) ucrtbase._o__putch
@ cdecl _o__putch_nolock(long) ucrtbase._o__putch_nolock
@ cdecl _o__putenv(str) ucrtbase._o__putenv
@ cdecl _o__putenv_s(str str) ucrtbase._o__putenv_s
@ cdecl _o__putw(long ptr) ucrtbase._o__putw
@ cdecl _o__putwc_nolock(long ptr) ucrtbase._o__putwc_nolock
@ cdecl _o__putwch(long) ucrtbase._o__putwch
@ cdecl _o__putwch_nolock(long) ucrtbase._o__putwch_nolock
@ cdecl _o__putws(wstr) ucrtbase._o__putws
@ cdecl _o__read(long ptr long) ucrtbase._o__read
@ cdecl _o__realloc_base(ptr long) ucrtbase._o__realloc_base
@ cdecl _o__recalloc(ptr long long) ucrtbase._o__recalloc
@ cdecl _o__register_onexit_function(ptr ptr) ucrtbase._o__register_onexit_function
@ cdecl _o__resetstkoflw() ucrtbase._o__resetstkoflw
@ cdecl _o__rmdir(str) ucrtbase._o__rmdir
@ cdecl _o__rmtmp() ucrtbase._o__rmtmp
@ cdecl _o__scalb(double long) ucrtbase._o__scalb
@ cdecl -arch=x86_64 _o__scalbf(float long) ucrtbase._o__scalbf
@ cdecl _o__searchenv(str str ptr) ucrtbase._o__searchenv
@ cdecl _o__searchenv_s(str str ptr long) ucrtbase._o__searchenv_s
@ cdecl _o__seh_filter_dll(long ptr) ucrtbase._o__seh_filter_dll
@ cdecl _o__seh_filter_exe(long ptr) ucrtbase._o__seh_filter_exe
@ cdecl _o__set_abort_behavior(long long) ucrtbase._o__set_abort_behavior
@ cdecl _o__set_app_type(long) ucrtbase._o__set_app_type
@ cdecl _o__set_doserrno(long) ucrtbase._o__set_doserrno
@ cdecl _o__set_errno(long) ucrtbase._o__set_errno
@ cdecl _o__set_fmode(long) ucrtbase._o__set_fmode
@ cdecl _o__set_invalid_parameter_handler(ptr) ucrtbase._o__set_invalid_parameter_handler
@ cdecl _o__set_new_handler(ptr) ucrtbase._o__set_new_handler
@ cdecl _o__set_new_mode(long) ucrtbase._o__set_new_mode
@ cdecl _o__set_thread_local_invalid_parameter_handler(ptr) ucrtbase._o__set_thread_local_invalid_parameter_handler
@ cdecl _o__seterrormode(long) ucrtbase._o__seterrormode
@ cdecl _o__setmbcp(long) ucrtbase._o__setmbcp
@ cdecl _o__setmode(long long) ucrtbase._o__setmode
@ stub _o__setsystime
@ cdecl _o__sleep(long) ucrtbase._o__sleep
@ varargs _o__sopen(str long long) ucrtbase._o__sopen
@ cdecl _o__sopen_dispatch(str long long long ptr long) ucrtbase._o__sopen_dispatch
@ cdecl _o__sopen_s(ptr str long long long) ucrtbase._o__sopen_s
@ cdecl _o__spawnv(long str ptr) ucrtbase._o__spawnv
@ cdecl _o__spawnve(long str ptr ptr) ucrtbase._o__spawnve
@ cdecl _o__spawnvp(long str ptr) ucrtbase._o__spawnvp
@ cdecl _o__spawnvpe(long str ptr ptr) ucrtbase._o__spawnvpe
@ cdecl _o__splitpath(str ptr ptr ptr ptr) ucrtbase._o__splitpath
@ cdecl _o__splitpath_s(str ptr long ptr long ptr long ptr long) ucrtbase._o__splitpath_s
@ cdecl _o__stat32(str ptr) ucrtbase._o__stat32
@ cdecl _o__stat32i64(str ptr) ucrtbase._o__stat32i64
@ cdecl _o__stat64(str ptr) ucrtbase._o__stat64
@ cdecl _o__stat64i32(str ptr) ucrtbase._o__stat64i32
@ cdecl _o__strcoll_l(str str ptr) ucrtbase._o__strcoll_l
@ cdecl _o__strdate(ptr) ucrtbase._o__strdate
@ cdecl _o__strdate_s(ptr long) ucrtbase._o__strdate_s
@ cdecl _o__strdup(str) ucrtbase._o__strdup
@ cdecl _o__strerror(long) ucrtbase._o__strerror
@ stub _o__strerror_s
@ cdecl _o__strftime_l(ptr long str ptr ptr) ucrtbase._o__strftime_l
@ cdecl _o__stricmp(str str) ucrtbase._o__stricmp
@ cdecl _o__stricmp_l(str str ptr) ucrtbase._o__stricmp_l
@ cdecl _o__stricoll(str str) ucrtbase._o__stricoll
@ cdecl _o__stricoll_l(str str ptr) ucrtbase._o__stricoll_l
@ cdecl _o__strlwr(str) ucrtbase._o__strlwr
@ cdecl _o__strlwr_l(str ptr) ucrtbase._o__strlwr_l
@ cdecl _o__strlwr_s(ptr long) ucrtbase._o__strlwr_s
@ cdecl _o__strlwr_s_l(ptr long ptr) ucrtbase._o__strlwr_s_l
@ cdecl _o__strncoll(str str long) ucrtbase._o__strncoll
@ cdecl _o__strncoll_l(str str long ptr) ucrtbase._o__strncoll_l
@ cdecl _o__strnicmp(str str long) ucrtbase._o__strnicmp
@ cdecl _o__strnicmp_l(str str long ptr) ucrtbase._o__strnicmp_l
@ cdecl _o__strnicoll(str str long) ucrtbase._o__strnicoll
@ cdecl _o__strnicoll_l(str str long ptr) ucrtbase._o__strnicoll_l
@ cdecl _o__strnset_s(str long long long) ucrtbase._o__strnset_s
@ stub _o__strset_s
@ cdecl _o__strtime(ptr) ucrtbase._o__strtime
@ cdecl _o__strtime_s(ptr long) ucrtbase._o__strtime_s
@ cdecl _o__strtod_l(str ptr ptr) ucrtbase._o__strtod_l
@ cdecl _o__strtof_l(str ptr ptr) ucrtbase._o__strtof_l
@ cdecl -ret64 _o__strtoi64(str ptr long) ucrtbase._o__strtoi64
@ cdecl -ret64 _o__strtoi64_l(str ptr long ptr) ucrtbase._o__strtoi64_l
@ cdecl _o__strtol_l(str ptr long ptr) ucrtbase._o__strtol_l
@ cdecl _o__strtold_l(str ptr ptr) ucrtbase._o__strtold_l
@ cdecl -ret64 _o__strtoll_l(str ptr long ptr) ucrtbase._o__strtoll_l
@ cdecl -ret64 _o__strtoui64(str ptr long) ucrtbase._o__strtoui64
@ cdecl -ret64 _o__strtoui64_l(str ptr long ptr) ucrtbase._o__strtoui64_l
@ cdecl _o__strtoul_l(str ptr long ptr) ucrtbase._o__strtoul_l
@ cdecl -ret64 _o__strtoull_l(str ptr long ptr) ucrtbase._o__strtoull_l
@ cdecl _o__strupr(str) ucrtbase._o__strupr
@ cdecl _o__strupr_l(str ptr) ucrtbase._o__strupr_l
@ cdecl _o__strupr_s(str long) ucrtbase._o__strupr_s
@ cdecl _o__strupr_s_l(str long ptr) ucrtbase._o__strupr_s_l
@ cdecl _o__strxfrm_l(ptr str long ptr) ucrtbase._o__strxfrm_l
@ cdecl _o__swab(str str long) ucrtbase._o__swab
@ cdecl _o__tell(long) ucrtbase._o__tell
@ cdecl -ret64 _o__telli64(long) ucrtbase._o__telli64
@ cdecl _o__timespec32_get(ptr long) ucrtbase._o__timespec32_get
@ cdecl _o__timespec64_get(ptr long) ucrtbase._o__timespec64_get
@ cdecl _o__tolower(long) ucrtbase._o__tolower
@ cdecl _o__tolower_l(long ptr) ucrtbase._o__tolower_l
@ cdecl _o__toupper(long) ucrtbase._o__toupper
@ cdecl _o__toupper_l(long ptr) ucrtbase._o__toupper_l
@ cdecl _o__towlower_l(long ptr) ucrtbase._o__towlower_l
@ cdecl _o__towupper_l(long ptr) ucrtbase._o__towupper_l
@ cdecl _o__tzset() ucrtbase._o__tzset
@ cdecl _o__ui64toa(int64 ptr long) ucrtbase._o__ui64toa
@ cdecl _o__ui64toa_s(int64 ptr long long) ucrtbase._o__ui64toa_s
@ cdecl _o__ui64tow(int64 ptr long) ucrtbase._o__ui64tow
@ cdecl _o__ui64tow_s(int64 ptr long long) ucrtbase._o__ui64tow_s
@ cdecl _o__ultoa(long ptr long) ucrtbase._o__ultoa
@ cdecl _o__ultoa_s(long ptr long long) ucrtbase._o__ultoa_s
@ cdecl _o__ultow(long ptr long) ucrtbase._o__ultow
@ cdecl _o__ultow_s(long ptr long long) ucrtbase._o__ultow_s
@ cdecl _o__umask(long) ucrtbase._o__umask
@ stub _o__umask_s
@ cdecl _o__ungetc_nolock(long ptr) ucrtbase._o__ungetc_nolock
@ cdecl _o__ungetch(long) ucrtbase._o__ungetch
@ cdecl _o__ungetch_nolock(long) ucrtbase._o__ungetch_nolock
@ cdecl _o__ungetwc_nolock(long ptr) ucrtbase._o__ungetwc_nolock
@ cdecl _o__ungetwch(long) ucrtbase._o__ungetwch
@ cdecl _o__ungetwch_nolock(long) ucrtbase._o__ungetwch_nolock
@ cdecl _o__unlink(str) ucrtbase._o__unlink
@ cdecl _o__unloaddll(long) ucrtbase._o__unloaddll
@ cdecl _o__unlock_file(ptr) ucrtbase._o__unlock_file
@ cdecl _o__utime32(str ptr) ucrtbase._o__utime32
@ cdecl _o__utime64(str ptr) ucrtbase._o__utime64
@ cdecl _o__waccess(wstr long) ucrtbase._o__waccess
@ cdecl _o__waccess_s(wstr long) ucrtbase._o__waccess_s
@ cdecl _o__wasctime(ptr) ucrtbase._o__wasctime
@ cdecl _o__wasctime_s(ptr long ptr) ucrtbase._o__wasctime_s
@ cdecl _o__wchdir(wstr) ucrtbase._o__wchdir
@ cdecl _o__wchmod(wstr long) ucrtbase._o__wchmod
@ cdecl _o__wcreat(wstr long) ucrtbase._o__wcreat
@ cdecl _o__wcreate_locale(long wstr) ucrtbase._o__wcreate_locale
@ cdecl _o__wcscoll_l(wstr wstr ptr) ucrtbase._o__wcscoll_l
@ cdecl _o__wcsdup(wstr) ucrtbase._o__wcsdup
@ cdecl _o__wcserror(long) ucrtbase._o__wcserror
@ cdecl _o__wcserror_s(ptr long long) ucrtbase._o__wcserror_s
@ cdecl _o__wcsftime_l(ptr long wstr ptr ptr) ucrtbase._o__wcsftime_l
@ cdecl _o__wcsicmp(wstr wstr) ucrtbase._o__wcsicmp
@ cdecl _o__wcsicmp_l(wstr wstr ptr) ucrtbase._o__wcsicmp_l
@ cdecl _o__wcsicoll(wstr wstr) ucrtbase._o__wcsicoll
@ cdecl _o__wcsicoll_l(wstr wstr ptr) ucrtbase._o__wcsicoll_l
@ cdecl _o__wcslwr(wstr) ucrtbase._o__wcslwr
@ cdecl _o__wcslwr_l(wstr ptr) ucrtbase._o__wcslwr_l
@ cdecl _o__wcslwr_s(wstr long) ucrtbase._o__wcslwr_s
@ cdecl _o__wcslwr_s_l(wstr long ptr) ucrtbase._o__wcslwr_s_l
@ cdecl _o__wcsncoll(wstr wstr long) ucrtbase._o__wcsncoll
@ cdecl _o__wcsncoll_l(wstr wstr long ptr) ucrtbase._o__wcsncoll_l
@ cdecl _o__wcsnicmp(wstr wstr long) ucrtbase._o__wcsnicmp
@ cdecl _o__wcsnicmp_l(wstr wstr long ptr) ucrtbase._o__wcsnicmp_l
@ cdecl _o__wcsnicoll(wstr wstr long) ucrtbase._o__wcsnicoll
@ cdecl _o__wcsnicoll_l(wstr wstr long ptr) ucrtbase._o__wcsnicoll_l
@ cdecl _o__wcsnset(wstr long long) ucrtbase._o__wcsnset
@ cdecl _o__wcsnset_s(wstr long long long) ucrtbase._o__wcsnset_s
@ cdecl _o__wcsset(wstr long) ucrtbase._o__wcsset
@ cdecl _o__wcsset_s(wstr long long) ucrtbase._o__wcsset_s
@ cdecl _o__wcstod_l(wstr ptr ptr) ucrtbase._o__wcstod_l
@ cdecl _o__wcstof_l(wstr ptr ptr) ucrtbase._o__wcstof_l
@ cdecl -ret64 _o__wcstoi64(wstr ptr long) ucrtbase._o__wcstoi64
@ cdecl -ret64 _o__wcstoi64_l(wstr ptr long ptr) ucrtbase._o__wcstoi64_l
@ cdecl _o__wcstol_l(wstr ptr long ptr) ucrtbase._o__wcstol_l
@ cdecl _o__wcstold_l(wstr ptr ptr) ucrtbase._o__wcstold_l
@ cdecl -ret64 _o__wcstoll_l(wstr ptr long ptr) ucrtbase._o__wcstoll_l
@ cdecl _o__wcstombs_l(ptr ptr long ptr) ucrtbase._o__wcstombs_l
@ cdecl _o__wcstombs_s_l(ptr ptr long wstr long ptr) ucrtbase._o__wcstombs_s_l
@ cdecl -ret64 _o__wcstoui64(wstr ptr long) ucrtbase._o__wcstoui64
@ cdecl -ret64 _o__wcstoui64_l(wstr ptr long ptr) ucrtbase._o__wcstoui64_l
@ cdecl _o__wcstoul_l(wstr ptr long ptr) ucrtbase._o__wcstoul_l
@ cdecl -ret64 _o__wcstoull_l(wstr ptr long ptr) ucrtbase._o__wcstoull_l
@ cdecl _o__wcsupr(wstr) ucrtbase._o__wcsupr
@ cdecl _o__wcsupr_l(wstr ptr) ucrtbase._o__wcsupr_l
@ cdecl _o__wcsupr_s(wstr long) ucrtbase._o__wcsupr_s
@ cdecl _o__wcsupr_s_l(wstr long ptr) ucrtbase._o__wcsupr_s_l
@ cdecl _o__wcsxfrm_l(ptr wstr long ptr) ucrtbase._o__wcsxfrm_l
@ cdecl _o__wctime32(ptr) ucrtbase._o__wctime32
@ cdecl _o__wctime32_s(ptr long ptr) ucrtbase._o__wctime32_s
@ cdecl _o__wctime64(ptr) ucrtbase._o__wctime64
@ cdecl _o__wctime64_s(ptr long ptr) ucrtbase._o__wctime64_s
@ cdecl _o__wctomb_l(ptr long ptr) ucrtbase._o__wctomb_l
@ cdecl _o__wctomb_s_l(ptr ptr long long ptr) ucrtbase._o__wctomb_s_l
@ cdecl _o__wdupenv_s(ptr ptr wstr) ucrtbase._o__wdupenv_s
@ cdecl _o__wexecv(wstr ptr) ucrtbase._o__wexecv
@ cdecl _o__wexecve(wstr ptr ptr) ucrtbase._o__wexecve
@ cdecl _o__wexecvp(wstr ptr) ucrtbase._o__wexecvp
@ cdecl _o__wexecvpe(wstr ptr ptr) ucrtbase._o__wexecvpe
@ cdecl _o__wfdopen(long wstr) ucrtbase._o__wfdopen
@ cdecl _o__wfindfirst32(wstr ptr) ucrtbase._o__wfindfirst32
@ stub _o__wfindfirst32i64
@ cdecl _o__wfindfirst64(wstr ptr) ucrtbase._o__wfindfirst64
@ cdecl _o__wfindfirst64i32(wstr ptr) ucrtbase._o__wfindfirst64i32
@ cdecl _o__wfindnext32(long ptr) ucrtbase._o__wfindnext32
@ stub _o__wfindnext32i64
@ cdecl _o__wfindnext64(long ptr) ucrtbase._o__wfindnext64
@ cdecl _o__wfindnext64i32(long ptr) ucrtbase._o__wfindnext64i32
@ cdecl _o__wfopen(wstr wstr) ucrtbase._o__wfopen
@ cdecl _o__wfopen_s(ptr wstr wstr) ucrtbase._o__wfopen_s
@ cdecl _o__wfreopen(wstr wstr ptr) ucrtbase._o__wfreopen
@ cdecl _o__wfreopen_s(ptr wstr wstr ptr) ucrtbase._o__wfreopen_s
@ cdecl _o__wfsopen(wstr wstr long) ucrtbase._o__wfsopen
@ cdecl _o__wfullpath(ptr wstr long) ucrtbase._o__wfullpath
@ cdecl _o__wgetcwd(wstr long) ucrtbase._o__wgetcwd
@ cdecl _o__wgetdcwd(long wstr long) ucrtbase._o__wgetdcwd
@ cdecl _o__wgetenv(wstr) ucrtbase._o__wgetenv
@ cdecl _o__wgetenv_s(ptr ptr long wstr) ucrtbase._o__wgetenv_s
@ cdecl _o__wmakepath(ptr wstr wstr wstr wstr) ucrtbase._o__wmakepath
@ cdecl _o__wmakepath_s(ptr long wstr wstr wstr wstr) ucrtbase._o__wmakepath_s
@ cdecl _o__wmkdir(wstr) ucrtbase._o__wmkdir
@ cdecl _o__wmktemp(wstr) ucrtbase._o__wmktemp
@ cdecl _o__wmktemp_s(wstr long) ucrtbase._o__wmktemp_s
@ cdecl _o__wperror(wstr) ucrtbase._o__wperror
@ cdecl _o__wpopen(wstr wstr) ucrtbase._o__wpopen
@ cdecl _o__wputenv(wstr) ucrtbase._o__wputenv
@ cdecl _o__wputenv_s(wstr wstr) ucrtbase._o__wputenv_s
@ cdecl _o__wremove(wstr) ucrtbase._o__wremove
@ cdecl _o__wrename(wstr wstr) ucrtbase._o__wrename
@ cdecl _o__write(long ptr long) ucrtbase._o__write
@ cdecl _o__wrmdir(wstr) ucrtbase._o__wrmdir
@ cdecl _o__wsearchenv(wstr wstr ptr) ucrtbase._o__wsearchenv
@ cdecl _o__wsearchenv_s(wstr wstr ptr long) ucrtbase._o__wsearchenv_s
@ cdecl _o__wsetlocale(long wstr) ucrtbase._o__wsetlocale
@ cdecl _o__wsopen_dispatch(wstr long long long ptr long) ucrtbase._o__wsopen_dispatch
@ cdecl _o__wsopen_s(ptr wstr long long long) ucrtbase._o__wsopen_s
@ cdecl _o__wspawnv(long wstr ptr) ucrtbase._o__wspawnv
@ cdecl _o__wspawnve(long wstr ptr ptr) ucrtbase._o__wspawnve
@ cdecl _o__wspawnvp(long wstr ptr) ucrtbase._o__wspawnvp
@ cdecl _o__wspawnvpe(long wstr ptr ptr) ucrtbase._o__wspawnvpe
@ cdecl _o__wsplitpath(wstr ptr ptr ptr ptr) ucrtbase._o__wsplitpath
@ cdecl _o__wsplitpath_s(wstr ptr long ptr long ptr long ptr long) ucrtbase._o__wsplitpath_s
@ cdecl _o__wstat32(wstr ptr) ucrtbase._o__wstat32
@ cdecl _o__wstat32i64(wstr ptr) ucrtbase._o__wstat32i64
@ cdecl _o__wstat64(wstr ptr) ucrtbase._o__wstat64
@ cdecl _o__wstat64i32(wstr ptr) ucrtbase._o__wstat64i32
@ cdecl _o__wstrdate(ptr) ucrtbase._o__wstrdate
@ cdecl _o__wstrdate_s(ptr long) ucrtbase._o__wstrdate_s
@ cdecl _o__wstrtime(ptr) ucrtbase._o__wstrtime
@ cdecl _o__wstrtime_s(ptr long) ucrtbase._o__wstrtime_s
@ cdecl _o__wsystem(wstr) ucrtbase._o__wsystem
@ cdecl _o__wtmpnam_s(ptr long) ucrtbase._o__wtmpnam_s
@ cdecl _o__wtof(wstr) ucrtbase._o__wtof
@ cdecl _o__wtof_l(wstr ptr) ucrtbase._o__wtof_l
@ cdecl _o__wtoi(wstr) ucrtbase._o__wtoi
@ cdecl -ret64 _o__wtoi64(wstr) ucrtbase._o__wtoi64
@ cdecl -ret64 _o__wtoi64_l(wstr ptr) ucrtbase._o__wtoi64_l
@ cdecl _o__wtoi_l(wstr ptr) ucrtbase._o__wtoi_l
@ cdecl _o__wtol(wstr) ucrtbase._o__wtol
@ cdecl _o__wtol_l(wstr ptr) ucrtbase._o__wtol_l
@ cdecl -ret64 _o__wtoll(wstr) ucrtbase._o__wtoll
@ cdecl -ret64 _o__wtoll_l(wstr ptr) ucrtbase._o__wtoll_l
@ cdecl _o__wunlink(wstr) ucrtbase._o__wunlink
@ cdecl _o__wutime32(wstr ptr) ucrtbase._o__wutime32
@ cdecl _o__wutime64(wstr ptr) ucrtbase._o__wutime64
@ cdecl _o__y0(double) ucrtbase._o__y0
@ cdecl _o__y1(double) ucrtbase._o__y1
@ cdecl _o__yn(long double) ucrtbase._o__yn
@ cdecl _o_abort() ucrtbase._o_abort
@ cdecl _o_acos(double) ucrtbase._o_acos
@ cdecl -arch=!i386 _o_acosf(float) ucrtbase._o_acosf
@ cdecl _o_acosh(double) ucrtbase._o_acosh
@ cdecl _o_acoshf(float) ucrtbase._o_acoshf
@ cdecl _o_acoshl(double) ucrtbase._o_acoshl
@ cdecl _o_asctime(ptr) ucrtbase._o_asctime
@ cdecl _o_asctime_s(ptr long ptr) ucrtbase._o_asctime_s
@ cdecl _o_asin(double) ucrtbase._o_asin
@ cdecl -arch=!i386 _o_asinf(float) ucrtbase._o_asinf
@ cdecl _o_asinh(double) ucrtbase._o_asinh
@ cdecl _o_asinhf(float) ucrtbase._o_asinhf
@ cdecl _o_asinhl(double) ucrtbase._o_asinhl
@ cdecl _o_atan(double) ucrtbase._o_atan
@ cdecl _o_atan2(double double) ucrtbase._o_atan2
@ cdecl -arch=!i386 _o_atan2f(float float) ucrtbase._o_atan2f
@ cdecl -arch=!i386 _o_atanf(float) ucrtbase._o_atanf
@ cdecl _o_atanh(double) ucrtbase._o_atanh
@ cdecl _o_atanhf(float) ucrtbase._o_atanhf
@ cdecl _o_atanhl(double) ucrtbase._o_atanhl
@ cdecl _o_atof(str) ucrtbase._o_atof
@ cdecl _o_atoi(str) ucrtbase._o_atoi
@ cdecl _o_atol(str) ucrtbase._o_atol
@ cdecl -ret64 _o_atoll(str) ucrtbase._o_atoll
@ cdecl _o_bsearch(ptr ptr long long ptr) ucrtbase._o_bsearch
@ cdecl _o_bsearch_s(ptr ptr long long ptr ptr) ucrtbase._o_bsearch_s
@ cdecl _o_btowc(long) ucrtbase._o_btowc
@ cdecl _o_calloc(long long) ucrtbase._o_calloc
@ cdecl _o_cbrt(double) ucrtbase._o_cbrt
@ cdecl _o_cbrtf(float) ucrtbase._o_cbrtf
@ cdecl _o_ceil(double) ucrtbase._o_ceil
@ cdecl -arch=!i386 _o_ceilf(float) ucrtbase._o_ceilf
@ cdecl _o_clearerr(ptr) ucrtbase._o_clearerr
@ cdecl _o_clearerr_s(ptr) ucrtbase._o_clearerr_s
@ cdecl _o_cos(double) ucrtbase._o_cos
@ cdecl -arch=!i386 _o_cosf(float) ucrtbase._o_cosf
@ cdecl _o_cosh(double) ucrtbase._o_cosh
@ cdecl -arch=!i386 _o_coshf(float) ucrtbase._o_coshf
@ cdecl _o_erf(double) ucrtbase._o_erf
@ cdecl _o_erfc(double) ucrtbase._o_erfc
@ cdecl _o_erfcf(float) ucrtbase._o_erfcf
@ cdecl _o_erfcl(double) ucrtbase._o_erfcl
@ cdecl _o_erff(float) ucrtbase._o_erff
@ cdecl _o_erfl(double) ucrtbase._o_erfl
@ cdecl _o_exit(long) ucrtbase._o_exit
@ cdecl _o_exp(double) ucrtbase._o_exp
@ cdecl _o_exp2(double) ucrtbase._o_exp2
@ cdecl _o_exp2f(float) ucrtbase._o_exp2f
@ cdecl _o_exp2l(double) ucrtbase._o_exp2l
@ cdecl -arch=!i386 _o_expf(float) ucrtbase._o_expf
@ cdecl _o_fabs(double) ucrtbase._o_fabs
@ cdecl _o_fclose(ptr) ucrtbase._o_fclose
@ cdecl _o_feof(ptr) ucrtbase._o_feof
@ cdecl _o_ferror(ptr) ucrtbase._o_ferror
@ cdecl _o_fflush(ptr) ucrtbase._o_fflush
@ cdecl _o_fgetc(ptr) ucrtbase._o_fgetc
@ cdecl _o_fgetpos(ptr ptr) ucrtbase._o_fgetpos
@ cdecl _o_fgets(ptr long ptr) ucrtbase._o_fgets
@ cdecl _o_fgetwc(ptr) ucrtbase._o_fgetwc
@ cdecl _o_fgetws(ptr long ptr) ucrtbase._o_fgetws
@ cdecl _o_floor(double) ucrtbase._o_floor
@ cdecl -arch=!i386 _o_floorf(float) ucrtbase._o_floorf
@ cdecl _o_fma(double double double) ucrtbase._o_fma
@ cdecl _o_fmaf(float float float) ucrtbase._o_fmaf
@ cdecl _o_fmal(double double double) ucrtbase._o_fmal
@ cdecl _o_fmod(double double) ucrtbase._o_fmod
@ cdecl -arch=!i386 _o_fmodf(float float) ucrtbase._o_fmodf
@ cdecl _o_fopen(str str) ucrtbase._o_fopen
@ cdecl _o_fopen_s(ptr str str) ucrtbase._o_fopen_s
@ cdecl _o_fputc(long ptr) ucrtbase._o_fputc
@ cdecl _o_fputs(str ptr) ucrtbase._o_fputs
@ cdecl _o_fputwc(long ptr) ucrtbase._o_fputwc
@ cdecl _o_fputws(wstr ptr) ucrtbase._o_fputws
@ cdecl _o_fread(ptr long long ptr) ucrtbase._o_fread
@ cdecl _o_fread_s(ptr long long long ptr) ucrtbase._o_fread_s
@ cdecl _o_free(ptr) ucrtbase._o_free
@ cdecl _o_freopen(str str ptr) ucrtbase._o_freopen
@ cdecl _o_freopen_s(ptr str str ptr) ucrtbase._o_freopen_s
@ cdecl _o_frexp(double ptr) ucrtbase._o_frexp
@ cdecl _o_fseek(ptr long long) ucrtbase._o_fseek
@ cdecl _o_fsetpos(ptr ptr) ucrtbase._o_fsetpos
@ cdecl _o_ftell(ptr) ucrtbase._o_ftell
@ cdecl _o_fwrite(ptr long long ptr) ucrtbase._o_fwrite
@ cdecl _o_getc(ptr) ucrtbase._o_getc
@ cdecl _o_getchar() ucrtbase._o_getchar
@ cdecl _o_getenv(str) ucrtbase._o_getenv
@ cdecl _o_getenv_s(ptr ptr long str) ucrtbase._o_getenv_s
@ cdecl _o_gets(str) ucrtbase._o_gets
@ cdecl _o_gets_s(ptr long) ucrtbase._o_gets_s
@ cdecl _o_getwc(ptr) ucrtbase._o_getwc
@ cdecl _o_getwchar() ucrtbase._o_getwchar
@ cdecl _o_hypot(double double) ucrtbase._o_hypot
@ cdecl _o_is_wctype(long long) ucrtbase._o_is_wctype
@ cdecl _o_isalnum(long) ucrtbase._o_isalnum
@ cdecl _o_isalpha(long) ucrtbase._o_isalpha
@ cdecl _o_isblank(long) ucrtbase._o_isblank
@ cdecl _o_iscntrl(long) ucrtbase._o_iscntrl
@ cdecl _o_isdigit(long) ucrtbase._o_isdigit
@ cdecl _o_isgraph(long) ucrtbase._o_isgraph
@ cdecl _o_isleadbyte(long) ucrtbase._o_isleadbyte
@ cdecl _o_islower(long) ucrtbase._o_islower
@ cdecl _o_isprint(long) ucrtbase._o_isprint
@ cdecl _o_ispunct(long) ucrtbase._o_ispunct
@ cdecl _o_isspace(long) ucrtbase._o_isspace
@ cdecl _o_isupper(long) ucrtbase._o_isupper
@ cdecl _o_iswalnum(long) ucrtbase._o_iswalnum
@ cdecl _o_iswalpha(long) ucrtbase._o_iswalpha
@ cdecl _o_iswascii(long) ucrtbase._o_iswascii
@ cdecl _o_iswblank(long) ucrtbase._o_iswblank
@ cdecl _o_iswcntrl(long) ucrtbase._o_iswcntrl
@ cdecl _o_iswctype(long long) ucrtbase._o_iswctype
@ cdecl _o_iswdigit(long) ucrtbase._o_iswdigit
@ cdecl _o_iswgraph(long) ucrtbase._o_iswgraph
@ cdecl _o_iswlower(long) ucrtbase._o_iswlower
@ cdecl _o_iswprint(long) ucrtbase._o_iswprint
@ cdecl _o_iswpunct(long) ucrtbase._o_iswpunct
@ cdecl _o_iswspace(long) ucrtbase._o_iswspace
@ cdecl _o_iswupper(long) ucrtbase._o_iswupper
@ cdecl _o_iswxdigit(long) ucrtbase._o_iswxdigit
@ cdecl _o_isxdigit(long) ucrtbase._o_isxdigit
@ cdecl _o_ldexp(double long) ucrtbase._o_ldexp
@ cdecl _o_lgamma(double) ucrtbase._o_lgamma
@ cdecl _o_lgammaf(float) ucrtbase._o_lgammaf
@ cdecl _o_lgammal(double) ucrtbase._o_lgammal
@ cdecl -ret64 _o_llrint(double) ucrtbase._o_llrint
@ cdecl -ret64 _o_llrintf(float) ucrtbase._o_llrintf
@ cdecl -ret64 _o_llrintl(double) ucrtbase._o_llrintl
@ cdecl -ret64 _o_llround(double) ucrtbase._o_llround
@ cdecl -ret64 _o_llroundf(float) ucrtbase._o_llroundf
@ cdecl -ret64 _o_llroundl(double) ucrtbase._o_llroundl
@ cdecl _o_localeconv() ucrtbase._o_localeconv
@ cdecl _o_log(double) ucrtbase._o_log
@ cdecl _o_log10(double) ucrtbase._o_log10
@ cdecl -arch=!i386 _o_log10f(float) ucrtbase._o_log10f
@ cdecl _o_log1p(double) ucrtbase._o_log1p
@ cdecl _o_log1pf(float) ucrtbase._o_log1pf
@ cdecl _o_log1pl(double) ucrtbase._o_log1pl
@ cdecl _o_log2(double) ucrtbase._o_log2
@ cdecl _o_log2f(float) ucrtbase._o_log2f
@ cdecl _o_log2l(double) ucrtbase._o_log2l
@ cdecl _o_logb(double) ucrtbase._o_logb
@ cdecl _o_logbf(float) ucrtbase._o_logbf
@ cdecl _o_logbl(double) ucrtbase._o_logbl
@ cdecl -arch=!i386 _o_logf(float) ucrtbase._o_logf
@ cdecl _o_lrint(double) ucrtbase._o_lrint
@ cdecl _o_lrintf(float) ucrtbase._o_lrintf
@ cdecl _o_lrintl(double) ucrtbase._o_lrintl
@ cdecl _o_lround(double) ucrtbase._o_lround
@ cdecl _o_lroundf(float) ucrtbase._o_lroundf
@ cdecl _o_lroundl(double) ucrtbase._o_lroundl
@ cdecl _o_malloc(long) ucrtbase._o_malloc
@ cdecl _o_mblen(ptr long) ucrtbase._o_mblen
@ cdecl _o_mbrlen(ptr long ptr) ucrtbase._o_mbrlen
@ stub _o_mbrtoc16
@ stub _o_mbrtoc32
@ cdecl _o_mbrtowc(ptr str long ptr) ucrtbase._o_mbrtowc
@ cdecl _o_mbsrtowcs(ptr ptr long ptr) ucrtbase._o_mbsrtowcs
@ cdecl _o_mbsrtowcs_s(ptr ptr long ptr long ptr) ucrtbase._o_mbsrtowcs_s
@ cdecl _o_mbstowcs(ptr str long) ucrtbase._o_mbstowcs
@ cdecl _o_mbstowcs_s(ptr ptr long str long) ucrtbase._o_mbstowcs_s
@ cdecl _o_mbtowc(ptr str long) ucrtbase._o_mbtowc
@ cdecl _o_memcpy_s(ptr long ptr long) ucrtbase._o_memcpy_s
@ cdecl _o_memset(ptr long long) ucrtbase._o_memset
@ cdecl _o_modf(double ptr) ucrtbase._o_modf
@ cdecl -arch=!i386 _o_modff(float ptr) ucrtbase._o_modff
@ cdecl _o_nan(str) ucrtbase._o_nan
@ cdecl _o_nanf(str) ucrtbase._o_nanf
@ cdecl _o_nanl(str) ucrtbase._o_nanl
@ cdecl _o_nearbyint(double) ucrtbase._o_nearbyint
@ cdecl _o_nearbyintf(float) ucrtbase._o_nearbyintf
@ cdecl _o_nearbyintl(double) ucrtbase._o_nearbyintl
@ cdecl _o_nextafter(double double) ucrtbase._o_nextafter
@ cdecl _o_nextafterf(float float) ucrtbase._o_nextafterf
@ cdecl _o_nextafterl(double double) ucrtbase._o_nextafterl
@ cdecl _o_nexttoward(double double) ucrtbase._o_nexttoward
@ cdecl _o_nexttowardf(float double) ucrtbase._o_nexttowardf
@ cdecl _o_nexttowardl(double double) ucrtbase._o_nexttowardl
@ cdecl _o_pow(double double) ucrtbase._o_pow
@ cdecl _o_powf(float float) ucrtbase._o_powf
@ cdecl _o_putc(long ptr) ucrtbase._o_putc
@ cdecl _o_putchar(long) ucrtbase._o_putchar
@ cdecl _o_puts(str) ucrtbase._o_puts
@ cdecl _o_putwc(long ptr) ucrtbase._o_putwc
@ cdecl _o_putwchar(long) ucrtbase._o_putwchar
@ cdecl _o_qsort(ptr long long ptr) ucrtbase._o_qsort
@ cdecl _o_qsort_s(ptr long long ptr ptr) ucrtbase._o_qsort_s
@ cdecl _o_raise(long) ucrtbase._o_raise
@ cdecl _o_rand() ucrtbase._o_rand
@ cdecl _o_rand_s(ptr) ucrtbase._o_rand_s
@ cdecl _o_realloc(ptr long) ucrtbase._o_realloc
@ cdecl _o_remainder(double double) ucrtbase._o_remainder
@ cdecl _o_remainderf(float float) ucrtbase._o_remainderf
@ cdecl _o_remainderl(double double) ucrtbase._o_remainderl
@ cdecl _o_remove(str) ucrtbase._o_remove
@ cdecl _o_remquo(double double ptr) ucrtbase._o_remquo
@ cdecl _o_remquof(float float ptr) ucrtbase._o_remquof
@ cdecl _o_remquol(double double ptr) ucrtbase._o_remquol
@ cdecl _o_rename(str str) ucrtbase._o_rename
@ cdecl _o_rewind(ptr) ucrtbase._o_rewind
@ cdecl _o_rint(double) ucrtbase._o_rint
@ cdecl _o_rintf(float) ucrtbase._o_rintf
@ cdecl _o_rintl(double) ucrtbase._o_rintl
@ cdecl _o_round(double) ucrtbase._o_round
@ cdecl _o_roundf(float) ucrtbase._o_roundf
@ cdecl _o_roundl(double) ucrtbase._o_roundl
@ cdecl _o_scalbln(double long) ucrtbase._o_scalbln
@ cdecl _o_scalblnf(float long) ucrtbase._o_scalblnf
@ cdecl _o_scalblnl(double long) ucrtbase._o_scalblnl
@ cdecl _o_scalbn(double long) ucrtbase._o_scalbn
@ cdecl _o_scalbnf(float long) ucrtbase._o_scalbnf
@ cdecl _o_scalbnl(double long) ucrtbase._o_scalbnl
@ cdecl _o_set_terminate(ptr) ucrtbase._o_set_terminate
@ cdecl _o_setbuf(ptr ptr) ucrtbase._o_setbuf
@ cdecl _o_setlocale(long str) ucrtbase._o_setlocale
@ cdecl _o_setvbuf(ptr str long long) ucrtbase._o_setvbuf
@ cdecl _o_sin(double) ucrtbase._o_sin
@ cdecl -arch=!i386 _o_sinf(float) ucrtbase._o_sinf
@ cdecl _o_sinh(double) ucrtbase._o_sinh
@ cdecl -arch=!i386 _o_sinhf(float) ucrtbase._o_sinhf
@ cdecl _o_sqrt(double) ucrtbase._o_sqrt
@ cdecl -arch=!i386 _o_sqrtf(float) ucrtbase._o_sqrtf
@ cdecl _o_srand(long) ucrtbase._o_srand
@ cdecl _o_strcat_s(str long str) ucrtbase._o_strcat_s
@ cdecl _o_strcoll(str str) ucrtbase._o_strcoll
@ cdecl _o_strcpy_s(ptr long str) ucrtbase._o_strcpy_s
@ cdecl _o_strerror(long) ucrtbase._o_strerror
@ cdecl _o_strerror_s(ptr long long) ucrtbase._o_strerror_s
@ cdecl _o_strftime(ptr long str ptr) ucrtbase._o_strftime
@ cdecl _o_strncat_s(str long str long) ucrtbase._o_strncat_s
@ cdecl _o_strncpy_s(ptr long str long) ucrtbase._o_strncpy_s
@ cdecl _o_strtod(str ptr) ucrtbase._o_strtod
@ cdecl _o_strtof(str ptr) ucrtbase._o_strtof
@ cdecl _o_strtok(str str) ucrtbase._o_strtok
@ cdecl _o_strtok_s(ptr str ptr) ucrtbase._o_strtok_s
@ cdecl _o_strtol(str ptr long) ucrtbase._o_strtol
@ cdecl _o_strtold(str ptr) ucrtbase._o_strtold
@ cdecl -ret64 _o_strtoll(str ptr long) ucrtbase._o_strtoll
@ cdecl _o_strtoul(str ptr long) ucrtbase._o_strtoul
@ cdecl -ret64 _o_strtoull(str ptr long) ucrtbase._o_strtoull
@ cdecl _o_system(str) ucrtbase._o_system
@ cdecl _o_tan(double) ucrtbase._o_tan
@ cdecl -arch=!i386 _o_tanf(float) ucrtbase._o_tanf
@ cdecl _o_tanh(double) ucrtbase._o_tanh
@ cdecl -arch=!i386 _o_tanhf(float) ucrtbase._o_tanhf
@ cdecl _o_terminate() ucrtbase._o_terminate
@ cdecl _o_tgamma(double) ucrtbase._o_tgamma
@ cdecl _o_tgammaf(float) ucrtbase._o_tgammaf
@ cdecl _o_tgammal(double) ucrtbase._o_tgammal
@ cdecl _o_tmpfile_s(ptr) ucrtbase._o_tmpfile_s
@ cdecl _o_tmpnam_s(ptr long) ucrtbase._o_tmpnam_s
@ cdecl _o_tolower(long) ucrtbase._o_tolower
@ cdecl _o_toupper(long) ucrtbase._o_toupper
@ cdecl _o_towlower(long) ucrtbase._o_towlower
@ cdecl _o_towupper(long) ucrtbase._o_towupper
@ cdecl _o_ungetc(long ptr) ucrtbase._o_ungetc
@ cdecl _o_ungetwc(long ptr) ucrtbase._o_ungetwc
@ cdecl _o_wcrtomb(ptr long ptr) ucrtbase._o_wcrtomb
@ cdecl _o_wcrtomb_s(ptr ptr long long ptr) ucrtbase._o_wcrtomb_s
@ cdecl _o_wcscat_s(wstr long wstr) ucrtbase._o_wcscat_s
@ cdecl _o_wcscoll(wstr wstr) ucrtbase._o_wcscoll
@ cdecl _o_wcscpy(ptr wstr) ucrtbase._o_wcscpy
@ cdecl _o_wcscpy_s(ptr long wstr) ucrtbase._o_wcscpy_s
@ cdecl _o_wcsftime(ptr long wstr ptr) ucrtbase._o_wcsftime
@ cdecl _o_wcsncat_s(wstr long wstr long) ucrtbase._o_wcsncat_s
@ cdecl _o_wcsncpy_s(ptr long wstr long) ucrtbase._o_wcsncpy_s
@ cdecl _o_wcsrtombs(ptr ptr long ptr) ucrtbase._o_wcsrtombs
@ cdecl _o_wcsrtombs_s(ptr ptr long ptr long ptr) ucrtbase._o_wcsrtombs_s
@ cdecl _o_wcstod(wstr ptr) ucrtbase._o_wcstod
@ cdecl _o_wcstof(ptr ptr) ucrtbase._o_wcstof
@ cdecl _o_wcstok(wstr wstr ptr) ucrtbase._o_wcstok
@ cdecl _o_wcstok_s(ptr wstr ptr) ucrtbase._o_wcstok_s
@ cdecl _o_wcstol(wstr ptr long) ucrtbase._o_wcstol
@ cdecl _o_wcstold(wstr ptr ptr) ucrtbase._o_wcstold
@ cdecl -ret64 _o_wcstoll(wstr ptr long) ucrtbase._o_wcstoll
@ cdecl _o_wcstombs(ptr ptr long) ucrtbase._o_wcstombs
@ cdecl _o_wcstombs_s(ptr ptr long wstr long) ucrtbase._o_wcstombs_s
@ cdecl _o_wcstoul(wstr ptr long) ucrtbase._o_wcstoul
@ cdecl -ret64 _o_wcstoull(wstr ptr long) ucrtbase._o_wcstoull
@ cdecl _o_wctob(long) ucrtbase._o_wctob
@ cdecl _o_wctomb(ptr long) ucrtbase._o_wctomb
@ cdecl _o_wctomb_s(ptr ptr long long) ucrtbase._o_wctomb_s
@ cdecl _o_wmemcpy_s(ptr long ptr long) ucrtbase._o_wmemcpy_s
@ cdecl _o_wmemmove_s(ptr long ptr long) ucrtbase._o_wmemmove_s
@ varargs _open(str long) ucrtbase._open
@ cdecl _open_osfhandle(long long) ucrtbase._open_osfhandle
@ cdecl _pclose(ptr) ucrtbase._pclose
@ cdecl _pipe(ptr long long) ucrtbase._pipe
@ cdecl _popen(str str) ucrtbase._popen
@ cdecl _purecall() ucrtbase._purecall
@ cdecl _putc_nolock(long ptr) ucrtbase._putc_nolock
@ cdecl _putch(long) ucrtbase._putch
@ cdecl _putch_nolock(long) ucrtbase._putch_nolock
@ cdecl _putenv(str) ucrtbase._putenv
@ cdecl _putenv_s(str str) ucrtbase._putenv_s
@ cdecl _putw(long ptr) ucrtbase._putw
@ cdecl _putwc_nolock(long ptr) ucrtbase._putwc_nolock
@ cdecl _putwch(long) ucrtbase._putwch
@ cdecl _putwch_nolock(long) ucrtbase._putwch_nolock
@ cdecl _putws(wstr) ucrtbase._putws
@ stub _query_app_type
@ cdecl _query_new_handler() ucrtbase._query_new_handler
@ cdecl _query_new_mode() ucrtbase._query_new_mode
@ cdecl _read(long ptr long) ucrtbase._read
@ cdecl _realloc_base(ptr long) ucrtbase._realloc_base
@ cdecl _recalloc(ptr long long) ucrtbase._recalloc
@ cdecl _register_onexit_function(ptr ptr) ucrtbase._register_onexit_function
@ cdecl _register_thread_local_exe_atexit_callback(ptr) ucrtbase._register_thread_local_exe_atexit_callback
@ cdecl _resetstkoflw() ucrtbase._resetstkoflw
@ cdecl _rmdir(str) ucrtbase._rmdir
@ cdecl _rmtmp() ucrtbase._rmtmp
@ cdecl _rotl(long long) ucrtbase._rotl
@ cdecl -ret64 _rotl64(int64 long) ucrtbase._rotl64
@ cdecl _rotr(long long) ucrtbase._rotr
@ cdecl -ret64 _rotr64(int64 long) ucrtbase._rotr64
@ cdecl _scalb(double long) ucrtbase._scalb
@ cdecl -arch=x86_64 _scalbf(float long) ucrtbase._scalbf
@ cdecl _searchenv(str str ptr) ucrtbase._searchenv
@ cdecl _searchenv_s(str str ptr long) ucrtbase._searchenv_s
@ cdecl _seh_filter_dll(long ptr) ucrtbase._seh_filter_dll
@ cdecl _seh_filter_exe(long ptr) ucrtbase._seh_filter_exe
@ cdecl -arch=win64 _set_FMA3_enable(long) ucrtbase._set_FMA3_enable
@ stdcall -arch=i386 _seh_longjmp_unwind4(ptr) ucrtbase._seh_longjmp_unwind4
@ stdcall -arch=i386 _seh_longjmp_unwind(ptr) ucrtbase._seh_longjmp_unwind
@ cdecl -arch=i386 _set_SSE2_enable(long) ucrtbase._set_SSE2_enable
@ cdecl _set_abort_behavior(long long) ucrtbase._set_abort_behavior
@ cdecl _set_app_type(long) ucrtbase._set_app_type
@ cdecl _set_controlfp(long long) ucrtbase._set_controlfp
@ cdecl _set_doserrno(long) ucrtbase._set_doserrno
@ cdecl _set_errno(long) ucrtbase._set_errno
@ cdecl _set_error_mode(long) ucrtbase._set_error_mode
@ cdecl _set_fmode(long) ucrtbase._set_fmode
@ cdecl _set_invalid_parameter_handler(ptr) ucrtbase._set_invalid_parameter_handler
@ cdecl _set_new_handler(ptr) ucrtbase._set_new_handler
@ cdecl _set_new_mode(long) ucrtbase._set_new_mode
@ cdecl _set_printf_count_output(long) ucrtbase._set_printf_count_output
@ cdecl _set_purecall_handler(ptr) ucrtbase._set_purecall_handler
@ cdecl _set_se_translator(ptr) ucrtbase._set_se_translator
@ cdecl _set_thread_local_invalid_parameter_handler(ptr) ucrtbase._set_thread_local_invalid_parameter_handler
@ cdecl _seterrormode(long) ucrtbase._seterrormode
@ cdecl -arch=i386 -norelay _setjmp3(ptr long) ucrtbase._setjmp3
@ cdecl _setmaxstdio(long) ucrtbase._setmaxstdio
@ cdecl _setmbcp(long) ucrtbase._setmbcp
@ cdecl _setmode(long long) ucrtbase._setmode
@ stub _setsystime(ptr long)
@ cdecl _sleep(long) ucrtbase._sleep
@ varargs _sopen(str long long) ucrtbase._sopen
@ cdecl _sopen_dispatch(str long long long ptr long) ucrtbase._sopen_dispatch
@ cdecl _sopen_s(ptr str long long long) ucrtbase._sopen_s
@ varargs _spawnl(long str str) ucrtbase._spawnl
@ varargs _spawnle(long str str) ucrtbase._spawnle
@ varargs _spawnlp(long str str) ucrtbase._spawnlp
@ varargs _spawnlpe(long str str) ucrtbase._spawnlpe
@ cdecl _spawnv(long str ptr) ucrtbase._spawnv
@ cdecl _spawnve(long str ptr ptr) ucrtbase._spawnve
@ cdecl _spawnvp(long str ptr) ucrtbase._spawnvp
@ cdecl _spawnvpe(long str ptr ptr) ucrtbase._spawnvpe
@ cdecl _splitpath(str ptr ptr ptr ptr) ucrtbase._splitpath
@ cdecl _splitpath_s(str ptr long ptr long ptr long ptr long) ucrtbase._splitpath_s
@ cdecl _stat32(str ptr) ucrtbase._stat32
@ cdecl _stat32i64(str ptr) ucrtbase._stat32i64
@ cdecl _stat64(str ptr) ucrtbase._stat64
@ cdecl _stat64i32(str ptr) ucrtbase._stat64i32
@ cdecl _statusfp() ucrtbase._statusfp
@ cdecl -arch=i386 _statusfp2(ptr ptr) ucrtbase._statusfp2
@ cdecl _strcoll_l(str str ptr) ucrtbase._strcoll_l
@ cdecl _strdate(ptr) ucrtbase._strdate
@ cdecl _strdate_s(ptr long) ucrtbase._strdate_s
@ cdecl _strdup(str) ucrtbase._strdup
@ cdecl _strerror(long) ucrtbase._strerror
@ stub _strerror_s
@ cdecl _strftime_l(ptr long str ptr ptr) ucrtbase._strftime_l
@ cdecl _stricmp(str str) ucrtbase._stricmp
@ cdecl _stricmp_l(str str ptr) ucrtbase._stricmp_l
@ cdecl _stricoll(str str) ucrtbase._stricoll
@ cdecl _stricoll_l(str str ptr) ucrtbase._stricoll_l
@ cdecl _strlwr(str) ucrtbase._strlwr
@ cdecl _strlwr_l(str ptr) ucrtbase._strlwr_l
@ cdecl _strlwr_s(ptr long) ucrtbase._strlwr_s
@ cdecl _strlwr_s_l(ptr long ptr) ucrtbase._strlwr_s_l
@ cdecl _strncoll(str str long) ucrtbase._strncoll
@ cdecl _strncoll_l(str str long ptr) ucrtbase._strncoll_l
@ cdecl _strnicmp(str str long) ucrtbase._strnicmp
@ cdecl _strnicmp_l(str str long ptr) ucrtbase._strnicmp_l
@ cdecl _strnicoll(str str long) ucrtbase._strnicoll
@ cdecl _strnicoll_l(str str long ptr) ucrtbase._strnicoll_l
@ cdecl _strnset(str long long) ucrtbase._strnset
@ cdecl _strnset_s(str long long long) ucrtbase._strnset_s
@ cdecl _strrev(str) ucrtbase._strrev
@ cdecl _strset(str long) ucrtbase._strset
@ stub _strset_s
@ cdecl _strtime(ptr) ucrtbase._strtime
@ cdecl _strtime_s(ptr long) ucrtbase._strtime_s
@ cdecl _strtod_l(str ptr ptr) ucrtbase._strtod_l
@ cdecl _strtof_l(str ptr ptr) ucrtbase._strtof_l
@ cdecl -ret64 _strtoi64(str ptr long) ucrtbase._strtoi64
@ cdecl -ret64 _strtoi64_l(str ptr long ptr) ucrtbase._strtoi64_l
@ cdecl -ret64 _strtoimax_l(str ptr long ptr) ucrtbase._strtoimax_l
@ cdecl _strtol_l(str ptr long ptr) ucrtbase._strtol_l
@ cdecl _strtold_l(str ptr ptr) ucrtbase._strtold_l
@ cdecl -ret64 _strtoll_l(str ptr long ptr) ucrtbase._strtoll_l
@ cdecl -ret64 _strtoui64(str ptr long) ucrtbase._strtoui64
@ cdecl -ret64 _strtoui64_l(str ptr long ptr) ucrtbase._strtoui64_l
@ cdecl _strtoul_l(str ptr long ptr) ucrtbase._strtoul_l
@ cdecl -ret64 _strtoull_l(str ptr long ptr) ucrtbase._strtoull_l
@ cdecl -ret64 _strtoumax_l(str ptr long ptr) ucrtbase._strtoumax_l
@ cdecl _strupr(str) ucrtbase._strupr
@ cdecl _strupr_l(str ptr) ucrtbase._strupr_l
@ cdecl _strupr_s(str long) ucrtbase._strupr_s
@ cdecl _strupr_s_l(str long ptr) ucrtbase._strupr_s_l
@ cdecl _strxfrm_l(ptr str long ptr) ucrtbase._strxfrm_l
@ cdecl _swab(str str long) ucrtbase._swab
@ cdecl _tell(long) ucrtbase._tell
@ cdecl -ret64 _telli64(long) ucrtbase._telli64
@ cdecl _tempnam(str str) ucrtbase._tempnam
@ cdecl _time32(ptr) ucrtbase._time32
@ cdecl _time64(ptr) ucrtbase._time64
@ cdecl _timespec32_get(ptr long) ucrtbase._timespec32_get
@ cdecl _timespec64_get(ptr long) ucrtbase._timespec64_get
@ cdecl _tolower(long) ucrtbase._tolower
@ cdecl _tolower_l(long ptr) ucrtbase._tolower_l
@ cdecl _toupper(long) ucrtbase._toupper
@ cdecl _toupper_l(long ptr) ucrtbase._toupper_l
@ cdecl _towlower_l(long ptr) ucrtbase._towlower_l
@ cdecl _towupper_l(long ptr) ucrtbase._towupper_l
@ cdecl _tzset() ucrtbase._tzset
@ cdecl _ui64toa(int64 ptr long) ucrtbase._ui64toa
@ cdecl _ui64toa_s(int64 ptr long long) ucrtbase._ui64toa_s
@ cdecl _ui64tow(int64 ptr long) ucrtbase._ui64tow
@ cdecl _ui64tow_s(int64 ptr long long) ucrtbase._ui64tow_s
@ cdecl _ultoa(long ptr long) ucrtbase._ultoa
@ cdecl _ultoa_s(long ptr long long) ucrtbase._ultoa_s
@ cdecl _ultow(long ptr long) ucrtbase._ultow
@ cdecl _ultow_s(long ptr long long) ucrtbase._ultow_s
@ cdecl _umask(long) ucrtbase._umask
@ stub _umask_s
@ cdecl _ungetc_nolock(long ptr) ucrtbase._ungetc_nolock
@ cdecl _ungetch(long) ucrtbase._ungetch
@ cdecl _ungetch_nolock(long) ucrtbase._ungetch_nolock
@ cdecl _ungetwc_nolock(long ptr) ucrtbase._ungetwc_nolock
@ cdecl _ungetwch(long) ucrtbase._ungetwch
@ cdecl _ungetwch_nolock(long) ucrtbase._ungetwch_nolock
@ cdecl _unlink(str) ucrtbase._unlink
@ cdecl _unloaddll(long) ucrtbase._unloaddll
@ cdecl _unlock_file(ptr) ucrtbase._unlock_file
@ cdecl _unlock_locales() ucrtbase._unlock_locales
@ cdecl _utime32(str ptr) ucrtbase._utime32
@ cdecl _utime64(str ptr) ucrtbase._utime64
@ cdecl _waccess(wstr long) ucrtbase._waccess
@ cdecl _waccess_s(wstr long) ucrtbase._waccess_s
@ cdecl _wasctime(ptr) ucrtbase._wasctime
@ cdecl _wasctime_s(ptr long ptr) ucrtbase._wasctime_s
@ cdecl _wassert(wstr wstr long) ucrtbase._wassert
@ cdecl _wchdir(wstr) ucrtbase._wchdir
@ cdecl _wchmod(wstr long) ucrtbase._wchmod
@ cdecl _wcreat(wstr long) ucrtbase._wcreat
@ cdecl _wcreate_locale(long wstr) ucrtbase._wcreate_locale
@ cdecl _wcscoll_l(wstr wstr ptr) ucrtbase._wcscoll_l
@ cdecl _wcsdup(wstr) ucrtbase._wcsdup
@ cdecl _wcserror(long) ucrtbase._wcserror
@ cdecl _wcserror_s(ptr long long) ucrtbase._wcserror_s
@ cdecl _wcsftime_l(ptr long wstr ptr ptr) ucrtbase._wcsftime_l
@ cdecl _wcsicmp(wstr wstr) ucrtbase._wcsicmp
@ cdecl _wcsicmp_l(wstr wstr ptr) ucrtbase._wcsicmp_l
@ cdecl _wcsicoll(wstr wstr) ucrtbase._wcsicoll
@ cdecl _wcsicoll_l(wstr wstr ptr) ucrtbase._wcsicoll_l
@ cdecl _wcslwr(wstr) ucrtbase._wcslwr
@ cdecl _wcslwr_l(wstr ptr) ucrtbase._wcslwr_l
@ cdecl _wcslwr_s(wstr long) ucrtbase._wcslwr_s
@ cdecl _wcslwr_s_l(wstr long ptr) ucrtbase._wcslwr_s_l
@ cdecl _wcsncoll(wstr wstr long) ucrtbase._wcsncoll
@ cdecl _wcsncoll_l(wstr wstr long ptr) ucrtbase._wcsncoll_l
@ cdecl _wcsnicmp(wstr wstr long) ucrtbase._wcsnicmp
@ cdecl _wcsnicmp_l(wstr wstr long ptr) ucrtbase._wcsnicmp_l
@ cdecl _wcsnicoll(wstr wstr long) ucrtbase._wcsnicoll
@ cdecl _wcsnicoll_l(wstr wstr long ptr) ucrtbase._wcsnicoll_l
@ cdecl _wcsnset(wstr long long) ucrtbase._wcsnset
@ cdecl _wcsnset_s(wstr long long long) ucrtbase._wcsnset_s
@ cdecl _wcsrev(wstr) ucrtbase._wcsrev
@ cdecl _wcsset(wstr long) ucrtbase._wcsset
@ cdecl _wcsset_s(wstr long long) ucrtbase._wcsset_s
@ cdecl _wcstod_l(wstr ptr ptr) ucrtbase._wcstod_l
@ cdecl _wcstof_l(wstr ptr ptr) ucrtbase._wcstof_l
@ cdecl -ret64 _wcstoi64(wstr ptr long) ucrtbase._wcstoi64
@ cdecl -ret64 _wcstoi64_l(wstr ptr long ptr) ucrtbase._wcstoi64_l
@ cdecl -ret64 _wcstoimax_l(wstr ptr long ptr) ucrtbase._wcstoimax_l
@ cdecl _wcstol_l(wstr ptr long ptr) ucrtbase._wcstol_l
@ cdecl _wcstold_l(wstr ptr ptr) ucrtbase._wcstold_l
@ cdecl -ret64 _wcstoll_l(wstr ptr long ptr) ucrtbase._wcstoll_l
@ cdecl _wcstombs_l(ptr ptr long ptr) ucrtbase._wcstombs_l
@ cdecl _wcstombs_s_l(ptr ptr long wstr long ptr) ucrtbase._wcstombs_s_l
@ cdecl -ret64 _wcstoui64(wstr ptr long) ucrtbase._wcstoui64
@ cdecl -ret64 _wcstoui64_l(wstr ptr long ptr) ucrtbase._wcstoui64_l
@ cdecl _wcstoul_l(wstr ptr long ptr) ucrtbase._wcstoul_l
@ cdecl -ret64 _wcstoull_l(wstr ptr long ptr) ucrtbase._wcstoull_l
@ cdecl -ret64 _wcstoumax_l(wstr ptr long ptr) ucrtbase._wcstoumax_l
@ cdecl _wcsupr(wstr) ucrtbase._wcsupr
@ cdecl _wcsupr_l(wstr ptr) ucrtbase._wcsupr_l
@ cdecl _wcsupr_s(wstr long) ucrtbase._wcsupr_s
@ cdecl _wcsupr_s_l(wstr long ptr) ucrtbase._wcsupr_s_l
@ cdecl _wcsxfrm_l(ptr wstr long ptr) ucrtbase._wcsxfrm_l
@ cdecl _wctime32(ptr) ucrtbase._wctime32
@ cdecl _wctime32_s(ptr long ptr) ucrtbase._wctime32_s
@ cdecl _wctime64(ptr) ucrtbase._wctime64
@ cdecl _wctime64_s(ptr long ptr) ucrtbase._wctime64_s
@ cdecl _wctomb_l(ptr long ptr) ucrtbase._wctomb_l
@ cdecl _wctomb_s_l(ptr ptr long long ptr) ucrtbase._wctomb_s_l
@ extern _wctype MSVCRT__wctype
@ cdecl _wdupenv_s(ptr ptr wstr) ucrtbase._wdupenv_s
@ varargs _wexecl(wstr wstr) ucrtbase._wexecl
@ varargs _wexecle(wstr wstr) ucrtbase._wexecle
@ varargs _wexeclp(wstr wstr) ucrtbase._wexeclp
@ varargs _wexeclpe(wstr wstr) ucrtbase._wexeclpe
@ cdecl _wexecv(wstr ptr) ucrtbase._wexecv
@ cdecl _wexecve(wstr ptr ptr) ucrtbase._wexecve
@ cdecl _wexecvp(wstr ptr) ucrtbase._wexecvp
@ cdecl _wexecvpe(wstr ptr ptr) ucrtbase._wexecvpe
@ cdecl _wfdopen(long wstr) ucrtbase._wfdopen
@ cdecl _wfindfirst32(wstr ptr) ucrtbase._wfindfirst32
@ stub _wfindfirst32i64
@ cdecl _wfindfirst64(wstr ptr) ucrtbase._wfindfirst64
@ cdecl _wfindfirst64i32(wstr ptr) ucrtbase._wfindfirst64i32
@ cdecl _wfindnext32(long ptr) ucrtbase._wfindnext32
@ stub _wfindnext32i64
@ cdecl _wfindnext64(long ptr) ucrtbase._wfindnext64
@ cdecl _wfindnext64i32(long ptr) ucrtbase._wfindnext64i32
@ cdecl _wfopen(wstr wstr) ucrtbase._wfopen
@ cdecl _wfopen_s(ptr wstr wstr) ucrtbase._wfopen_s
@ cdecl _wfreopen(wstr wstr ptr) ucrtbase._wfreopen
@ cdecl _wfreopen_s(ptr wstr wstr ptr) ucrtbase._wfreopen_s
@ cdecl _wfsopen(wstr wstr long) ucrtbase._wfsopen
@ cdecl _wfullpath(ptr wstr long) ucrtbase._wfullpath
@ cdecl _wgetcwd(wstr long) ucrtbase._wgetcwd
@ cdecl _wgetdcwd(long wstr long) ucrtbase._wgetdcwd
@ cdecl _wgetenv(wstr) ucrtbase._wgetenv
@ cdecl _wgetenv_s(ptr ptr long wstr) ucrtbase._wgetenv_s
@ cdecl _wmakepath(ptr wstr wstr wstr wstr) ucrtbase._wmakepath
@ cdecl _wmakepath_s(ptr long wstr wstr wstr wstr) ucrtbase._wmakepath_s
@ cdecl _wmkdir(wstr) ucrtbase._wmkdir
@ cdecl _wmktemp(wstr) ucrtbase._wmktemp
@ cdecl _wmktemp_s(wstr long) ucrtbase._wmktemp_s
@ varargs _wopen(wstr long) ucrtbase._wopen
@ cdecl _wperror(wstr) ucrtbase._wperror
@ cdecl _wpopen(wstr wstr) ucrtbase._wpopen
@ cdecl _wputenv(wstr) ucrtbase._wputenv
@ cdecl _wputenv_s(wstr wstr) ucrtbase._wputenv_s
@ cdecl _wremove(wstr) ucrtbase._wremove
@ cdecl _wrename(wstr wstr) ucrtbase._wrename
@ cdecl _write(long ptr long) ucrtbase._write
@ cdecl _wrmdir(wstr) ucrtbase._wrmdir
@ cdecl _wsearchenv(wstr wstr ptr) ucrtbase._wsearchenv
@ cdecl _wsearchenv_s(wstr wstr ptr long) ucrtbase._wsearchenv_s
@ cdecl _wsetlocale(long wstr) ucrtbase._wsetlocale
@ varargs _wsopen(wstr long long) ucrtbase._wsopen
@ cdecl _wsopen_dispatch(wstr long long long ptr long) ucrtbase._wsopen_dispatch
@ cdecl _wsopen_s(ptr wstr long long long) ucrtbase._wsopen_s
@ varargs _wspawnl(long wstr wstr) ucrtbase._wspawnl
@ varargs _wspawnle(long wstr wstr) ucrtbase._wspawnle
@ varargs _wspawnlp(long wstr wstr) ucrtbase._wspawnlp
@ varargs _wspawnlpe(long wstr wstr) ucrtbase._wspawnlpe
@ cdecl _wspawnv(long wstr ptr) ucrtbase._wspawnv
@ cdecl _wspawnve(long wstr ptr ptr) ucrtbase._wspawnve
@ cdecl _wspawnvp(long wstr ptr) ucrtbase._wspawnvp
@ cdecl _wspawnvpe(long wstr ptr ptr) ucrtbase._wspawnvpe
@ cdecl _wsplitpath(wstr ptr ptr ptr ptr) ucrtbase._wsplitpath
@ cdecl _wsplitpath_s(wstr ptr long ptr long ptr long ptr long) ucrtbase._wsplitpath_s
@ cdecl _wstat32(wstr ptr) ucrtbase._wstat32
@ cdecl _wstat32i64(wstr ptr) ucrtbase._wstat32i64
@ cdecl _wstat64(wstr ptr) ucrtbase._wstat64
@ cdecl _wstat64i32(wstr ptr) ucrtbase._wstat64i32
@ cdecl _wstrdate(ptr) ucrtbase._wstrdate
@ cdecl _wstrdate_s(ptr long) ucrtbase._wstrdate_s
@ cdecl _wstrtime(ptr) ucrtbase._wstrtime
@ cdecl _wstrtime_s(ptr long) ucrtbase._wstrtime_s
@ cdecl _wsystem(wstr) ucrtbase._wsystem
@ cdecl _wtempnam(wstr wstr) ucrtbase._wtempnam
@ cdecl _wtmpnam(ptr) ucrtbase._wtmpnam
@ cdecl _wtmpnam_s(ptr long) ucrtbase._wtmpnam_s
@ cdecl _wtof(wstr) ucrtbase._wtof
@ cdecl _wtof_l(wstr ptr) ucrtbase._wtof_l
@ cdecl _wtoi(wstr) ucrtbase._wtoi
@ cdecl -ret64 _wtoi64(wstr) ucrtbase._wtoi64
@ cdecl -ret64 _wtoi64_l(wstr ptr) ucrtbase._wtoi64_l
@ cdecl _wtoi_l(wstr ptr) ucrtbase._wtoi_l
@ cdecl _wtol(wstr) ucrtbase._wtol
@ cdecl _wtol_l(wstr ptr) ucrtbase._wtol_l
@ cdecl -ret64 _wtoll(wstr) ucrtbase._wtoll
@ cdecl -ret64 _wtoll_l(wstr ptr) ucrtbase._wtoll_l
@ cdecl _wunlink(wstr) ucrtbase._wunlink
@ cdecl _wutime32(wstr ptr) ucrtbase._wutime32
@ cdecl _wutime64(wstr ptr) ucrtbase._wutime64
@ cdecl _y0(double) ucrtbase._y0
@ cdecl _y1(double) ucrtbase._y1
@ cdecl _yn(long double) ucrtbase._yn
@ cdecl abort() ucrtbase.abort
@ cdecl abs(long) ucrtbase.abs
@ cdecl acos(double) ucrtbase.acos
@ cdecl -arch=!i386 acosf(float) ucrtbase.acosf
@ cdecl acosh(double) ucrtbase.acosh
@ cdecl acoshf(float) ucrtbase.acoshf
@ cdecl acoshl(double) ucrtbase.acoshl
@ cdecl asctime(ptr) ucrtbase.asctime
@ cdecl asctime_s(ptr long ptr) ucrtbase.asctime_s
@ cdecl asin(double) ucrtbase.asin
@ cdecl -arch=!i386 asinf(float) ucrtbase.asinf
@ cdecl asinh(double) ucrtbase.asinh
@ cdecl asinhf(float) ucrtbase.asinhf
@ cdecl asinhl(double) ucrtbase.asinhl
@ cdecl atan(double) ucrtbase.atan
@ cdecl atan2(double double) ucrtbase.atan2
@ cdecl -arch=!i386 atan2f(float float) ucrtbase.atan2f
@ cdecl -arch=!i386 atanf(float) ucrtbase.atanf
@ cdecl atanh(double) ucrtbase.atanh
@ cdecl atanhf(float) ucrtbase.atanhf
@ cdecl atanhl(double) ucrtbase.atanhl
@ cdecl atof(str) ucrtbase.atof
@ cdecl atoi(str) ucrtbase.atoi
@ cdecl atol(str) ucrtbase.atol
@ cdecl -ret64 atoll(str) ucrtbase.atoll
@ cdecl bsearch(ptr ptr long long ptr) ucrtbase.bsearch
@ cdecl bsearch_s(ptr ptr long long ptr ptr) ucrtbase.bsearch_s
@ cdecl btowc(long) ucrtbase.btowc
@ stub c16rtomb
@ stub c32rtomb
@ stub cabs
@ stub cabsf
@ stub cabsl
@ stub cacos
@ stub cacosf
@ stub cacosh
@ stub cacoshf
@ stub cacoshl
@ stub cacosl
@ cdecl calloc(long long) ucrtbase.calloc
@ cdecl carg(int128) ucrtbase.carg
@ cdecl cargf(int64) ucrtbase.cargf
@ stub cargl
@ stub casin
@ stub casinf
@ stub casinh
@ stub casinhf
@ stub casinhl
@ stub casinl
@ stub catan
@ stub catanf
@ stub catanh
@ stub catanhf
@ stub catanhl
@ stub catanl
@ cdecl cbrt(double) ucrtbase.cbrt
@ cdecl cbrtf(float) ucrtbase.cbrtf
@ cdecl cbrtl(double) ucrtbase.cbrtl
@ stub ccos
@ stub ccosf
@ stub ccosh
@ stub ccoshf
@ stub ccoshl
@ stub ccosl
@ cdecl ceil(double) ucrtbase.ceil
@ cdecl -arch=!i386 ceilf(float) ucrtbase.ceilf
@ cdecl -norelay cexp(int128) ucrtbase.cexp
@ stub cexpf
@ stub cexpl
@ cdecl cimag(int128) ucrtbase.cimag
@ cdecl cimagf(int64) ucrtbase.cimagf
@ stub cimagl
@ cdecl clearerr(ptr) ucrtbase.clearerr
@ cdecl clearerr_s(ptr) ucrtbase.clearerr_s
@ cdecl clock() ucrtbase.clock
@ stub clog
@ stub clog10
@ stub clog10f
@ stub clog10l
@ stub clogf
@ stub clogl
@ stub conj
@ stub conjf
@ stub conjl
@ cdecl copysign(double double) ucrtbase.copysign
@ cdecl copysignf(float float) ucrtbase.copysignf
@ cdecl copysignl(double double) ucrtbase.copysignl
@ cdecl cos(double) ucrtbase.cos
@ cdecl -arch=!i386 cosf(float) ucrtbase.cosf
@ cdecl cosh(double) ucrtbase.cosh
@ cdecl -arch=!i386 coshf(float) ucrtbase.coshf
@ stub cpow
@ stub cpowf
@ stub cpowl
@ stub cproj
@ stub cprojf
@ stub cprojl
@ cdecl creal(int128) ucrtbase.creal
@ cdecl crealf(int64) ucrtbase.crealf
@ stub creall
@ stub csin
@ stub csinf
@ stub csinh
@ stub csinhf
@ stub csinhl
@ stub csinl
@ stub csqrt
@ stub csqrtf
@ stub csqrtl
@ stub ctan
@ stub ctanf
@ stub ctanh
@ stub ctanhf
@ stub ctanhl
@ stub ctanl
@ cdecl -ret64 div(long long) ucrtbase.div
@ cdecl erf(double) ucrtbase.erf
@ cdecl erfc(double) ucrtbase.erfc
@ cdecl erfcf(float) ucrtbase.erfcf
@ cdecl erfcl(double) ucrtbase.erfcl
@ cdecl erff(float) ucrtbase.erff
@ cdecl erfl(double) ucrtbase.erfl
@ cdecl exit(long) ucrtbase.exit
@ cdecl exp(double) ucrtbase.exp
@ cdecl exp2(double) ucrtbase.exp2
@ cdecl exp2f(float) ucrtbase.exp2f
@ cdecl exp2l(double) ucrtbase.exp2l
@ cdecl -arch=!i386 expf(float) ucrtbase.expf
@ cdecl expm1(double) ucrtbase.expm1
@ cdecl expm1f(float) ucrtbase.expm1f
@ cdecl expm1l(double) ucrtbase.expm1l
@ cdecl fabs(double) ucrtbase.fabs
@ cdecl -arch=arm,arm64 fabsf(float) ucrtbase.fabsf
@ cdecl fclose(ptr) ucrtbase.fclose
@ cdecl fdim(double double) ucrtbase.fdim
@ cdecl fdimf(float float) ucrtbase.fdimf
@ cdecl fdiml(double double) ucrtbase.fdiml
@ cdecl feclearexcept(long) ucrtbase.feclearexcept
@ cdecl fegetenv(ptr) ucrtbase.fegetenv
@ cdecl fegetexceptflag(ptr long) ucrtbase.fegetexceptflag
@ cdecl fegetround() ucrtbase.fegetround
@ cdecl feholdexcept(ptr) ucrtbase.feholdexcept
@ cdecl feof(ptr) ucrtbase.feof
@ cdecl ferror(ptr) ucrtbase.ferror
@ cdecl fesetenv(ptr) ucrtbase.fesetenv
@ cdecl fesetexceptflag(ptr long) ucrtbase.fesetexceptflag
@ cdecl fesetround(long) ucrtbase.fesetround
@ cdecl fetestexcept(long) ucrtbase.fetestexcept
@ cdecl fflush(ptr) ucrtbase.fflush
@ cdecl fgetc(ptr) ucrtbase.fgetc
@ cdecl fgetpos(ptr ptr) ucrtbase.fgetpos
@ cdecl fgets(ptr long ptr) ucrtbase.fgets
@ cdecl fgetwc(ptr) ucrtbase.fgetwc
@ cdecl fgetws(ptr long ptr) ucrtbase.fgetws
@ cdecl floor(double) ucrtbase.floor
@ cdecl -arch=!i386 floorf(float) ucrtbase.floorf
@ cdecl fma(double double double) ucrtbase.fma
@ cdecl fmaf(float float float) ucrtbase.fmaf
@ cdecl fmal(double double double) ucrtbase.fmal
@ cdecl fmax(double double) ucrtbase.fmax
@ cdecl fmaxf(float float) ucrtbase.fmaxf
@ cdecl fmaxl(double double) ucrtbase.fmaxl
@ cdecl fmin(double double) ucrtbase.fmin
@ cdecl fminf(float float) ucrtbase.fminf
@ cdecl fminl(double double) ucrtbase.fminl
@ cdecl fmod(double double) ucrtbase.fmod
@ cdecl -arch=!i386 fmodf(float float) ucrtbase.fmodf
@ cdecl fopen(str str) ucrtbase.fopen
@ cdecl fopen_s(ptr str str) ucrtbase.fopen_s
@ cdecl fputc(long ptr) ucrtbase.fputc
@ cdecl fputs(str ptr) ucrtbase.fputs
@ cdecl fputwc(long ptr) ucrtbase.fputwc
@ cdecl fputws(wstr ptr) ucrtbase.fputws
@ cdecl fread(ptr long long ptr) ucrtbase.fread
@ cdecl fread_s(ptr long long long ptr) ucrtbase.fread_s
@ cdecl free(ptr) ucrtbase.free
@ cdecl freopen(str str ptr) ucrtbase.freopen
@ cdecl freopen_s(ptr str str ptr) ucrtbase.freopen_s
@ cdecl frexp(double ptr) ucrtbase.frexp
@ cdecl fseek(ptr long long) ucrtbase.fseek
@ cdecl fsetpos(ptr ptr) ucrtbase.fsetpos
@ cdecl ftell(ptr) ucrtbase.ftell
@ cdecl fwrite(ptr long long ptr) ucrtbase.fwrite
@ cdecl getc(ptr) ucrtbase.getc
@ cdecl getchar() ucrtbase.getchar
@ cdecl getenv(str) ucrtbase.getenv
@ cdecl getenv_s(ptr ptr long str) ucrtbase.getenv_s
@ cdecl gets(str) ucrtbase.gets
@ cdecl gets_s(ptr long) ucrtbase.gets_s
@ cdecl getwc(ptr) ucrtbase.getwc
@ cdecl getwchar() ucrtbase.getwchar
@ cdecl hypot(double double) ucrtbase.hypot
@ cdecl ilogb(double) ucrtbase.ilogb
@ cdecl ilogbf(float) ucrtbase.ilogbf
@ cdecl ilogbl(double) ucrtbase.ilogbl
@ cdecl -ret64 imaxabs(int64) ucrtbase.imaxabs
@ cdecl -norelay imaxdiv(int64 int64) ucrtbase.imaxdiv
@ cdecl is_wctype(long long) ucrtbase.is_wctype
@ cdecl isalnum(long) ucrtbase.isalnum
@ cdecl isalpha(long) ucrtbase.isalpha
@ cdecl isblank(long) ucrtbase.isblank
@ cdecl iscntrl(long) ucrtbase.iscntrl
@ cdecl isdigit(long) ucrtbase.isdigit
@ cdecl isgraph(long) ucrtbase.isgraph
@ cdecl isleadbyte(long) ucrtbase.isleadbyte
@ cdecl islower(long) ucrtbase.islower
@ cdecl isprint(long) ucrtbase.isprint
@ cdecl ispunct(long) ucrtbase.ispunct
@ cdecl isspace(long) ucrtbase.isspace
@ cdecl isupper(long) ucrtbase.isupper
@ cdecl iswalnum(long) ucrtbase.iswalnum
@ cdecl iswalpha(long) ucrtbase.iswalpha
@ cdecl iswascii(long) ucrtbase.iswascii
@ cdecl iswblank(long) ucrtbase.iswblank
@ cdecl iswcntrl(long) ucrtbase.iswcntrl
@ cdecl iswctype(long long) ucrtbase.iswctype
@ cdecl iswdigit(long) ucrtbase.iswdigit
@ cdecl iswgraph(long) ucrtbase.iswgraph
@ cdecl iswlower(long) ucrtbase.iswlower
@ cdecl iswprint(long) ucrtbase.iswprint
@ cdecl iswpunct(long) ucrtbase.iswpunct
@ cdecl iswspace(long) ucrtbase.iswspace
@ cdecl iswupper(long) ucrtbase.iswupper
@ cdecl iswxdigit(long) ucrtbase.iswxdigit
@ cdecl isxdigit(long) ucrtbase.isxdigit
@ cdecl labs(long) ucrtbase.labs
@ cdecl ldexp(double long) ucrtbase.ldexp
@ cdecl -ret64 ldiv(long long) ucrtbase.ldiv
@ cdecl lgamma(double) ucrtbase.lgamma
@ cdecl lgammaf(float) ucrtbase.lgammaf
@ cdecl lgammal(double) ucrtbase.lgammal
@ cdecl -ret64 llabs(int64) ucrtbase.llabs
@ cdecl -norelay lldiv(int64 int64) ucrtbase.lldiv
@ cdecl -ret64 llrint(double) ucrtbase.llrint
@ cdecl -ret64 llrintf(float) ucrtbase.llrintf
@ cdecl -ret64 llrintl(double) ucrtbase.llrintl
@ cdecl -ret64 llround(double) ucrtbase.llround
@ cdecl -ret64 llroundf(float) ucrtbase.llroundf
@ cdecl -ret64 llroundl(double) ucrtbase.llroundl
@ cdecl localeconv() ucrtbase.localeconv
@ cdecl log(double) ucrtbase.log
@ cdecl log10(double) ucrtbase.log10
@ cdecl -arch=!i386 log10f(float) ucrtbase.log10f
@ cdecl log1p(double) ucrtbase.log1p
@ cdecl log1pf(float) ucrtbase.log1pf
@ cdecl log1pl(double) ucrtbase.log1pl
@ cdecl log2(double) ucrtbase.log2
@ cdecl log2f(float) ucrtbase.log2f
@ cdecl log2l(double) ucrtbase.log2l
@ cdecl logb(double) ucrtbase.logb
@ cdecl logbf(float) ucrtbase.logbf
@ cdecl logbl(double) ucrtbase.logbl
@ cdecl -arch=!i386 logf(float) ucrtbase.logf
@ cdecl longjmp(ptr long) ucrtbase.longjmp
@ cdecl lrint(double) ucrtbase.lrint
@ cdecl lrintf(float) ucrtbase.lrintf
@ cdecl lrintl(double) ucrtbase.lrintl
@ cdecl lround(double) ucrtbase.lround
@ cdecl lroundf(float) ucrtbase.lroundf
@ cdecl lroundl(double) ucrtbase.lroundl
@ cdecl malloc(long) ucrtbase.malloc
@ cdecl mblen(ptr long) ucrtbase.mblen
@ cdecl mbrlen(ptr long ptr) ucrtbase.mbrlen
@ stub mbrtoc16
@ stub mbrtoc32
@ cdecl mbrtowc(ptr str long ptr) ucrtbase.mbrtowc
@ cdecl mbsrtowcs(ptr ptr long ptr) ucrtbase.mbsrtowcs
@ cdecl mbsrtowcs_s(ptr ptr long ptr long ptr) ucrtbase.mbsrtowcs_s
@ cdecl mbstowcs(ptr str long) ucrtbase.mbstowcs
@ cdecl mbstowcs_s(ptr ptr long str long) ucrtbase.mbstowcs_s
@ cdecl mbtowc(ptr str long) ucrtbase.mbtowc
@ cdecl memchr(ptr long long) ucrtbase.memchr
@ cdecl memcmp(ptr ptr long) ucrtbase.memcmp
@ cdecl memcpy(ptr ptr long) ucrtbase.memcpy
@ cdecl memcpy_s(ptr long ptr long) ucrtbase.memcpy_s
@ cdecl memmove(ptr ptr long) ucrtbase.memmove
@ cdecl memmove_s(ptr long ptr long) ucrtbase.memmove_s
@ cdecl memset(ptr long long) ucrtbase.memset
@ cdecl modf(double ptr) ucrtbase.modf
@ cdecl -arch=!i386 modff(float ptr) ucrtbase.modff
@ cdecl nan(str) ucrtbase.nan
@ cdecl nanf(str) ucrtbase.nanf
@ cdecl nanl(str) ucrtbase.nanl
@ cdecl nearbyint(double) ucrtbase.nearbyint
@ cdecl nearbyintf(float) ucrtbase.nearbyintf
@ cdecl nearbyintl(double) ucrtbase.nearbyintl
@ cdecl nextafter(double double) ucrtbase.nextafter
@ cdecl nextafterf(float float) ucrtbase.nextafterf
@ cdecl nextafterl(double double) ucrtbase.nextafterl
@ cdecl nexttoward(double double) ucrtbase.nexttoward
@ cdecl nexttowardf(float double) ucrtbase.nexttowardf
@ cdecl nexttowardl(double double) ucrtbase.nexttowardl
@ stub norm
@ stub normf
@ stub norml
@ cdecl perror(str) ucrtbase.perror
@ cdecl pow(double double) ucrtbase.pow
@ cdecl powf(float float) ucrtbase.powf
@ cdecl putc(long ptr) ucrtbase.putc
@ cdecl putchar(long) ucrtbase.putchar
@ cdecl puts(str) ucrtbase.puts
@ cdecl putwc(long ptr) ucrtbase.putwc
@ cdecl putwchar(long) ucrtbase.putwchar
@ cdecl qsort(ptr long long ptr) ucrtbase.qsort
@ cdecl qsort_s(ptr long long ptr ptr) ucrtbase.qsort_s
@ cdecl quick_exit(long) ucrtbase.quick_exit
@ cdecl raise(long) ucrtbase.raise
@ cdecl rand() ucrtbase.rand
@ cdecl rand_s(ptr) ucrtbase.rand_s
@ cdecl realloc(ptr long) ucrtbase.realloc
@ cdecl remainder(double double) ucrtbase.remainder
@ cdecl remainderf(float float) ucrtbase.remainderf
@ cdecl remainderl(double double) ucrtbase.remainderl
@ cdecl remove(str) ucrtbase.remove
@ cdecl remquo(double double ptr) ucrtbase.remquo
@ cdecl remquof(float float ptr) ucrtbase.remquof
@ cdecl remquol(double double ptr) ucrtbase.remquol
@ cdecl rename(str str) ucrtbase.rename
@ cdecl -arch=i386 rewind(ptr) ucrtbase.rewind
@ cdecl -arch=!i386 rewind(ptr) ucrtbase.rewind
@ cdecl rint(double) ucrtbase.rint
@ cdecl rintf(float) ucrtbase.rintf
@ cdecl rintl(double) ucrtbase.rintl
@ cdecl round(double) ucrtbase.round
@ cdecl roundf(float) ucrtbase.roundf
@ cdecl roundl(double) ucrtbase.roundl
@ cdecl scalbln(double long) ucrtbase.scalbln
@ cdecl scalblnf(float long) ucrtbase.scalblnf
@ cdecl scalblnl(double long) ucrtbase.scalblnl
@ cdecl scalbn(double long) ucrtbase.scalbn
@ cdecl scalbnf(float long) ucrtbase.scalbnf
@ cdecl scalbnl(double long) ucrtbase.scalbnl
@ cdecl set_terminate(ptr) ucrtbase.set_terminate
@ cdecl set_unexpected(ptr) ucrtbase.set_unexpected
@ cdecl setbuf(ptr ptr) ucrtbase.setbuf
@ cdecl -arch=arm,x86_64 -norelay -private setjmp(ptr ptr) ucrtbase.setjmp
@ cdecl setlocale(long str) ucrtbase.setlocale
@ cdecl setvbuf(ptr str long long) ucrtbase.setvbuf
@ cdecl signal(long long) ucrtbase.signal
@ cdecl sin(double) ucrtbase.sin
@ cdecl -arch=!i386 sinf(float) ucrtbase.sinf
@ cdecl sinh(double) ucrtbase.sinh
@ cdecl -arch=!i386 sinhf(float) ucrtbase.sinhf
@ cdecl sqrt(double) ucrtbase.sqrt
@ cdecl -arch=!i386 sqrtf(float) ucrtbase.sqrtf
@ cdecl srand(long) ucrtbase.srand
@ cdecl strcat(str str) ucrtbase.strcat
@ cdecl strcat_s(str long str) ucrtbase.strcat_s
@ cdecl strchr(str long) ucrtbase.strchr
@ cdecl strcmp(str str) ucrtbase.strcmp
@ cdecl strcoll(str str) ucrtbase.strcoll
@ cdecl strcpy(ptr str) ucrtbase.strcpy
@ cdecl strcpy_s(ptr long str) ucrtbase.strcpy_s
@ cdecl strcspn(str str) ucrtbase.strcspn
@ cdecl strerror(long) ucrtbase.strerror
@ cdecl strerror_s(ptr long long) ucrtbase.strerror_s
@ cdecl strftime(ptr long str ptr) ucrtbase.strftime
@ cdecl strlen(str) ucrtbase.strlen
@ cdecl strncat(str str long) ucrtbase.strncat
@ cdecl strncat_s(str long str long) ucrtbase.strncat_s
@ cdecl strncmp(str str long) ucrtbase.strncmp
@ cdecl strncpy(ptr str long) ucrtbase.strncpy
@ cdecl strncpy_s(ptr long str long) ucrtbase.strncpy_s
@ cdecl strnlen(str long) ucrtbase.strnlen
@ cdecl strpbrk(str str) ucrtbase.strpbrk
@ cdecl strrchr(str long) ucrtbase.strrchr
@ cdecl strspn(str str) ucrtbase.strspn
@ cdecl strstr(str str) ucrtbase.strstr
@ cdecl strtod(str ptr) ucrtbase.strtod
@ cdecl strtof(str ptr) ucrtbase.strtof
@ cdecl -ret64 strtoimax(str ptr long) ucrtbase.strtoimax
@ cdecl strtok(str str) ucrtbase.strtok
@ cdecl strtok_s(ptr str ptr) ucrtbase.strtok_s
@ cdecl strtol(str ptr long) ucrtbase.strtol
@ cdecl strtold(str ptr) ucrtbase.strtold
@ cdecl -ret64 strtoll(str ptr long) ucrtbase.strtoll
@ cdecl strtoul(str ptr long) ucrtbase.strtoul
@ cdecl -ret64 strtoull(str ptr long) ucrtbase.strtoull
@ cdecl -ret64 strtoumax(str ptr long) ucrtbase.strtoumax
@ cdecl strxfrm(ptr str long) ucrtbase.strxfrm
@ cdecl system(str) ucrtbase.system
@ cdecl tan(double) ucrtbase.tan
@ cdecl -arch=!i386 tanf(float) ucrtbase.tanf
@ cdecl tanh(double) ucrtbase.tanh
@ cdecl -arch=!i386 tanhf(float) ucrtbase.tanhf
@ cdecl terminate() ucrtbase.terminate
@ cdecl tgamma(double) ucrtbase.tgamma
@ cdecl tgammaf(float) ucrtbase.tgammaf
@ cdecl tgammal(double) ucrtbase.tgammal
@ cdecl tmpfile() ucrtbase.tmpfile
@ cdecl tmpfile_s(ptr) ucrtbase.tmpfile_s
@ cdecl tmpnam(ptr) ucrtbase.tmpnam
@ cdecl tmpnam_s(ptr long) ucrtbase.tmpnam_s
@ cdecl tolower(long) ucrtbase.tolower
@ cdecl toupper(long) ucrtbase.toupper
@ cdecl towctrans(long long) ucrtbase.towctrans
@ cdecl towlower(long) ucrtbase.towlower
@ cdecl towupper(long) ucrtbase.towupper
@ cdecl trunc(double) ucrtbase.trunc
@ cdecl truncf(float) ucrtbase.truncf
@ cdecl truncl(double) ucrtbase.truncl
@ stub unexpected
@ cdecl ungetc(long ptr) ucrtbase.ungetc
@ cdecl ungetwc(long ptr) ucrtbase.ungetwc
@ cdecl wcrtomb(ptr long ptr) ucrtbase.wcrtomb
@ cdecl wcrtomb_s(ptr ptr long long ptr) ucrtbase.wcrtomb_s
@ cdecl wcscat(wstr wstr) ucrtbase.wcscat
@ cdecl wcscat_s(wstr long wstr) ucrtbase.wcscat_s
@ cdecl wcschr(wstr long) ucrtbase.wcschr
@ cdecl wcscmp(wstr wstr) ucrtbase.wcscmp
@ cdecl wcscoll(wstr wstr) ucrtbase.wcscoll
@ cdecl wcscpy(ptr wstr) ucrtbase.wcscpy
@ cdecl wcscpy_s(ptr long wstr) ucrtbase.wcscpy_s
@ cdecl wcscspn(wstr wstr) ucrtbase.wcscspn
@ cdecl wcsftime(ptr long wstr ptr) ucrtbase.wcsftime
@ cdecl wcslen(wstr) ucrtbase.wcslen
@ cdecl wcsncat(wstr wstr long) ucrtbase.wcsncat
@ cdecl wcsncat_s(wstr long wstr long) ucrtbase.wcsncat_s
@ cdecl wcsncmp(wstr wstr long) ucrtbase.wcsncmp
@ cdecl wcsncpy(ptr wstr long) ucrtbase.wcsncpy
@ cdecl wcsncpy_s(ptr long wstr long) ucrtbase.wcsncpy_s
@ cdecl wcsnlen(wstr long) ucrtbase.wcsnlen
@ cdecl wcspbrk(wstr wstr) ucrtbase.wcspbrk
@ cdecl wcsrchr(wstr long) ucrtbase.wcsrchr
@ cdecl wcsrtombs(ptr ptr long ptr) ucrtbase.wcsrtombs
@ cdecl wcsrtombs_s(ptr ptr long ptr long ptr) ucrtbase.wcsrtombs_s
@ cdecl wcsspn(wstr wstr) ucrtbase.wcsspn
@ cdecl wcsstr(wstr wstr) ucrtbase.wcsstr
@ cdecl wcstod(wstr ptr) ucrtbase.wcstod
@ cdecl wcstof(ptr ptr) ucrtbase.wcstof
@ cdecl -ret64 wcstoimax(wstr ptr long) ucrtbase.wcstoimax
@ cdecl wcstok(wstr wstr ptr) ucrtbase.wcstok
@ cdecl wcstok_s(ptr wstr ptr) ucrtbase.wcstok_s
@ cdecl wcstol(wstr ptr long) ucrtbase.wcstol
@ cdecl wcstold(wstr ptr) ucrtbase.wcstold
@ cdecl -ret64 wcstoll(wstr ptr long) ucrtbase.wcstoll
@ cdecl wcstombs(ptr ptr long) ucrtbase.wcstombs
@ cdecl wcstombs_s(ptr ptr long wstr long) ucrtbase.wcstombs_s
@ cdecl wcstoul(wstr ptr long) ucrtbase.wcstoul
@ cdecl -ret64 wcstoull(wstr ptr long) ucrtbase.wcstoull
@ cdecl -ret64 wcstoumax(wstr ptr long) ucrtbase.wcstoumax
@ cdecl wcsxfrm(ptr wstr long) ucrtbase.wcsxfrm
@ cdecl wctob(long) ucrtbase.wctob
@ cdecl wctomb(ptr long) ucrtbase.wctomb
@ cdecl wctomb_s(ptr ptr long long) ucrtbase.wctomb_s
@ cdecl wctrans(str) ucrtbase.wctrans
@ cdecl wctype(str) ucrtbase.wctype
@ cdecl wmemcpy_s(ptr long ptr long) ucrtbase.wmemcpy_s
@ cdecl wmemmove_s(ptr long ptr long) ucrtbase.wmemmove_s
