@echo off
REM ============================================================
REM  Construit MT5TradingBot.exe (dossier dist\)
REM  Necessite d'avoir lance run.bat au moins une fois.
REM ============================================================
setlocal
cd /d "%~dp0"

set PYEXE=.venv\Scripts\python.exe
if not exist "%PYEXE%" (
    echo Lancez d'abord run.bat pour creer l'environnement.
    pause
    exit /b 1
)

"%PYEXE%" -m pip install --upgrade pyinstaller --quiet

REM --onedir demarre plus vite et evite les faux positifs antivirus lies au
REM decompactage de --onefile. Ajoutez --onefile si vous preferez un exe unique.
"%PYEXE%" -m PyInstaller ^
    --noconfirm ^
    --clean ^
    --onedir ^
    --windowed ^
    --name MT5TradingBot ^
    --hidden-import MetaTrader5 ^
    --collect-all PySide6 ^
    app\__main__.py

if errorlevel 1 (
    echo La construction a echoue.
    pause
    exit /b 1
)

echo.
echo Termine : dist\MT5TradingBot\MT5TradingBot.exe
pause
endlocal
