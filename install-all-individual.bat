@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "FIRST_ARG=%~1"
set "INSTALL_SET=all"
set "PASS_ARGS=%*"
if /I "%FIRST_ARG%"=="top10" goto recognized_set
if /I "%FIRST_ARG%"=="top25" goto recognized_set
if /I "%FIRST_ARG%"=="top50" goto recognized_set
if /I "%FIRST_ARG%"=="all" goto recognized_set
goto run_installer

:recognized_set
set "INSTALL_SET=%FIRST_ARG%"
shift
set "PASS_ARGS=%*"

:run_installer
echo Installing %INSTALL_SET% individual skills, plugins, and MCP sources without merging them...
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-all-individual.ps1" -Targets all -InstallSet %INSTALL_SET% -InstallRepoDeps %PASS_ARGS%
set "EXITCODE=%ERRORLEVEL%"

echo.
if not "%EXITCODE%"=="0" (
  echo Installer finished with errors. Review the report files under:
  echo %%LOCALAPPDATA%%\ai-agent-individual-extensions\reports
) else (
  echo Installation and staging completed for %INSTALL_SET%.
  echo Review the final report before enabling MCP servers or installing repo dependencies.
)
echo.
pause
exit /b %EXITCODE%
