@echo off
REM ============================================================
REM  MT5 Trading Bot - lancement sous Windows 10 / 11
REM  Cree l'environnement virtuel au premier demarrage, puis lance l'app.
REM ============================================================
setlocal
cd /d "%~dp0"

set VENV=.venv
set PYEXE=%VENV%\Scripts\python.exe

if not exist "%PYEXE%" (
    echo [1/3] Creation de l'environnement Python...
    py -3 -m venv "%VENV%" 2>nul
    if not exist "%PYEXE%" python -m venv "%VENV%"
    if not exist "%PYEXE%" (
        echo.
        echo ERREUR : Python 3.10 ou superieur est introuvable.
        echo Installez-le depuis https://www.python.org/downloads/windows/
        echo en cochant "Add python.exe to PATH", puis relancez ce fichier.
        echo.
        pause
        exit /b 1
    )
    set FRESH=1
)

if defined FRESH (
    echo [2/3] Installation des dependances ^(quelques minutes la premiere fois^)...
    "%PYEXE%" -m pip install --upgrade pip --quiet
    "%PYEXE%" -m pip install -r requirements.txt
    if errorlevel 1 (
        echo.
        echo ERREUR : l'installation des dependances a echoue.
        pause
        exit /b 1
    )
    echo ok> "%VENV%\.deps-ok"
)

if not exist "%VENV%\.deps-ok" (
    echo [2/3] Verification des dependances...
    "%PYEXE%" -m pip install -r requirements.txt --quiet
    echo ok> "%VENV%\.deps-ok"
)

echo [3/3] Demarrage de l'application...
"%PYEXE%" -m app
if errorlevel 1 (
    echo.
    echo L'application s'est terminee avec une erreur.
    echo Consultez le journal : %%APPDATA%%\MT5TradingBot\logs\app.log
    pause
)
endlocal
