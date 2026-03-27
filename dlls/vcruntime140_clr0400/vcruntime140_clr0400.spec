@ cdecl _CreateFrameInfo(ptr ptr) vcruntime140._CreateFrameInfo
@ stdcall _CxxThrowException(ptr ptr) vcruntime140._CxxThrowException
@ cdecl -arch=i386 -norelay _EH_prolog() vcruntime140._EH_prolog
@ cdecl _FindAndUnlinkFrame(ptr) vcruntime140._FindAndUnlinkFrame
@ cdecl _IsExceptionObjectToBeDestroyed(ptr) vcruntime140._IsExceptionObjectToBeDestroyed
@ stub _NLG_Dispatch2
@ stub _NLG_Return
@ stub _NLG_Return2
@ cdecl _SetWinRTOutOfMemoryExceptionCallback(ptr) vcruntime140._SetWinRTOutOfMemoryExceptionCallback
@ cdecl __AdjustPointer(ptr ptr) vcruntime140.__AdjustPointer
@ stub __BuildCatchObject
@ stub __BuildCatchObjectHelper
@ stdcall -arch=!i386 __C_specific_handler(ptr long ptr ptr) vcruntime140.__C_specific_handler
@ stub __C_specific_handler_noexcept
@ cdecl __CxxDetectRethrow(ptr) vcruntime140.__CxxDetectRethrow
@ cdecl __CxxExceptionFilter(ptr ptr long ptr) vcruntime140.__CxxExceptionFilter
@ cdecl -norelay __CxxFrameHandler(ptr ptr ptr ptr) vcruntime140.__CxxFrameHandler
@ cdecl -norelay __CxxFrameHandler2(ptr ptr ptr ptr) vcruntime140.__CxxFrameHandler2
@ cdecl -norelay __CxxFrameHandler3(ptr ptr ptr ptr) vcruntime140.__CxxFrameHandler3
@ stdcall -arch=i386 __CxxLongjmpUnwind(ptr) vcruntime140.__CxxLongjmpUnwind
@ cdecl __CxxQueryExceptionSize() vcruntime140.__CxxQueryExceptionSize
@ cdecl __CxxRegisterExceptionObject(ptr ptr) vcruntime140.__CxxRegisterExceptionObject
@ cdecl __CxxUnregisterExceptionObject(ptr long) vcruntime140.__CxxUnregisterExceptionObject
@ cdecl __DestructExceptionObject(ptr) vcruntime140.__DestructExceptionObject
@ stub __FrameUnwindFilter
@ stub __GetPlatformExceptionInfo
@ stub __NLG_Dispatch2
@ stub __NLG_Return2
@ cdecl __RTCastToVoid(ptr) vcruntime140.__RTCastToVoid
@ cdecl __RTDynamicCast(ptr long ptr ptr long) vcruntime140.__RTDynamicCast
@ cdecl __RTtypeid(ptr) vcruntime140.__RTtypeid
@ stub __TypeMatch
@ cdecl __current_exception() vcruntime140.__current_exception
@ cdecl __current_exception_context() vcruntime140.__current_exception_context
@ cdecl -norelay __intrinsic_setjmp(ptr) vcruntime140.__intrinsic_setjmp
@ cdecl -arch=!i386 -norelay __intrinsic_setjmpex(ptr ptr) vcruntime140.__intrinsic_setjmpex
@ stdcall -arch=arm __jump_unwind(ptr ptr) vcruntime140.__jump_unwind
@ cdecl __processing_throw() vcruntime140.__processing_throw
@ stub __report_gsfailure
@ cdecl __std_exception_copy(ptr ptr) vcruntime140.__std_exception_copy
@ cdecl __std_exception_destroy(ptr) vcruntime140.__std_exception_destroy
@ cdecl __std_terminate() vcruntime140.__std_terminate
@ cdecl __std_type_info_compare(ptr ptr) vcruntime140.__std_type_info_compare
@ cdecl __std_type_info_destroy_list(ptr) vcruntime140.__std_type_info_destroy_list
@ cdecl __std_type_info_hash(ptr) vcruntime140.__std_type_info_hash
@ cdecl __std_type_info_name(ptr ptr) vcruntime140.__std_type_info_name
@ cdecl __telemetry_main_invoke_trigger(ptr) vcruntime140.__telemetry_main_invoke_trigger
@ cdecl __telemetry_main_return_trigger(ptr) vcruntime140.__telemetry_main_return_trigger
@ cdecl __unDName(ptr str long ptr ptr long) vcruntime140.__unDName
@ cdecl __unDNameEx(ptr str long ptr ptr ptr long) vcruntime140.__unDNameEx
@ cdecl __uncaught_exception() vcruntime140.__uncaught_exception
@ cdecl __uncaught_exceptions() vcruntime140.__uncaught_exceptions
@ stub __vcrt_GetModuleFileNameW
@ stub __vcrt_GetModuleHandleW
@ cdecl __vcrt_InitializeCriticalSectionEx(ptr long long) vcruntime140.__vcrt_InitializeCriticalSectionEx
@ stub __vcrt_LoadLibraryExW
@ cdecl -arch=i386 -norelay _chkesp() vcruntime140._chkesp
@ cdecl -arch=i386 _except_handler2(ptr ptr ptr ptr) vcruntime140._except_handler2
@ cdecl -arch=i386 _except_handler3(ptr ptr ptr ptr) vcruntime140._except_handler3
@ cdecl -arch=i386 _except_handler4_common(ptr ptr ptr ptr ptr ptr) vcruntime140._except_handler4_common
@ cdecl _get_purecall_handler() vcruntime140._get_purecall_handler
@ cdecl _get_unexpected() vcruntime140._get_unexpected
@ cdecl -arch=i386 _global_unwind2(ptr) vcruntime140._global_unwind2
@ stub _is_exception_typeof
@ cdecl -arch=i386 _local_unwind2(ptr long) vcruntime140._local_unwind2
@ cdecl -arch=i386 _local_unwind4(ptr ptr long) vcruntime140._local_unwind4
@ cdecl -arch=i386 _longjmpex(ptr long) vcruntime140._longjmpex
@ cdecl -arch=win64 _local_unwind(ptr ptr) vcruntime140._local_unwind
@ cdecl _purecall() vcruntime140._purecall
@ stdcall -arch=i386 _seh_longjmp_unwind4(ptr) vcruntime140._seh_longjmp_unwind4
@ stdcall -arch=i386 _seh_longjmp_unwind(ptr) vcruntime140._seh_longjmp_unwind
@ cdecl _set_purecall_handler(ptr) vcruntime140._set_purecall_handler
@ cdecl _set_se_translator(ptr) vcruntime140._set_se_translator
@ cdecl -arch=i386 -norelay _setjmp3(ptr long) vcruntime140._setjmp3
@ cdecl longjmp(ptr long) vcruntime140.longjmp
@ cdecl memchr(ptr long long) vcruntime140.memchr
@ cdecl memcmp(ptr ptr long) vcruntime140.memcmp
@ cdecl memcpy(ptr ptr long) vcruntime140.memcpy
@ cdecl memmove(ptr ptr long) vcruntime140.memmove
@ cdecl memset(ptr long long) vcruntime140.memset
@ cdecl set_unexpected(ptr) vcruntime140.set_unexpected
@ cdecl strchr(str long) vcruntime140.strchr
@ cdecl strrchr(str long) vcruntime140.strrchr
@ cdecl strstr(str str) vcruntime140.strstr
@ stub unexpected
@ cdecl wcschr(wstr long) vcruntime140.wcschr
@ cdecl wcsrchr(wstr long) vcruntime140.wcsrchr
@ cdecl wcsstr(wstr wstr) vcruntime140.wcsstr
