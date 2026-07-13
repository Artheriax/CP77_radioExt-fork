@echo off
setlocal enabledelayedexpansion

:: ────────────────────────────────────────────
::  RadioExt — Build & Package Script
:: ────────────────────────────────────────────

set "TEMP_DIR=_temp"
set "RED4EXT_SRC=red4ext"
set "RED4EXT_DIR=%TEMP_DIR%\red4ext\plugins\RadioExt"
set "CET_DIR=%TEMP_DIR%\bin\x64\plugins\cyber_engine_tweaks\mods\radioExt"

echo.
echo ========================================
echo   RadioExt Packaging
echo ========================================
echo.

:: ── Step 1: Clean & create temp structure ──
echo [1/4] Preparing temp directory...
if exist "%TEMP_DIR%" rmdir /S /Q "%TEMP_DIR%"
mkdir "%RED4EXT_DIR%"
mkdir "%CET_DIR%"

:: ── Step 2: Copy DLLs & scripts ────────────
echo [2/4] Copying files...

echo   radioext.dll  -^>  %RED4EXT_DIR%
copy /Y "%RED4EXT_SRC%\RadioExt.dll" "%RED4EXT_DIR%\radioext.dll" >nul
echo   fmod.dll      -^>  %RED4EXT_DIR%
copy /Y "%RED4EXT_SRC%\fmod.dll"     "%RED4EXT_DIR%" >nul

echo   modules\      -^>  %CET_DIR%\modules\
robocopy "modules" "%CET_DIR%\modules" /E /NFL /NDL /NJH /NJS >nul
echo   radios\       -^>  %CET_DIR%\radios\
robocopy "radios"  "%CET_DIR%\radios"  /E /NFL /NDL /NJH /NJS >nul
echo   init.lua      -^>  %CET_DIR%
copy /Y "init.lua"      "%CET_DIR%" >nul
echo   metadata.json -^>  %CET_DIR%
copy /Y "metadata.json" "%CET_DIR%" >nul

:: ── Step 3: Zip from temp ──────────────────
echo [3/4] Creating archive...

set "VERSION="
for /f "tokens=2 delims=: " %%v in ('findstr /r /c:"\"displayName\"" metadata.json') do (
    set "VERSION=%%~v"
)
if defined VERSION (
    set "ARCHIVE=RadioExt_%VERSION:"=%.zip"
) else (
    set "ARCHIVE=RadioExt.zip"
)

powershell -NoProfile -Command ^
    "if (Test-Path '%ARCHIVE%') { Remove-Item '%ARCHIVE%' }; " ^
    "Compress-Archive -Path '%TEMP_DIR%\bin', '%TEMP_DIR%\red4ext' -DestinationPath '%ARCHIVE%' -Force"

:: ── Step 4: Cleanup ────────────────────────
echo [4/4] Cleaning up...
rmdir /S /Q "%TEMP_DIR%"

echo.
echo ========================================
echo   Done!  Archive: %ARCHIVE%
echo ========================================
echo.
endlocal
