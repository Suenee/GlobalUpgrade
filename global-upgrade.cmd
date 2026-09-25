@echo off
cls
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
title GlobalUpgrade 1.04

set "GU_VERSION=1.04"
set "GU_REPO=%~dp0"
if "%GU_REPO:~-1%"=="\" set "GU_REPO=%GU_REPO:~0,-1%"
set "GU_TEMP=%TEMP%\GlobalUpgrade-runner-%RANDOM%-%RANDOM%.ps1"

if not defined GU_REPO (
  echo ERROR: GlobalUpgrade repository path is empty.
  exit /b 10
)

where git.exe >nul 2>&1
if errorlevel 1 (
  echo ERROR: Git was not found in PATH.
  exit /b 11
)

pushd "%GU_REPO%" >nul 2>&1
if errorlevel 1 (
  echo ERROR: Cannot access GlobalUpgrade repository:
  echo %GU_REPO%
  exit /b 12
)

set "GIT_CONFIG_COUNT=1"
set "GIT_CONFIG_KEY_0=safe.directory"
set "GIT_CONFIG_VALUE_0=%CD%"

git.exe fetch origin main --quiet
if errorlevel 1 (
  echo ERROR: Cannot fetch GlobalUpgrade from GitHub.
  popd
  exit /b 13
)

git.exe show origin/main:global-upgrade.ps1 > "%GU_TEMP%"
if errorlevel 1 (
  echo ERROR: Cannot extract current GlobalUpgrade runner.
  del /q "%GU_TEMP%" >nul 2>&1
  popd
  exit /b 14
)

popd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%GU_TEMP%" -RepositoryPath "%GU_REPO%"
set "GU_RC=%ERRORLEVEL%"
del /q "%GU_TEMP%" >nul 2>&1
exit /b %GU_RC%
