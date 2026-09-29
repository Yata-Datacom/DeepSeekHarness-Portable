@echo off
setlocal
cd /d "%~dp0"

echo ============================================================
echo   Remove the DSH-Portable signing certificate
echo ============================================================
echo.
echo This undoes "trust-signing-cert.cmd": it deletes the certificate
echo       CN=Yata-Datacom Portable Release Signing
echo   from these per-user stores:
echo       - Trusted Root Certification Authorities
echo       - Trusted Publishers
echo Nothing else on this computer is touched. Other certificates in
echo those stores are left alone.
echo.

set "OK="
set /p OK="Type YES to remove it: "
if /i not "%OK%"=="YES" (
  echo Cancelled - nothing was changed.
  pause
  exit /b 1
)

set "RC=0"

echo.
echo [1/2] Trusted Publishers
certutil -user -delstore TrustedPublisher "Yata-Datacom Portable Release Signing"
if errorlevel 1 (
  echo [WARN] not found in Trusted Publishers - nothing to remove there.
  set "RC=1"
)

echo.
echo [2/2] Trusted Root Certification Authorities
certutil -user -delstore Root "Yata-Datacom Portable Release Signing"
if errorlevel 1 (
  echo [WARN] not found in Trusted Root - nothing to remove there.
  set "RC=1"
)

echo.
if "%RC%"=="0" (
  echo Removed. Restart the launcher if it is running; Windows App Control
  echo treats the exe as untrusted again, so use "start-dsh.cmd" or the
  echo .vbs entry instead.
) else (
  echo The certificate was NOT in both stores - nothing may have been trusted
  echo to begin with. Re-run trust-signing-cert.cmd to see it import, then
  echo this script to see it removed.
)
echo.
pause
endlocal
exit /b 0
