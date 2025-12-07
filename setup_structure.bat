@echo off
chcp 65001
cls
echo ========================================================
echo   FlashEASuite V2: Structure Generator (By Gemini)
echo ========================================================

REM --- 1. Setup Program B: Brain (Python) ---
echo [1/2] Processing Program B (Python Brain)...
cd "02_ProgramB_Brain_Py"

REM Create Directories
if not exist "core" mkdir core
if not exist "modules" mkdir modules

REM Create Files (Root)
if not exist "main.py" type nul > main.py
if not exist "config.py" type nul > config.py
if not exist "requirements.txt" type nul > requirements.txt

REM Create Files (Core)
if not exist "core\__init__.py" type nul > core\__init__.py
if not exist "core\ingestion.py" type nul > core\ingestion.py
if not exist "core\strategy_engine.py" type nul > core\strategy_engine.py
if not exist "core\data_logger.py" type nul > core\data_logger.py
if not exist "core\zmq_server.py" type nul > core\zmq_server.py

REM Create Files (Modules - Including GA Research)
if not exist "modules\__init__.py" type nul > modules\__init__.py
if not exist "modules\regime_analyzer.py" type nul > modules\regime_analyzer.py
if not exist "modules\ga_optimizer.py" type nul > modules\ga_optimizer.py

REM Return to Root
cd ..

REM --- 2. Setup Program C: Trader (MQL5) ---
echo [2/2] Processing Program C (MQL5 Trader)...
cd "03_ProgramC_Trader_MQL"

REM Create Directories
if not exist "Config" mkdir Config
if not exist "Network" mkdir Network
if not exist "Logic" mkdir Logic
if not exist "Risk" mkdir Risk

REM Create Main EA File
if not exist "ProgramC_Trader.mq5" type nul > ProgramC_Trader.mq5

REM Create Files (Config & Network)
if not exist "Config\Settings.mqh" type nul > Config\Settings.mqh
if not exist "Network\ZmqHub.mqh" type nul > Network\ZmqHub.mqh
if not exist "Network\Protocol.mqh" type nul > Network\Protocol.mqh

REM Create Files (Logic - Policy & Strategies)
if not exist "Logic\PolicyManager.mqh" type nul > Logic\PolicyManager.mqh
if not exist "Logic\StrategyBase.mqh" type nul > Logic\StrategyBase.mqh
if not exist "Logic\Strategy_Spike.mqh" type nul > Logic\Strategy_Spike.mqh
if not exist "Logic\Strategy_Trend.mqh" type nul > Logic\Strategy_Trend.mqh
if not exist "Logic\Strategy_Standalone.mqh" type nul > Logic\Strategy_Standalone.mqh

REM Create Files (Risk)
if not exist "Risk\RiskGuardian.mqh" type nul > Risk\RiskGuardian.mqh

REM Return to Root
cd ..

echo ========================================================
echo   SUCCESS! Directory structure created.
echo   Ready for coding phase with Claude.
echo ========================================================
pause