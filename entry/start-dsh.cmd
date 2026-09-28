@echo off
rem ============================================================
rem  DSH Portable - console entry (fallback)
rem  Prefer "start DSH.vbs" (no console flash).
rem  This file is intentionally ASCII-only to avoid codepage issues.
rem ============================================================
chcp 65001 >nul 2>&1
setlocal
set "HERE=%~dp0"
if not exist "%HERE%launcher\launcher.ps1" (
  echo [ERROR] launcher\launcher.ps1 not found. Please extract the whole folder.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%HERE%launcher\launcher.ps1"
if errorlevel 1 pause
endlocal
