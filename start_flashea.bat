@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion

:: ============================================================
:: FlashEASuite V2 — Production Startup Script
:: Version: 1.0 (P9-4)
:: Author: Dr. Suksaeng Kukanok
:: Date: 2026-02-26
::
:: Usage:
::   start_flashea.bat              — Start all (Brain + verify MT5)
::   start_flashea.bat brain        — Start Python Brain only
::   start_flashea.bat status       — Show status dashboard
::   start_flashea.bat stop         — Stop Python Brain gracefully
::   start_flashea.bat doctor       — Run diagnostic checks
::
:: Save: FlashEASuite_V2/start_flashea.bat (root folder)
:: ============================================================

title FlashEASuite V2 — Production Startup

:: ─────────────────────────────────────────────
:: CONFIGURATION — แก้ path ให้ตรงกับเครื่องจริง
:: ─────────────────────────────────────────────
set "FLASHEA_ROOT=%~dp0"
set "BRAIN_DIR=%FLASHEA_ROOT%02_Brain"
set "BRAIN_ENTRY=%BRAIN_DIR%\main.py"
set "HEALTH_MON=%FLASHEA_ROOT%tools\health_monitor.py"
set "LOG_DIR=%FLASHEA_ROOT%logs"
set "PYTHON_EXE=python"
set "MT5_PROCESS=terminal64.exe"

:: ZMQ Ports
set "PORT_FEEDER=7777"
set "PORT_POLICY=7778"
set "PORT_FEEDBACK=7779"

:: PID file for Brain process
set "BRAIN_PID_FILE=%LOG_DIR%\brain.pid"

:: ─────────────────────────────────────────────
:: Create log directory
:: ─────────────────────────────────────────────
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

:: ─────────────────────────────────────────────
:: Parse command
:: ─────────────────────────────────────────────
set "CMD=%~1"
if "%CMD%"=="" set "CMD=start"

if /i "%CMD%"=="start"  goto :CMD_START
if /i "%CMD%"=="brain"  goto :CMD_BRAIN
if /i "%CMD%"=="status" goto :CMD_STATUS
if /i "%CMD%"=="stop"   goto :CMD_STOP
if /i "%CMD%"=="doctor" goto :CMD_DOCTOR
if /i "%CMD%"=="help"   goto :CMD_HELP

echo [ERROR] Unknown command: %CMD%
goto :CMD_HELP

:: ============================================================
:: COMMAND: START (full startup)
:: ============================================================
:CMD_START
echo.
echo ╔══════════════════════════════════════════════════════╗
echo ║   FlashEASuite V2 — Production Startup              ║
echo ║   %DATE% %TIME:~0,8%                                ║
echo ╚══════════════════════════════════════════════════════╝
echo.

:: Step 1: Preflight checks
call :CHECK_PYTHON
if errorlevel 1 (
    echo [FATAL] Python not found. Install Python 3.8+ and add to PATH.
    goto :EOF
)

call :CHECK_MT5
if errorlevel 1 (
    echo [WARN] MT5 terminal not running.
    echo        Please start MetaTrader 5 first, then attach FeederEA and Trader EA.
    echo        Brain will start anyway and wait for connections.
    echo.
)

call :CHECK_PORTS
if errorlevel 1 (
    echo [WARN] Some ports may be in use. Check output above.
    echo.
)

:: Step 2: Check dependencies
echo [2/5] Checking Python dependencies...
"%PYTHON_EXE%" -c "import zmq, msgpack; print('  pyzmq:', zmq.__version__, '| msgpack:', msgpack.version)" 2>nul
if errorlevel 1 (
    echo [ERROR] Missing dependencies. Run:
    echo         pip install pyzmq msgpack
    goto :EOF
)
echo   Dependencies OK
echo.

:: Step 3: Start Brain
echo [3/5] Starting Python Brain...
call :START_BRAIN
echo.

:: Step 4: Wait for Brain initialization
echo [4/5] Waiting for Brain initialization (3 seconds)...
timeout /t 3 /nobreak >nul

:: Step 5: Show status
echo [5/5] System status:
call :SHOW_STATUS
echo.
echo ════════════════════════════════════════════════════════
echo   Brain is running. Next steps:
echo   1. Open MetaTrader 5
echo   2. Attach FeederEA to chart (port 7777)
echo   3. Attach ProgramC_Trader to chart (port 7778/7779)
echo   4. Monitor: start_flashea.bat status
echo ════════════════════════════════════════════════════════
echo.
goto :EOF

:: ============================================================
:: COMMAND: BRAIN (start Brain only)
:: ============================================================
:CMD_BRAIN
echo [INFO] Starting Python Brain only...
call :CHECK_PYTHON
if errorlevel 1 goto :EOF
call :START_BRAIN
goto :EOF

:: ============================================================
:: COMMAND: STATUS
:: ============================================================
:CMD_STATUS
echo.
echo ╔══════════════════════════════════════════════════════╗
echo ║   FlashEASuite V2 — Status Dashboard                ║
echo ║   %DATE% %TIME:~0,8%                                ║
echo ╚══════════════════════════════════════════════════════╝
echo.
call :SHOW_STATUS
goto :EOF

:: ============================================================
:: COMMAND: STOP
:: ============================================================
:CMD_STOP
echo.
echo [INFO] Stopping Python Brain...

:: Find and kill Brain process
for /f "tokens=2" %%p in ('tasklist /fi "WINDOWTITLE eq FlashEA Brain*" /fo csv /nh 2^>nul ^| find "python"') do (
    set "PID=%%~p"
)

:: Also search by main.py
for /f "tokens=2 delims=," %%p in ('wmic process where "commandline like '%%main.py%%' and name='python.exe'" get processid /format:csv 2^>nul ^| find ","') do (
    echo [INFO] Sending Ctrl+C to Brain PID: %%p
    taskkill /pid %%p /f >nul 2>&1
    echo [OK] Brain process terminated.
    goto :STOP_DONE
)

echo [WARN] Brain process not found. It may not be running.

:STOP_DONE
if exist "%BRAIN_PID_FILE%" del "%BRAIN_PID_FILE%" >nul 2>&1
echo.
goto :EOF

:: ============================================================
:: COMMAND: DOCTOR (diagnostic)
:: ============================================================
:CMD_DOCTOR
echo.
echo ╔══════════════════════════════════════════════════════╗
echo ║   FlashEASuite V2 — System Doctor                   ║
echo ╚══════════════════════════════════════════════════════╝
echo.

echo [1] Python...
call :CHECK_PYTHON
echo.

echo [2] MetaTrader 5...
call :CHECK_MT5
echo.

echo [3] Ports...
call :CHECK_PORTS
echo.

echo [4] Python Dependencies...
"%PYTHON_EXE%" -c "import zmq; print('  pyzmq:    OK (' + zmq.__version__ + ')')" 2>nul || echo   pyzmq:    MISSING
"%PYTHON_EXE%" -c "import msgpack; print('  msgpack:  OK (' + str(msgpack.version) + ')')" 2>nul || echo   msgpack:  MISSING
"%PYTHON_EXE%" -c "import numpy; print('  numpy:    OK (' + numpy.__version__ + ')')" 2>nul || echo   numpy:    MISSING (optional)
"%PYTHON_EXE%" -c "import pandas; print('  pandas:   OK (' + pandas.__version__ + ')')" 2>nul || echo   pandas:   MISSING (optional)
echo.

echo [5] File Structure...
if exist "%BRAIN_ENTRY%" (echo   main.py:           FOUND) else (echo   main.py:           MISSING!)
if exist "%BRAIN_DIR%\core\ingestion.py" (echo   ingestion.py:      FOUND) else (echo   ingestion.py:      MISSING!)
if exist "%BRAIN_DIR%\core\execution_listener.py" (echo   execution_listener: FOUND) else (echo   execution_listener: MISSING!)
if exist "%FLASHEA_ROOT%01_Feeder\Src\FeederEA.mq5" (echo   FeederEA.mq5:      FOUND) else (echo   FeederEA.mq5:      MISSING!)
if exist "%FLASHEA_ROOT%03_Trader\ProgramC_Trader.mq5" (echo   ProgramC_Trader:   FOUND) else (echo   ProgramC_Trader:   MISSING!)
echo.

echo [6] Log Directory...
if exist "%LOG_DIR%" (echo   %LOG_DIR% EXISTS) else (echo   %LOG_DIR% MISSING - will create)
echo.

echo ════════════════════════════════════════════════════════
echo   Doctor check complete. Fix any issues marked MISSING.
echo ════════════════════════════════════════════════════════
goto :EOF

:: ============================================================
:: COMMAND: HELP
:: ============================================================
:CMD_HELP
echo.
echo FlashEASuite V2 — Startup Script
echo.
echo Usage: start_flashea.bat [command]
echo.
echo Commands:
echo   start    Start all components (default)
echo   brain    Start Python Brain only
echo   status   Show status dashboard
echo   stop     Stop Python Brain gracefully
echo   doctor   Run diagnostic checks
echo   help     Show this message
echo.
goto :EOF

:: ============================================================
:: HELPER FUNCTIONS
:: ============================================================

:CHECK_PYTHON
"%PYTHON_EXE%" --version >nul 2>&1
if errorlevel 1 (
    echo   [FAIL] Python not found in PATH
    exit /b 1
)
for /f "tokens=*" %%v in ('"%PYTHON_EXE%" --version 2^>^&1') do echo   [OK] %%v
exit /b 0

:CHECK_MT5
tasklist /fi "IMAGENAME eq %MT5_PROCESS%" 2>nul | find /i "%MT5_PROCESS%" >nul
if errorlevel 1 (
    echo   [WARN] %MT5_PROCESS% not running
    exit /b 1
)
echo   [OK] MetaTrader 5 is running
exit /b 0

:CHECK_PORTS
set "PORT_ISSUE=0"
for %%P in (%PORT_FEEDER% %PORT_POLICY% %PORT_FEEDBACK%) do (
    netstat -an 2>nul | find "%%P" | find "LISTENING" >nul 2>&1
    if not errorlevel 1 (
        echo   [WARN] Port %%P already in use
        set "PORT_ISSUE=1"
    ) else (
        echo   [OK] Port %%P available
    )
)
if "%PORT_ISSUE%"=="1" exit /b 1
exit /b 0

:START_BRAIN
pushd "%BRAIN_DIR%"
start "FlashEA Brain" /min "%PYTHON_EXE%" main.py
echo   [OK] Brain started in background (minimized window)
echo   [OK] Log: check Brain console window

:: Save approximate PID (for stop command)
for /f "tokens=2" %%p in ('tasklist /fi "WINDOWTITLE eq FlashEA Brain" /fo csv /nh 2^>nul') do (
    echo %%~p > "%BRAIN_PID_FILE%"
)

popd
exit /b 0

:SHOW_STATUS
:: Brain
tasklist 2>nul | find /i "python" >nul
if not errorlevel 1 (
    echo   Python Brain:     [RUNNING]
) else (
    echo   Python Brain:     [STOPPED]
)

:: MT5
tasklist /fi "IMAGENAME eq %MT5_PROCESS%" 2>nul | find /i "%MT5_PROCESS%" >nul
if not errorlevel 1 (
    echo   MetaTrader 5:     [RUNNING]
) else (
    echo   MetaTrader 5:     [STOPPED]
)

:: Ports
for %%P in (%PORT_FEEDER% %PORT_POLICY% %PORT_FEEDBACK%) do (
    netstat -an 2>nul | find "%%P" | find "LISTENING" >nul 2>&1
    if not errorlevel 1 (
        echo   Port %%P:          [LISTENING]
    ) else (
        echo   Port %%P:          [FREE]
    )
)
exit /b 0
