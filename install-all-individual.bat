@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "FIRST_ARG=%~1"
set "PASS_ARGS=%*"
set "INSTALL_SET="

if /I "%FIRST_ARG%"=="top10" (set "INSTALL_SET=top10"& goto run_installer)
if /I "%FIRST_ARG%"=="top25" (set "INSTALL_SET=top25"& goto run_installer)
if /I "%FIRST_ARG%"=="top50" (set "INSTALL_SET=top50"& goto run_installer)
if /I "%FIRST_ARG%"=="all" (set "INSTALL_SET=all"& goto run_installer)
if not "%FIRST_ARG%"=="" goto show_menu

:show_menu
cls
echo ============================================================
echo   Individual AI Agent Extensions Installer
 echo ============================================================
echo.
echo   Choose how many ranked extensions to install:
echo.
echo     [1] Top 10
echo     [2] Top 25
echo     [3] Top 50
echo     [4] All 100
echo     [Q] Quit
echo.
choice /C 1234Q /N /M "Select an option: "
if errorlevel 5 goto quit_installer
if errorlevel 4 (set "INSTALL_SET=all"& goto run_installer)
if errorlevel 3 (set "INSTALL_SET=top50"& goto run_installer)
if errorlevel 2 (set "INSTALL_SET=top25"& goto run_installer)
if errorlevel 1 (set "INSTALL_SET=top10"& goto run_installer)
goto quit_installer

:run_installer
if "%INSTALL_SET%"=="" set "INSTALL_SET=all"
echo.
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

:quit_installer
echo Installation cancelled.
exit /b 0
