@echo off
rem ============================================================
rem  DSH Portable - command line (optional)
rem  Sets DSH_HOME to this folder's data dir so it never touches
rem  a system-wide ~/.dsh install.
rem ============================================================
setlocal
set "HERE=%~dp0.."
set "DSH_HOME=%HERE%\data\.dsh"
set "NODE_DIR=%HERE%\node"
if exist "%HERE%\config\api-key.txt" (
  set /p DEEPSEEK_API_KEY=<"%HERE%\config\api-key.txt"
)
"%NODE_DIR%\node.exe" "%NODE_DIR%\node_modules\@deepseek-ai\dsh\lib\bin.js" %*
endlocal
