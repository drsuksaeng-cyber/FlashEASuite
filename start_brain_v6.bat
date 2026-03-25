@echo off
title FlashEASuite V2 - Brain V6 (Full)
echo =============================================
echo  FlashEASuite V2 - Brain V6 Full Integration
echo  Deploy: S01+S06+S07+S10+S14+S16
echo  Symbols: USDJPY + XAUUSD + GBPUSD
echo  Port: 7778 (PUB) + 7779 (Feedback)
echo  Regime: Auto-detect from tick data
echo =============================================
echo.

REM --- Auto-detect Python ---
if defined FLASH_PYTHON (
    set PYTHON=%FLASH_PYTHON%
) else (
    where python >nul 2>&1
    if not errorlevel 1 (
        set PYTHON=python
    ) else (
        echo ERROR: Python not found! Set FLASH_PYTHON env var or add python to PATH.
        pause
        exit /b 1
    )
)
set BRAIN_DIR=%~dp002_Brain
set SCRIPT=main_v6.py

echo [1/3] Checking Python...
"%PYTHON%" --version
if errorlevel 1 (
    echo ERROR: Python not found at %PYTHON%
    pause
    exit /b 1
)

echo.
echo [2/3] Checking ZMQ port 7778...
netstat -ano | findstr ":7778" >nul 2>&1
if not errorlevel 1 (
    echo WARNING: Port 7778 already in use!
    echo Close existing process first, or Brain will fail to bind.
    echo.
    netstat -ano | findstr ":7778"
    echo.
    choice /M "Continue anyway?"
    if errorlevel 2 exit /b 1
)

echo.
echo [3/3] Starting Brain V6 Full...
echo   Mode: --no-feeder (standalone regime detect)
echo   Suffix: .tp
echo   Ctrl+C to stop
echo.

cd /d "%BRAIN_DIR%"
"%PYTHON%" "%SCRIPT%" --no-feeder

echo.
echo Brain V6 stopped.
pause
