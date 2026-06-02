@echo off
REM ============================================================
REM  Voice Changer Setup - lanceur d'installation (double-clic)
REM  Relance install.ps1 avec bypass de l'ExecutionPolicy.
REM  L'elevation administrateur est geree par le script PowerShell.
REM ============================================================
setlocal
cd /d "%~dp0"

echo.
echo   Lancement de l'installeur Voice Changer...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo   L'installeur a renvoye une erreur ^(code %ERRORLEVEL%^).
    echo   Lis les messages ci-dessus.
    pause
)
endlocal
