@echo off
setlocal
cd /d "%~dp0"

echo ============================================================
echo   Trust the DSH-Portable signing certificate (optional)
echo ============================================================
echo.
echo WHAT THIS DOES
echo   Adds ONE certificate to YOUR OWN Windows user account:
echo       CN=Yata-Datacom Portable Release Signing
echo   It is imported into the per-user stores
echo       - Trusted Root Certification Authorities
echo       - Trusted Publishers
echo   of the CURRENT USER only. No administrator rights are used.
echo.
echo WHY YOU WOULD WANT IT
echo   Windows 11 Smart App Control sometimes refuses to run the freshly
echo   built launcher exe ("this file is blocked by your app control
echo   policy"). Trusting the publisher lets that exe run.
echo.
echo YOU DO NOT NEED THIS
echo   The launcher works without it: use "start-dsh.cmd", or the
echo   "start DSH.vbs" entry, which run through Microsoft-signed
echo   powershell.exe and are never blocked. Trusting is a convenience.
echo.
echo HOW TO UNDO IT
echo   Run "untrust-signing-cert.cmd" (same folder). It removes exactly
echo   the certificate this script added and nothing else.
echo.

set "CER=assets\certs\YataDatacom-Release-Signing.cer"
if not exist "%CER%" (
  echo [ERROR] Certificate not found: %CER%
  echo         Run this script from the root of the extracted folder.
  pause
  exit /b 1
)

set "OK="
set /p OK="Type YES to import the certificate: "
if /i not "%OK%"=="YES" (
  echo Cancelled - nothing was changed.
  pause
  exit /b 1
)

echo.
echo [1/2] Trusted Root Certification Authorities
certutil -user -addstore Root "%CER%"
if errorlevel 1 (
  echo [ERROR] importing into Root failed.
  pause
  exit /b 2
)

echo.
echo [2/2] Trusted Publishers
certutil -user -addstore TrustedPublisher "%CER%"
if errorlevel 1 (
  echo [ERROR] importing into Trusted Publishers failed.
  pause
  exit /b 3
)

echo.
echo Done. The launcher exe signed by this certificate is now trusted
echo for your user account. Close this window and start the launcher.
echo.
pause
endlocal
exit /b 0
