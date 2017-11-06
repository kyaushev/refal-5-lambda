@echo off
call :MAIN %* || exit /b 1
goto :EOF

:MAIN
setlocal
  call :LOOKUP_COMPILERS
  if {%REFC_EXIST%%SREFC_EXIST%%CREFAL_EXIST%}=={} (
    echo NO REFAL COMPILERS FOUND, EXITING
    exit /b 1
  )

  if {%1}=={} (
    call :RUN_ALL_TESTS *.ref
  ) else (
    call :RUN_ALL_TESTS %*
  )
endlocal
goto :EOF

:LOOKUP_COMPILERS
  :: Без setlocal
  set REFC_EXIST=
  set SREFC_EXIST=
  set CREFAL_EXIST=

  echo *** Detecting Refal-5 compilers ...
  :: Поиск refc/refgo
  if exist detect.rsl erase detect.rsl
  refc detect.ref
  call :CHECK_DETECT_RSL
  if not errorlevel 1 (
    set REFAL_COMPILERS=refc
    set REFC_EXIST=1
    echo ... found refc
  )

  :: Поиск crefal (два варианта)
  call crefal detect.ref 2>NUL
  call :CHECK_DETECT_RSL
  if not errorlevel 1 (
    set REFAL_COMPILERS=crefal %REFAL_COMPILERS%
    set CREFAL_EXIST=1
    set CREFAL_CALL=call crefal
    echo ... found crefal.bat
  ) else (
    refgo crefal detect.ref
    call :CHECK_DETECT_RSL
    if not errorlevel 1 (
      set REFAL_COMPILERS=crefal %REFAL_COMPILERS%
      set CREFAL_EXIST=1
      set CREFAL_CALL=refgo crefal
      echo ... found crefal.rsl
    )
  )

  :: Поиск srefc
  if exist ..\..\bin\srefc-core.exe (
    set REFAL_COMPILERS=srefc %REFAL_COMPILERS%
    set SREFC_EXIST=1
    echo ... found srefc
    call ..\..\c-plus-plus.conf.bat
  )
  echo.
goto :EOF

:CHECK_DETECT_RSL
setlocal
  set RETCODE=1
  if exist detect.rsl (
    refgo detect.rsl > detect.out
    echo detected> detect.expected
    fc detect.out detect.expected >NUL

    if not errorlevel 1 (
      set RETCODE=0
    )

    erase detect.rsl
    if exist detect.out erase detect.out
    if exist detect.expected erase detect.expected
  )
  exit /b %RETCODE%
endlocal
goto :EOF

:RUN_ALL_TESTS
setlocal
  for %%n in (%*) do call :RUN_TEST "%%~nn" "%%~n" || exit /b 1
endlocal
goto :EOF

:RUN_TEST
setlocal
  call :RUN_TEST_RESULT%~x1 "%~2" || exit /b 1
endlocal
goto :EOF

:RUN_TEST_RESULT
  :: Без расширения - ничего не делаем
goto :EOF

:RUN_TEST_RESULT.OK
setlocal
  for %%c in (%REFAL_COMPILERS%) do (
    echo *** Perform OK test %~1 for compiler %%c...
    call :COMPILE.%%c "%~1"
    if errorlevel 1 (
      echo COMPILATION FOR COMPILER %%c FAILED
      endlocal
      exit /b 1
    )
    call :EXECUTE_OK.%%c "%~1" || exit /b 1
    move __out.txt __out.txt.%%c >NUL
    echo %%c>__last.txt
    echo.
  )
  set /P LAST=<__last.txt
  for %%c in (%REFAL_COMPILERS%) do (
    fc __out.txt.%LAST% __out.txt.%%c > __diff.txt
    if errorlevel 1 (
      echo ERROR: Outputs of %%c and %LAST% is different:
      type __diff.txt
      endlocal
      exit /b 1
    )
  )
  for %%c in (%REFAL_COMPILERS%) do (
    call :CLEANUP.%%c "%~n1"
    if exist __out.txt.%%c erase __out.txt.%%c
  )
  erase __last.txt
  if exist __diff.txt erase __diff.txt
endlocal
goto :EOF

:RUN_TEST_RESULT.FAIL
setlocal
  for %%c in (%REFAL_COMPILERS%) do (
    echo *** Perform FAIL test %~1 for compiler %%c...
    call :COMPILE.%%c "%~1"
    if errorlevel 1 (
      echo COMPILATION FOR COMPILER %%c FAILED
      endlocal
      exit /b 1
    )
    call :EXECUTE_FAIL.%%c "%~1" || exit /b 1
    call :CLEANUP.%%c "%~n1"
    echo.
  )
endlocal
goto :EOF

:RUN_TEST_RESULT.SYNTAX-ERROR
setlocal
  for %%c in (%REFAL_COMPILERS%) do (
    echo *** Perform SYNTAX ERROR test %~1 for compiler %%c...
    call :COMPILE.%%c "%~1"
    if not errorlevel 1 (
      echo COMPILATION FOR COMPILER %%c SUCCESSED, SYNTAX ERRORS IS NOT FOUND
      endlocal
      exit /b 1
    ) else (
      echo Ok! This syntax errors is normal and expected!
    )
    call :CLEANUP.%%c "%~n1"
    echo.
  )
endlocal
goto :EOF

:COMPILE.srefc
setlocal
  set COMMON_SRFLAGS= ^
    -c "%CPPLINEE%" ^
    --exesuffix=.exe ^
    -D../../src/srlib ^
    -D../../src/srlib/platform-Windows ^
    -D../../src/srlib/common ^
    --prelude=refal5-builtins.srefi ^
    -f-DSTEP_LIMIT=1000 ^
    -f-DMEMORY_LIMIT=1000 ^
    -f-DDUMP_FILE="\\"__dump.txt\\"" ^
    -f-DDONT_PRINT_STATISTICS ^
    refalrts ^
    refalrts-platform-specific

  copy ..\..\src\srlib\Library.sref .

  set SRC=%1
  set TARGET=%~n1.exe

  ..\..\bin\srefc-core %SRC% -o %TARGET% %COMMON_SRFLAGS% Library 2>__error.txt
  if errorlevel 100 (
    echo COMPILER FAILS ON %SRC%, SEE __error.txt
    exit /b 1
  )
  erase __error.txt
  if not exist %TARGET% (
    endlocal
    exit /b 1
  )

  if exist *.obj erase *.obj
  if exist *.tds erase *.tds
endlocal
goto :EOF

:EXECUTE_OK.srefc
setlocal
  set EXE=%~n1.exe
  %EXE% > __out.txt
  if errorlevel 1 (
    echo TEST FAILED, SEE __dump.txt
    endlocal
    exit /b 1
  )
endlocal
goto :EOF

:EXECUTE_FAIL.srefc
setlocal
  set EXE=%~n1.exe
  %EXE% > __out.txt
  if not errorlevel 1 (
    echo THIS TEST MUST FAIL BUT DONT IT
    endlocal
    exit /b 1
  )
  echo Ok! This failure was normal and expected!
endlocal
exit /b 0

:CLEANUP.srefc
setlocal
  if exist "%~1.rasl" erase "%~1.rasl"
  if exist "%~1.exe" erase "%~1.exe"
  if exist "%~1.cpp" erase "%~1.cpp"
  if exist __dump.txt erase __dump.txt
  if exist __out.txt erase __out.txt
  erase Library.*
endlocal
goto :EOF

:COMPILE.crefal
setlocal
  set RSL="%~n1"-crefal.rsl
  %CREFAL_CALL% "%~1" %RSL%
  if not exist %RSL% (
    endlocal
    exit /b 1
  )
endlocal
goto :EOF

:EXECUTE_OK.crefal
setlocal
  echo Y | refgo "%~n1"-crefal >__out.txt 2>__dump.txt
  if errorlevel 1 (
    echo TEST FAILED, SEE __dump.txt
    endlocal
    exit /b 1
  )
endlocal
goto :EOF

:EXECUTE_FAIL.crefal
setlocal
  echo Y | refgo "%~n1"-crefal >__out.txt 2>__dump.txt
  if not errorlevel 1 (
    echo THIS TEST MUST FAIL BUT DONT IT
    endlocal
    exit /b 1
  )
  echo Ok! Program failed on this test!
endlocal
exit /b 0

:CLEANUP.crefal
setlocal
  if exist "%~1-crefal.rsl" erase "%~1-crefal.rsl"
  if exist "%~1.lis" erase "%~1.lis"
  if exist __dump.txt erase __dump.txt
  if exist __out.txt erase __out.txt
endlocal
goto :EOF

:COMPILE.refc
setlocal
  set RSL="%~n1".rsl
  refc "%~1"
  if not exist %RSL% (
    endlocal
    exit /b 1
  )
endlocal
goto :EOF

:EXECUTE_OK.refc
setlocal
  echo Y | refgo "%~n1" >__out.txt 2>__dump.txt
  if errorlevel 1 (
    echo TEST FAILED, SEE __dump.txt
    endlocal
    exit /b 1
  )
endlocal
goto :EOF

:EXECUTE_FAIL.refc
setlocal
  echo Y | refgo "%~n1" >__out.txt 2>__dump.txt
  if not errorlevel 1 (
    echo THIS TEST MUST FAIL BUT DONT IT
    endlocal
    exit /b 1
  )
  echo Ok! Program failed on this test!
endlocal
exit /b 0

:CLEANUP.refc
setlocal
  if exist "%~1.rsl" erase "%~1.rsl"
  if exist "%~1.lis" erase "%~1.lis"
  if exist __dump.txt erase __dump.txt
  if exist __out.txt erase __out.txt
endlocal
goto :EOF