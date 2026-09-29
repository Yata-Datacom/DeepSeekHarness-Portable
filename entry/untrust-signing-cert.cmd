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

set /p OK="Type YES to remove it: "
if /i not "%OK%"=="YES" (
  echo Cancelled - nothing was changed.
  pause
  exit /b 1
)

echo.
echo [1/2] Trusted Publishers
certutil -user -delstore TrustedPublisher "Yata-Datacom Portable Release Signing"

echo.
echo [2/2] Trusted Root Certification Authorities
certutil -user -delstore Root "Yata-Datacom Portable Release Signing"

echo.
echo Removed. Restart the launcher if it is running; Windows App Control
echo treats the exe as untrusted again, so use "start-dsh.cmd" or the
echo .vbs entry instead.
echo.
pause
endlocal
exit /b 0
