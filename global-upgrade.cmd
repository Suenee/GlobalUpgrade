@echo off
cls
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
title GlobalUpgrade 1.01

set "GU_VERSION=1.01"
set "OWNER=Suenee"
set "SELF_REPO=GlobalUpgrade"
set "TARGET_BRANCH=main"
set "SELF_FILE=global-upgrade.cmd"

rem ============================================================
rem SELF-UPDATE - phase zero
rem The repository launcher immediately hands control to a unique
rem temporary copy. The repository copy never resumes afterwards.
rem ============================================================
if /i not "%~1"=="--temp-runner" goto :HANDOFF
shift /1
goto :TEMP_RUNNER

:HANDOFF
set "REPO_DIR=%~dp0"
if "%REPO_DIR:~-1%"=="\" set "REPO_DIR=%REPO_DIR:~0,-1%"
set "TEMP_LAUNCHER=%TEMP%\GlobalUpgrade-launcher-%RANDOM%-%RANDOM%.cmd"

copy /y "%~f0" "%TEMP_LAUNCHER%" >nul
if errorlevel 1 (
  echo ERROR: Cannot create temporary GlobalUpgrade launcher.
  exit /b 10
)

rem Use START /WAIT so the repository batch never continues reading
rem after the temporary runner may have replaced it.
start "" /wait cmd /d /c ""%TEMP_LAUNCHER%" --temp-runner "%REPO_DIR%""
set "RC=%ERRORLEVEL%"
del /q "%TEMP_LAUNCHER%" >nul 2>&1
exit /b %RC%

:TEMP_RUNNER
set "REPO_DIR=%~1"
if not defined REPO_DIR (
  echo ERROR: Repository path was lost during self-update handoff.
  exit /b 11
)

pushd "%REPO_DIR%" >nul 2>&1
if errorlevel 1 (
  echo ERROR: Cannot access GlobalUpgrade repository:
  echo %REPO_DIR%
  exit /b 12
)
set "ACTIVE_SELF_DIR=%CD%"
for %%I in ("%ACTIVE_SELF_DIR%\..") do set "ROOT_DIR=%%~fI"

where git.exe >nul 2>&1
if errorlevel 1 (
  echo ERROR: Git was not found in PATH.
  popd
  exit /b 13
)

set "GIT_CONFIG_COUNT=1"
set "GIT_CONFIG_KEY_0=safe.directory"
set "GIT_CONFIG_VALUE_0=%ACTIVE_SELF_DIR%"

echo GlobalUpgrade %GU_VERSION%
echo.
echo [SELF-UPDATE] Checking GlobalUpgrade...

git.exe rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
  echo ERROR: GlobalUpgrade directory is not a Git repository.
  popd
  exit /b 14
)

git.exe fetch origin "%TARGET_BRANCH%" --quiet
if errorlevel 1 (
  echo ERROR: Cannot fetch GlobalUpgrade from GitHub.
  popd
  exit /b 15
)

for /f %%H in ('git.exe rev-parse HEAD 2^>nul') do set "SELF_LOCAL_HEAD=%%H"
for /f %%H in ('git.exe rev-parse "origin/%TARGET_BRANCH%" 2^>nul') do set "SELF_REMOTE_HEAD=%%H"

if not defined SELF_LOCAL_HEAD (
  echo ERROR: Cannot determine local GlobalUpgrade HEAD.
  popd
  exit /b 16
)
if not defined SELF_REMOTE_HEAD (
  echo ERROR: Cannot determine remote GlobalUpgrade HEAD.
  popd
  exit /b 17
)

if /i not "%SELF_LOCAL_HEAD%"=="%SELF_REMOTE_HEAD%" (
  echo [SELF-UPDATE] New GlobalUpgrade revision found.

  rem Protect user/developer changes. The updater never silently destroys them.
  git.exe diff --quiet
  if errorlevel 1 (
    echo ERROR: GlobalUpgrade contains tracked local changes.
    echo Commit or revert them before updating.
    popd
    exit /b 18
  )
  git.exe diff --cached --quiet
  if errorlevel 1 (
    echo ERROR: GlobalUpgrade contains staged local changes.
    echo Commit or revert them before updating.
    popd
    exit /b 19
  )

  git.exe reset --hard "origin/%TARGET_BRANCH%" >nul
  if errorlevel 1 (
    echo ERROR: GlobalUpgrade self-update failed.
    popd
    exit /b 20
  )

  echo [SELF-UPDATE] Updated. Restarting current GlobalUpgrade...
  set "NEW_SELF=%ACTIVE_SELF_DIR%\%SELF_FILE%"
  popd
  if not exist "%NEW_SELF%" (
    echo ERROR: Updated GlobalUpgrade launcher is missing.
    exit /b 21
  )

  rem One-way handoff to the newly synchronized repository launcher.
  call "%NEW_SELF%" --self-restarted
  exit /b %ERRORLEVEL%
)

echo [SELF-UPDATE] Current.
echo.

set "TMP_DIR=%TEMP%\GlobalUpgrade-%RANDOM%-%RANDOM%"
set "RESULT_FILE=%TMP_DIR%\results.tsv"
md "%TMP_DIR%" >nul 2>&1
if errorlevel 1 (
  echo ERROR: Cannot create temporary working directory.
  popd
  exit /b 22
)
> "%RESULT_FILE%" type nul

rem ============================================================
rem DISCOVERY
rem Public GitHub REST API via built-in Windows PowerShell.
rem No GitHub CLI and no GitHub authentication are required.
rem ============================================================
echo Discovering managed repositories...

set "REPO_LIST=%TMP_DIR%\repositories.tsv"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; $h=@{'User-Agent'='GlobalUpgrade/%GU_VERSION%'}; $page=1; $all=@(); do { $u='https://api.github.com/users/%OWNER%/repos?per_page=100&page='+$page; $r=@(Invoke-RestMethod -UseBasicParsing -Headers $h -Uri $u); $all += $r; $page++ } while($r.Count -eq 100); foreach($x in $all){ $d=$x.default_branch; try { Invoke-RestMethod -UseBasicParsing -Headers $h -Uri ('https://api.github.com/repos/%OWNER%/'+$x.name+'/branches/devel') | Out-Null; $b='devel' } catch { $b=$d }; try { Invoke-WebRequest -UseBasicParsing -Headers $h -Uri ('https://raw.githubusercontent.com/%OWNER%/'+$x.name+'/'+$b+'/upgrade.cmd') -Method Head | Out-Null; [Console]::Out.WriteLine($x.name+[char]9+$b) } catch {} }" > "%REPO_LIST%"
if errorlevel 1 (
  echo ERROR: GitHub repository discovery failed.
  rd /s /q "%TMP_DIR%" >nul 2>&1
  popd
  exit /b 23
)

for /f "usebackq tokens=1,2 delims=	" %%A in ("%REPO_LIST%") do (
  call :PROCESS_REPO "%%~A" "%%~B"
)

call :SHOW_SUMMARY
set "FINAL_RC=%ERRORLEVEL%"
rd /s /q "%TMP_DIR%" >nul 2>&1
popd >nul 2>&1
exit /b %FINAL_RC%

:PROCESS_REPO
set "REPO=%~1"
set "BRANCH=%~2"
set "LOCAL_DIR=%ROOT_DIR%\%REPO%"
set "OLD_VER="
set "NEW_VER="
set "INSTALL_MODE=0"

rem GlobalUpgrade has no upgrade.cmd by design, so normally it never reaches
rem this routine. No name-based self exclusion is required.

echo [%REPO%] Checking...

if not exist "%LOCAL_DIR%" (
  md "%LOCAL_DIR%" >nul 2>&1
  if errorlevel 1 (
    call :ADD_RESULT "%REPO%" "" "" "INSTALL" "FAIL"
    exit /b 0
  )
)

call :READ_VERSION "%LOCAL_DIR%" OLD_VER

rem Download authoritative upgrade.cmd before invoking the project.
rem PowerShell is used only as a standard Windows HTTPS client.
set "UPDATER_TMP=%TMP_DIR%\%REPO%-upgrade.tmp"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; Invoke-WebRequest -UseBasicParsing -Headers @{'User-Agent'='GlobalUpgrade/%GU_VERSION%'} -Uri 'https://raw.githubusercontent.com/%OWNER%/%REPO%/%BRANCH%/upgrade.cmd' -OutFile '%UPDATER_TMP%'; $s=[IO.File]::ReadAllText('%UPDATER_TMP%'); $s=$s -replace '\r?\n','\r\n'; [IO.File]::WriteAllText('%LOCAL_DIR%\upgrade.cmd',$s,(New-Object Text.UTF8Encoding($false)))"
if errorlevel 1 (
  call :ADD_RESULT "%REPO%" "%OLD_VER%" "%OLD_VER%" "UPDATER" "FAIL"
  exit /b 0
)

set "NEEDS_RUN=0"
if not exist "%LOCAL_DIR%\.git" (
  set "NEEDS_RUN=1"
  set "INSTALL_MODE=1"
) else (
  pushd "%LOCAL_DIR%" >nul 2>&1
  if errorlevel 1 (
    call :ADD_RESULT "%REPO%" "%OLD_VER%" "%OLD_VER%" "CHECK" "FAIL"
    exit /b 0
  )

  set "GIT_CONFIG_COUNT=1"
  set "GIT_CONFIG_KEY_0=safe.directory"
  set "GIT_CONFIG_VALUE_0=%CD%"

  git.exe fetch origin "%BRANCH%" --quiet >nul 2>&1
  if errorlevel 1 (
    set "NEEDS_RUN=1"
  ) else (
    set "LOCAL_HEAD="
    set "REMOTE_HEAD="
    for /f %%H in ('git.exe rev-parse HEAD 2^>nul') do set "LOCAL_HEAD=%%H"
    for /f %%H in ('git.exe rev-parse "origin/%BRANCH%" 2^>nul') do set "REMOTE_HEAD=%%H"
    if not defined LOCAL_HEAD set "NEEDS_RUN=1"
    if not defined REMOTE_HEAD set "NEEDS_RUN=1"
    if defined LOCAL_HEAD if defined REMOTE_HEAD if /i not "%LOCAL_HEAD%"=="%REMOTE_HEAD%" set "NEEDS_RUN=1"
  )
  popd >nul 2>&1
)

if "%NEEDS_RUN%"=="0" (
  call :READ_VERSION "%LOCAL_DIR%" NEW_VER
  if not defined NEW_VER set "NEW_VER=%OLD_VER%"
  call :ADD_RESULT "%REPO%" "" "%NEW_VER%" "CURRENT" "OK"
  exit /b 0
)

if "%INSTALL_MODE%"=="1" (
  set "OP_STATUS=INSTALL"
) else (
  set "OP_STATUS=UPDATE"
)

pushd "%LOCAL_DIR%" >nul 2>&1
if errorlevel 1 (
  call :ADD_RESULT "%REPO%" "%OLD_VER%" "%OLD_VER%" "%OP_STATUS%" "FAIL"
  exit /b 0
)

call "%LOCAL_DIR%\upgrade.cmd"
set "PROJECT_RC=%ERRORLEVEL%"
popd >nul 2>&1

call :READ_VERSION "%LOCAL_DIR%" NEW_VER
if not defined NEW_VER set "NEW_VER=%OLD_VER%"

if not "%PROJECT_RC%"=="0" (
  call :ADD_RESULT "%REPO%" "%OLD_VER%" "%NEW_VER%" "%OP_STATUS%" "FAIL"
  exit /b 0
)

if "%INSTALL_MODE%"=="1" (
  set "OP_STATUS=INSTALLED"
) else (
  set "OP_STATUS=UPDATED"
)

if /i "%OLD_VER%"=="%NEW_VER%" set "OLD_VER="
call :ADD_RESULT "%REPO%" "%OLD_VER%" "%NEW_VER%" "%OP_STATUS%" "OK"
exit /b 0

:READ_VERSION
set "%~2="
set "V_DIR=%~1"
if exist "%V_DIR%\VERSION" (
  for /f "usebackq tokens=* delims=" %%V in ("%V_DIR%\VERSION") do if not defined %~2 set "%~2=%%V"
)
if not defined %~2 if exist "%V_DIR%\package.json" (
  for /f "usebackq delims=" %%V in (`powershell.exe -NoProfile -Command "$p=Get-Content -Raw -LiteralPath '%V_DIR%\package.json'|ConvertFrom-Json;if($p.version){$p.version}" 2^>nul`) do if not defined %~2 set "%~2=%%V"
)
exit /b 0

:ADD_RESULT
>> "%RESULT_FILE%" echo %~1	%~2	%~3	%~4	%~5
exit /b 0

:SHOW_SUMMARY
cls
echo GLOBAL UPGRADE %GU_VERSION%
echo ==========================================================================================
echo Repository                         Old          Version      Status       Result
echo ------------------------------------------------------------------------------------------
set /a OK_COUNT=0
set /a FAIL_COUNT=0
for /f "usebackq tokens=1-5 delims=	" %%A in ("%RESULT_FILE%") do (
  if /i "%%E"=="OK" (
    set /a OK_COUNT+=1
    powershell.exe -NoProfile -Command "Write-Host ('{0,-34} {1,-12} {2,-12} {3,-12} {4}' -f '%%A','%%B','%%C','%%D','%%E') -ForegroundColor Green"
  ) else (
    set /a FAIL_COUNT+=1
    powershell.exe -NoProfile -Command "Write-Host ('{0,-34} {1,-12} {2,-12} {3,-12} {4}' -f '%%A','%%B','%%C','%%D','%%E') -ForegroundColor Red"
  )
)
echo ------------------------------------------------------------------------------------------
echo.
echo OK: %OK_COUNT%    FAIL: %FAIL_COUNT%
echo.
if %FAIL_COUNT% GTR 0 exit /b 1
exit /b 0
