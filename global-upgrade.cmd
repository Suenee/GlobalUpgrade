@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
title GlobalUpgrade 1.00

rem ============================================================
rem GlobalUpgrade 1.00
rem Centralized updater for repositories owned by Suenee.
rem A repository is managed only when upgrade.cmd exists in the
rem selected branch. Branch preference: devel, otherwise default.
rem ============================================================

set "GU_VERSION=1.00"
set "OWNER=Suenee"
set "SELF_DIR=%~dp0"
for %%I in ("%SELF_DIR%..") do set "ROOT_DIR=%%~fI"
set "TMP_DIR=%TEMP%\GlobalUpgrade"
set "RESULT_FILE=%TMP_DIR%\results.tsv"
set "GH=gh"

if exist "%TMP_DIR%" rd /s /q "%TMP_DIR%" >nul 2>&1
md "%TMP_DIR%" >nul 2>&1
if errorlevel 1 (
  echo ERROR: Cannot create temporary directory "%TMP_DIR%".
  exit /b 10
)

> "%RESULT_FILE%" type nul

where %GH% >nul 2>&1
if errorlevel 1 (
  echo ERROR: GitHub CLI ^(gh^) was not found in PATH.
  echo Install GitHub CLI and authenticate it with: gh auth login
  exit /b 11
)

%GH% auth status >nul 2>&1
if errorlevel 1 (
  echo ERROR: GitHub CLI is not authenticated.
  echo Run: gh auth login
  exit /b 12
)

echo GlobalUpgrade %GU_VERSION%
echo Root: %ROOT_DIR%
echo.
echo Discovering repositories...

for /f "usebackq delims=" %%R in (`%GH% repo list %OWNER% --limit 1000 --json name,defaultBranchRef --jq ".[] ^| [.name, (.defaultBranchRef.name // \"main\")] ^| @tsv"`) do (
  for /f "tokens=1,2 delims=	" %%A in ("%%R") do (
    call :ProcessRepo "%%~A" "%%~B"
  )
)

call :ShowSummary
exit /b 0

:ProcessRepo
set "REPO=%~1"
set "DEFAULT_BRANCH=%~2"
set "BRANCH=%DEFAULT_BRANCH%"
set "LOCAL_DIR=%ROOT_DIR%\%REPO%"
set "OLD_VER="
set "NEW_VER="
set "STATUS="
set "RESULT=OK"

rem Prefer devel whenever it exists.
%GH% api "repos/%OWNER%/%REPO%/branches/devel" >nul 2>&1
if not errorlevel 1 set "BRANCH=devel"

rem upgrade.cmd is the opt-in marker. No file = not managed.
%GH% api "repos/%OWNER%/%REPO%/contents/upgrade.cmd?ref=%BRANCH%" >nul 2>&1
if errorlevel 1 exit /b 0

echo.
echo [%REPO%] branch=%BRANCH%

if not exist "%LOCAL_DIR%" (
  md "%LOCAL_DIR%" >nul 2>&1
  if errorlevel 1 (
    call :AddResult "%REPO%" "" "" "INSTALL" "FAIL"
    exit /b 0
  )
)

call :ReadVersion "%LOCAL_DIR%" OLD_VER

rem Always refresh the project updater from the authoritative branch
rem before running it. This also repairs incomplete repositories.
%GH% api -H "Accept: application/vnd.github.raw+json" "repos/%OWNER%/%REPO%/contents/upgrade.cmd?ref=%BRANCH%" > "%LOCAL_DIR%\upgrade.cmd"
if errorlevel 1 (
  call :AddResult "%REPO%" "%OLD_VER%" "%OLD_VER%" "UPDATER" "FAIL"
  exit /b 0
)

rem Determine whether the local repository is complete and current.
set "NEEDS_RUN=0"
set "INSTALL_MODE=0"

if not exist "%LOCAL_DIR%\.git" (
  set "NEEDS_RUN=1"
  set "INSTALL_MODE=1"
) else (
  pushd "%LOCAL_DIR%" >nul 2>&1
  if errorlevel 1 (
    call :AddResult "%REPO%" "%OLD_VER%" "%OLD_VER%" "CHECK" "FAIL"
    exit /b 0
  )

  git remote get-url origin >nul 2>&1
  if errorlevel 1 (
    set "NEEDS_RUN=1"
  ) else (
    git fetch origin "%BRANCH%" --quiet >nul 2>&1
    if errorlevel 1 (
      set "NEEDS_RUN=1"
    ) else (
      for /f %%H in ('git rev-parse HEAD 2^>nul') do set "LOCAL_HEAD=%%H"
      for /f %%H in ('git rev-parse "origin/%BRANCH%" 2^>nul') do set "REMOTE_HEAD=%%H"
      if not defined LOCAL_HEAD set "NEEDS_RUN=1"
      if not defined REMOTE_HEAD set "NEEDS_RUN=1"
      if defined LOCAL_HEAD if defined REMOTE_HEAD if /i not "!LOCAL_HEAD!"=="!REMOTE_HEAD!" set "NEEDS_RUN=1"
    )
  )
  popd >nul 2>&1
)

if "%NEEDS_RUN%"=="0" (
  call :ReadVersion "%LOCAL_DIR%" NEW_VER
  if not defined NEW_VER set "NEW_VER=%OLD_VER%"
  call :AddResult "%REPO%" "" "%NEW_VER%" "CURRENT" "OK"
  exit /b 0
)

if "%INSTALL_MODE%"=="1" (
  set "STATUS=INSTALL"
) else (
  set "STATUS=UPDATE"
)

pushd "%LOCAL_DIR%" >nul 2>&1
if errorlevel 1 (
  call :AddResult "%REPO%" "%OLD_VER%" "%OLD_VER%" "%STATUS%" "FAIL"
  exit /b 0
)

call "%LOCAL_DIR%\upgrade.cmd"
set "RC=!ERRORLEVEL!"
popd >nul 2>&1

call :ReadVersion "%LOCAL_DIR%" NEW_VER
if not defined NEW_VER set "NEW_VER=%OLD_VER%"

if not "%RC%"=="0" (
  call :AddResult "%REPO%" "%OLD_VER%" "%NEW_VER%" "%STATUS%" "FAIL"
  exit /b 0
)

if "%INSTALL_MODE%"=="1" (
  set "STATUS=INSTALLED"
) else (
  set "STATUS=UPDATED"
)

if /i "%OLD_VER%"=="%NEW_VER%" set "OLD_VER="
call :AddResult "%REPO%" "%OLD_VER%" "%NEW_VER%" "%STATUS%" "OK"
exit /b 0

:ReadVersion
set "%~2="
set "V_DIR=%~1"

rem Preferred generic VERSION file.
if exist "%V_DIR%\VERSION" (
  for /f "usebackq tokens=* delims=" %%V in ("%V_DIR%\VERSION") do (
    if not defined %~2 set "%~2=%%V"
  )
)

rem package.json is common in Node.js projects.
if not defined %~2 if exist "%V_DIR%\package.json" (
  for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "$p=Get-Content -Raw -LiteralPath '%V_DIR%\package.json' ^| ConvertFrom-Json; if($p.version){$p.version}" 2^>nul`) do (
    if not defined %~2 set "%~2=%%V"
  )
)

rem Fallback: try to find a simple version declaration in common files.
if not defined %~2 (
  for %%F in ("%V_DIR%\main.js" "%V_DIR%\manifest.json" "%V_DIR%\companion\manifest.json") do (
    if exist "%%~fF" (
      for /f "tokens=2 delims=:, " %%V in ('findstr /i /r /c:"[\"']version[\"'][ ]*:" "%%~fF" 2^>nul') do (
        if not defined %~2 set "%~2=%%~V"
      )
    )
  )
)
exit /b 0

:AddResult
>> "%RESULT_FILE%" echo %~1	%~2	%~3	%~4	%~5
exit /b 0

:ShowSummary
cls
echo GLOBAL UPGRADE %GU_VERSION%
echo ==========================================================================================
echo Repository                         Old          Version      Status       Result
echo ------------------------------------------------------------------------------------------

set /a OK_COUNT=0
set /a FAIL_COUNT=0

for /f "usebackq tokens=1-5 delims=	" %%A in ("%RESULT_FILE%") do (
  set "R_REPO=%%A"
  set "R_OLD=%%B"
  set "R_VER=%%C"
  set "R_STATUS=%%D"
  set "R_RESULT=%%E"

  if /i "!R_RESULT!"=="OK" (
    set /a OK_COUNT+=1
    powershell -NoProfile -Command "Write-Host ('{0,-34} {1,-12} {2,-12} {3,-12} {4}' -f '!R_REPO!','!R_OLD!','!R_VER!','!R_STATUS!','!R_RESULT!') -ForegroundColor Green"
  ) else (
    set /a FAIL_COUNT+=1
    powershell -NoProfile -Command "Write-Host ('{0,-34} {1,-12} {2,-12} {3,-12} {4}' -f '!R_REPO!','!R_OLD!','!R_VER!','!R_STATUS!','!R_RESULT!') -ForegroundColor Red"
  )
)

echo ------------------------------------------------------------------------------------------
echo.
echo OK: %OK_COUNT%    FAIL: %FAIL_COUNT%
echo.
exit /b 0
