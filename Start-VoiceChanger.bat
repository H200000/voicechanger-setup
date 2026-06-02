@echo off
REM ============================================================
REM  Relance rapide du voice changer apres installation.
REM  Cherche start_http.bat dans le dossier d'installation.
REM ============================================================
setlocal enabledelayedexpansion

set "INSTALL_DIR=C:\vcclient"
if not "%~1"=="" set "INSTALL_DIR=%~1"

if not exist "%INSTALL_DIR%" (
    echo   Dossier d'installation introuvable : %INSTALL_DIR%
    echo   Lance d'abord INSTALL.bat, ou passe le chemin en argument.
    pause
    exit /b 1
)

for /r "%INSTALL_DIR%" %%F in (start_http.bat) do (
    echo   Lancement : %%F
    cd /d "%%~dpF"
    call "%%F"
    goto :done
)

echo   start_http.bat introuvable dans %INSTALL_DIR%.
echo   Reinstalle via INSTALL.bat.
pause

:done
endlocal
