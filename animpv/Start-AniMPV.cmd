@echo off
setlocal
set "animpv_engine=%ANIMPV_MPV%"
if not defined animpv_engine if exist "%~dp0bin\mpv.exe" set "animpv_engine=%~dp0bin\mpv.exe"
if not defined animpv_engine if exist "%~dp0mpv.exe" set "animpv_engine=%~dp0mpv.exe"
if not defined animpv_engine for %%I in (mpv.exe) do set "animpv_engine=%%~$PATH:I"
if not defined animpv_engine goto missing
if not exist "%animpv_engine%" goto missing
if not exist "%~dp0state" mkdir "%~dp0state"
if not exist "%~dp0screenshots" mkdir "%~dp0screenshots"
"%animpv_engine%" --config-dir="%~dp0." -- %*
exit /b %errorlevel%
:missing
echo mpv was not found. Put a standalone mpv engine in animpv\bin or set ANIMPV_MPV.
pause
exit /b 1
