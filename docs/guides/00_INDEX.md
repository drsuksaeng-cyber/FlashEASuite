# FlashEASuite V2 — Documentation Index

> **Version:** V6 (P9-5 Production) | **Date:** 2026-03-01
> **Author:** Dr. Suksaeng Kukanok | **Motto:** *"Smart Server, Powerful Client"*

---

## System Status

| Item | Value |
|------|-------|
| Current Phase | P9-5 — Production Ready |
| Test Results | 162/163 PASS (1 WARN — InfluxDB optional) |
| Strategies | 16 (MQL5) |
| MM Methods | 19 (MQL5) |
| ZMQ Ports | 7777 / 7778 / 7779 |
| Protocol | MessagePack binary |

---

## Guide Library

### [01 — System Overview](01_SystemOverview.md)
**ภาพรวมระบบทั้งหมด**

Full architecture breakdown of the 3-component system. Covers ZMQ communication ports, MessagePack protocol types, tick-to-trade data flow, AI Council formula, ML stack (RF + LSTM + XGBoost + KMeans + HMM), Online vs Standalone modes, and the complete key file map.

> **Read this first** — everything else builds on this foundation.

---

### [02 — Installation Guide](02_InstallationGuide.md)
**คู่มือการติดตั้ง**

Step-by-step installation from scratch. Covers software prerequisites, Python dependency install, project folder structure, ZMQ DLL placement, MT5 settings (algo trading, DLL imports), EA compile instructions (FeederEA + ProgramC_Trader), pre-live validation tool, and optional Windows Task Scheduler auto-start.

> **Use when:** Setting up on a new machine or fresh MT5 terminal.

---

### [03 — Strategy Reference](03_StrategyReference.md)
**คู่มืออ้างอิง 16 กลยุทธ์**

Complete reference for all 16 trading strategies. Each entry includes: theory, MQL5 category, Standalone capability, best market regime, entry/exit conditions, key parameters, and Thai-language concept summary (สรุปแนวคิด).

| Standalone Strategies | Server-Required Strategies |
|-----------------------|---------------------------|
| S01, S06, S07, S10, S14, S15, S16 | S02, S03, S04, S05, S08, S09, S11, S12, S13 |

> **Use when:** Understanding what each strategy does, selecting strategies for a regime, or debugging unexpected trade behavior.

---

### [04 — Money Management Reference](04_MoneyManagementReference.md)
**คู่มืออ้างอิง 19 วิธีบริหารความเสี่ยง**

Complete reference for all 19 MM methods. Each entry includes: formula, risk level, best use case, parameters, and Thai-language concept summary. Includes selection guides by experience level, strategy type, and Brain-recommended defaults per regime.

| Conservative | Moderate | Aggressive |
|-------------|----------|------------|
| MM01, MM09, MM12, MM18 | MM03, MM04, MM06, MM07, MM11, MM13, MM14, MM16, MM17 | MM02, MM05, MM08, MM15 |
| **Best overall (production):** MM19 Dynamic Multi |

> **Use when:** Choosing a MM method, understanding lot size behavior, or tuning risk parameters.

---

### [05 — Operation Manual](05_OperationManual.md)
**คู่มือดำเนินงานประจำวัน**

The day-to-day operations handbook. Covers the exact startup sequence (MT5 → Brain → FeederEA → Trader → Monitor), shutdown levels (L1–L4), pre-live go timeline, daily/weekly/monthly maintenance routines, trading session times, Do's and Don'ts, and a laminated-style quick reference card.

> **Use when:** Starting the system each day, performing maintenance, or training someone new.

---

### [06 — Monitoring Guide](06_MonitoringGuide.md)
**คู่มือการตรวจสอบระบบ**

Everything about watching the live system. Covers the Brain Dashboard (all panels explained), Health Monitor output and color codes, Validation Tool flags and interpretation, MT5 Experts/Journal/Trade tabs, InfluxDB buckets, all log file formats with example entries, automated alert thresholds, and monitoring checklists for before/during/after sessions.

> **Use when:** Checking if the system is healthy, investigating unusual behavior, or reviewing daily performance.

---

### [07 — Backtesting Guide](07_BacktestingGuide.md)
**คู่มือการทดสอบย้อนหลัง**

Complete guide to testing strategies before going live. Covers MT5 Strategy Tester setup, all Tester EA files in `Tester/`, how to read Report and Graph tabs, performance benchmarks per strategy, best practices (test period, walk-forward validation, Monte Carlo), optimization pitfalls, strategy-specific backtest settings, and the Backtest → Demo → Live progression path.

> **Use when:** Testing a strategy, validating parameter changes, or evaluating optimization results.

---

### [08 — Troubleshooting Guide](08_TroubleshootingGuide.md)
**คู่มือการแก้ไขปัญหา**

Indexed guide to 18 common problems, each with diagnosis steps and fix table. Includes: Brain won't start, FeederEA not broadcasting, Trader not receiving policies, port conflicts, compile errors, DLL not found, memory leaks, high CPU, wrong suffix, Standalone not activating, InfluxDB issues, validation failures, feedback loop broken, wrong lot size, and RiskGuardian blocking trades.

> **Use when:** Something is wrong and you need to find the cause fast.

---

### [09 — Emergency Procedures](09_EmergencyProcedures.md)
**ขั้นตอนฉุกเฉิน**

Playbook for every emergency scenario. Covers the 4 shutdown levels (L1: AutoTrading OFF → L4: Force Kill), and 8 named scenarios: Drawdown Exceeds Threshold, Flash Crash/News Spike, Brain Crash, MT5 Crash, Broker Disconnection, Server Overload, Margin Call Warning, and Rogue Trade. Includes an emergency decision tree and post-emergency checklist.

> **Read and practice before going live. Practice each level on Demo.**

---

### [10 — Production Checklist](10_ProductionChecklist.md)
**รายการตรวจสอบก่อน Go-Live**

The gate before going live. 12 sections, 80+ checkbox items covering: Python Brain, FeederEA, ProgramC_Trader, MT5 global settings, data flow verification, trade execution, feedback loop, risk management, standalone mode, monitoring, backtest validation, and final pre-live checks. Includes production rules commitment, pre-live timeline, and space to record test results.

> **Complete every item before switching from Demo to Live.**

---

## Reading Paths

### New User (first time setup)
```
01 System Overview → 02 Installation → 07 Backtesting → 05 Operation Manual → 10 Production Checklist
```

### Daily Operator
```
05 Operation Manual (startup) → 06 Monitoring → 09 Emergency (reference)
```

### Strategy Researcher
```
01 System Overview → 03 Strategy Reference → 04 MM Reference → 07 Backtesting
```

### Something Went Wrong
```
08 Troubleshooting → 09 Emergency Procedures
```

### Going Live for the First Time
```
07 Backtesting → 06 Monitoring → 09 Emergency → 10 Production Checklist → 05 Operation Manual
```

---

## Key Files Quick Reference

| File | Purpose |
|------|---------|
| `start_flashea.bat` | Start / stop / status / doctor |
| `02_Brain/main.py` | Python Brain entry point |
| `03_Trader/ProgramC_Trader.mq5` | Main Trader EA |
| `01_Feeder/Src/FeederEA.mq5` | Tick data feeder EA |
| `tools/health_monitor.py` | Real-time health checker |
| `tools/validate_live_readiness.py` | Pre-live validator |
| `02_Brain/dashboard.py` | Brain dashboard (5s refresh) |
| `Include/Risk/RiskGuardian.mqh` | Daily loss + max DD limits |
| `Include/Logic/StrategyConstants.mqh` | Strategy enums + magic numbers |
| `02_Brain/config.py` | Brain configuration |

## ZMQ Ports

| Port | Flow | Data |
|------|------|------|
| **7777** | FeederEA → Brain | TICK / OHLC / INDICATOR |
| **7778** | Brain → Trader | CONFIG_PUSH (strategy + MM config) |
| **7779** | Trader → Brain | TRADE_REPORT (feedback loop) |

---

*FlashEASuite V2 Documentation Index — V6 P9-5 Production | 2026-03-01*
