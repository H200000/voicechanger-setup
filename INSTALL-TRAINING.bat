@echo off
REM ============================================================
REM  Applio - lanceur d'installation entrainement de voix (double-clic)
REM  IMPORTANT : NE PAS lancer en administrateur. Applio le refuse.
REM  Ce .bat ne demande donc PAS l'elevation (contrairement a INSTALL.bat).
REM ============================================================
setlocal
cd /d "%~dp0"

echo.
echo   Lancement de l'installeur Applio (entrainement de voix)...
echo   (Applio s'installe en utilisateur normal, pas en administrateur)
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-applio.ps1" %*

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo   L'installeur a renvoye une erreur ^(code %ERRORLEVEL%^).
    echo   Lis les messages ci-dessus.
    pause
)
endlocal
