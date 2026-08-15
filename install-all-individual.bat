@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo Installing all individual skills, plugins, and MCP sources without merging them...
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-all-individual.ps1" -Targets all -InstallRepoDeps %*
set "EXITCODE=%ERRORLEVEL%"

echo.
if not "%EXITCODE%"=="0" (
  echo Installer finished with errors. Review the report files under:
  echo %%LOCALAPPDATA%%\ai-agent-individual-extensions\reports
) else (
  echo Installation and staging completed.
  echo Review the requirements report before enabling MCP servers or installing repo dependencies.
)
echo.
pause
exit /b %EXITCODE%
