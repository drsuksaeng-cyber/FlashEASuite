# FlashEASuite V2 — Documentation Index

> **Version**: 2.1.0 (Phase P9-5) | **Updated**: 2026-03-01
> **Motto**: "Smart Server, Powerful Client"
> **Status**: Production Ready ✅

---

## เริ่มต้นที่นี่

| เป้าหมาย | ไปที่ |
|----------|------|
| ติดตั้งระบบครั้งแรก | [Installation Guide](#installation) |
| เข้าใจภาพรวมระบบ | [Section 1 — Architecture](#deep-dive-technical-analysis) |
| ดู diagram ทั้งระบบ | [Section 5 — Diagrams](#deep-dive-technical-analysis) |
| วิธีใช้งานประจำวัน | [guides/05_OperationManual.md](guides/05_OperationManual.md) |
| รู้จัก 16 strategies | [Strategy Reference](#strategy-manuals-s01--s16) |
| แก้ปัญหา | [guides/08_TroubleshootingGuide.md](guides/08_TroubleshootingGuide.md) |
| Emergency หยุดระบบ | [guides/09_EmergencyProcedures.md](guides/09_EmergencyProcedures.md) |

---

## Deep-Dive Technical Analysis

> วิเคราะห์ระบบระดับ Method/Function เป็นภาษาไทย
> เหมาะสำหรับ developer ที่ต้องการเข้าใจ code อย่างลึก

| Section | ไฟล์ | เนื้อหา | บรรทัด |
|---------|------|---------|--------|
| **S1** — System Architecture | [SECTION1_SYSTEM_ARCHITECTURE.md](SECTION1_SYSTEM_ARCHITECTURE.md) | Block diagram, ZMQ ports, DFD L0, timing, MessagePack | 364 |
| **S2** — Brain Logic | [SECTION2_BRAIN_LOGIC.md](SECTION2_BRAIN_LOGIC.md) | 6 workers, normalize_symbol, spike/grid scoring, EmergencySystem | 866 |
| **S3** — Execution & Strategy | [SECTION3_EXECUTION_STRATEGY.md](SECTION3_EXECUTION_STRATEGY.md) | ProgramC_Trader, RiskGuardian 4 gates, ExecutePolicy, feedback | 899 |
| **S4** — Philosophy | [SECTION4_PHILOSOPHY.md](SECTION4_PHILOSOPHY.md) | Smart Server/Powerful Client, adaptive design, fail-safe rationale | 681 |
| **S5** — Diagram Summary | [SECTION5_DIAGRAM_READY_SUMMARY.md](SECTION5_DIAGRAM_READY_SUMMARY.md) | 13 Mermaid diagrams, state machines, timing, message formats | 1,069 |

### ลำดับการอ่านที่แนะนำ

```
S1 (ภาพรวม) → S2 (Brain Python) → S3 (Trader MQL5) → S4 (ทำไม) → S5 (diagram)
```

---

## Installation

| ไฟล์ | เนื้อหา |
|------|---------|
| [INSTALLATION_GUIDE.md](INSTALLATION_GUIDE.md) | คู่มือติดตั้งหลัก |
| [installation/QUICK_START_THAI.md](installation/QUICK_START_THAI.md) | เริ่มต้นเร็ว (ภาษาไทย) |
| [installation/INSTALLATION_README.md](installation/INSTALLATION_README.md) | รายละเอียดการติดตั้ง |
| [installation/QUICK_FIX_THAI.md](installation/QUICK_FIX_THAI.md) | แก้ปัญหาการติดตั้ง |
| [first_day_runbook.md](first_day_runbook.md) | วันแรกที่ใช้งาน step-by-step |

---

## User Guides (guides/)

> คู่มือการใช้งานระบบสำหรับ operator

| ไฟล์ | หัวข้อ |
|------|--------|
| [guides/00_INDEX.md](guides/00_INDEX.md) | Index ของ guides ทั้งหมด |
| [guides/01_SystemOverview.md](guides/01_SystemOverview.md) | ภาพรวมระบบสำหรับผู้ใช้ |
| [guides/02_InstallationGuide.md](guides/02_InstallationGuide.md) | คู่มือติดตั้งแบบละเอียด |
| [guides/03_StrategyReference.md](guides/03_StrategyReference.md) | เอกสาร reference กลยุทธ์ทั้ง 16 |
| [guides/04_MoneyManagementReference.md](guides/04_MoneyManagementReference.md) | เอกสาร reference MM ทั้ง 19 |
| [guides/05_OperationManual.md](guides/05_OperationManual.md) | คู่มือการใช้งานประจำวัน |
| [guides/06_MonitoringGuide.md](guides/06_MonitoringGuide.md) | การ monitor ระบบ |
| [guides/07_BacktestingGuide.md](guides/07_BacktestingGuide.md) | การทดสอบย้อนหลัง |
| [guides/08_TroubleshootingGuide.md](guides/08_TroubleshootingGuide.md) | แก้ปัญหาที่พบบ่อย |
| [guides/09_EmergencyProcedures.md](guides/09_EmergencyProcedures.md) | ขั้นตอน emergency |
| [guides/10_ProductionChecklist.md](guides/10_ProductionChecklist.md) | checklist ก่อน go-live |

---

## Strategy Manuals (S01 – S16)

> คู่มือแต่ละ strategy ระดับลึก: ทฤษฎี, parameters, diagnostics

| # | ไฟล์ | ชื่อ | Category | Standalone | Best Regime |
|---|------|------|----------|------------|-------------|
| S01 | [strategies/S01_StatArb_DEEP_Manual.md](strategies/S01_StatArb_DEEP_Manual.md) | Statistical Arbitrage | HYBRID | ✅ | RANGING |
| S02 | [strategies/S02_ML_Ensemble_Manual.md](strategies/S02_ML_Ensemble_Manual.md) | ML Ensemble | HYBRID | ❌ | ALL |
| S03 | [strategies/S03_SMC_Manual.md](strategies/S03_SMC_Manual.md) | Smart Money Concepts | FULL_MQL5 | ❌ | TRENDING |
| S04 | [strategies/S04_MarketProfile_Manual.md](strategies/S04_MarketProfile_Manual.md) | Market Profile | FULL_MQL5 | ❌ | RANGING |
| S05 | [strategies/S05_SupplyDemand_Manual.md](strategies/S05_SupplyDemand_Manual.md) | Supply & Demand | FULL_MQL5 | ❌ | RANGING |
| S06 | [strategies/S06_KAMA_Manual.md](strategies/S06_KAMA_Manual.md) | KAMA Adaptive MA | FULL_MQL5 | ✅ | TRENDING |
| S07 | [strategies/S07_MeanReversion_DEEP_Manual.md](strategies/S07_MeanReversion_DEEP_Manual.md) | Mean Reversion | FULL_MQL5 | ✅ | RANGING |
| S08 | [strategies/S08_Intermarket_DEEP_Manual.md](strategies/S08_Intermarket_DEEP_Manual.md) | Intermarket Analysis | HYBRID | ❌ | TRENDING |
| S09 | [strategies/S09_SessionBreakout_DEEP_Manual.md](strategies/S09_SessionBreakout_DEEP_Manual.md) | Session Breakout | FULL_MQL5 | ❌ | VOLATILE |
| S10 | [strategies/S10_Turtle_DEEP_Manual.md](strategies/S10_Turtle_DEEP_Manual.md) | Turtle Trading | FULL_MQL5 | ✅ | TRENDING |
| S11 | [strategies/S11_Ichimoku_DEEP_Manual.md](strategies/S11_Ichimoku_DEEP_Manual.md) | Ichimoku Cloud | FULL_MQL5 | ❌ | TRENDING |
| S12 | [strategies/S12_PriceAction_DEEP_Manual.md](strategies/S12_PriceAction_DEEP_Manual.md) | Price Action | FULL_MQL5 | ❌ | TRENDING |
| S13 | [strategies/S13_FibStoch_DEEP_Manual.md](strategies/S13_FibStoch_DEEP_Manual.md) | Fibonacci + Stochastic | FULL_MQL5 | ❌ | RANGING |
| S14 | [strategies/S14_BBSqueeze_DEEP_Manual.md](strategies/S14_BBSqueeze_DEEP_Manual.md) | BB Squeeze | FULL_MQL5 | ✅ | SQUEEZE |
| S15 | [strategies/S15_Grid_DEEP_Manual.md](strategies/S15_Grid_DEEP_Manual.md) | Grid Trading | FULL_MQL5 | ✅ | RANGING |
| S16 | [strategies/S16_Spike_DEEP_Manual.md](strategies/S16_Spike_DEEP_Manual.md) | Spike Momentum | FULL_MQL5 | ✅ | VOLATILE |

**Strategy Quick Reference:**

| Standalone-only (7) | ต้องมี Brain (9) |
|--------------------|-----------------|
| S01, S06, S07, S10, S14, S15, S16 | S02, S03, S04, S05, S08, S09, S11, S12, S13 |

---

## Money Management Manuals (MM01 – MM19)

> คู่มือแต่ละ Money Manager: สูตร, use case, strategy pairing

| # | ไฟล์ | ชื่อ | ใช้กับ Strategy |
|---|------|------|----------------|
| MM01 | [money_management/MM01_FixedConservative_Manual.md](money_management/MM01_FixedConservative_Manual.md) | Fixed Conservative | S16 (default) |
| MM02 | [money_management/MM02_FixedAggressive_Manual.md](money_management/MM02_FixedAggressive_Manual.md) | Fixed Aggressive | S09, S12 |
| MM03 | [money_management/MM03_ATRBased_Manual.md](money_management/MM03_ATRBased_Manual.md) | ATR-Based | S06, S10 |
| MM04 | [money_management/MM04_KellyCriterion_Manual.md](money_management/MM04_KellyCriterion_Manual.md) | Kelly Criterion | S15 (default) |
| MM05 | [money_management/MM05_MartingaleControlled_Manual.md](money_management/MM05_MartingaleControlled_Manual.md) | Controlled Martingale | S15 (alt) |
| MM06 | [money_management/MM06_AntiMartingale_Manual.md](money_management/MM06_AntiMartingale_Manual.md) | Anti-Martingale | S01, S06 |
| MM07 | [money_management/MM07_PctVolatility_Manual.md](money_management/MM07_PctVolatility_Manual.md) | % of Volatility | S07 (default) |
| MM08 | [money_management/MM08_Pyramid_Manual.md](money_management/MM08_Pyramid_Manual.md) | Pyramiding | S10, S11 |
| MM09 | [money_management/MM09_EquityCurveRecovery_Manual.md](money_management/MM09_EquityCurveRecovery_Manual.md) | Equity Curve Recovery | S03, S08 |
| MM10 | [money_management/MM10_DrawdownBased_Manual.md](money_management/MM10_DrawdownBased_Manual.md) | Drawdown-Based | S04, S05 |
| MM11 | [money_management/MM11_SessionBased_Manual.md](money_management/MM11_SessionBased_Manual.md) | Session-Based | S09 |
| MM12 | [money_management/MM12_EquityCurveFilter_Manual.md](money_management/MM12_EquityCurveFilter_Manual.md) | Equity Curve Filter | S02, S14 |
| MM13 | [money_management/MM13_CorrelationAdjusted_Manual.md](money_management/MM13_CorrelationAdjusted_Manual.md) | Correlation Adjusted | S08, S13 |
| MM14 | [money_management/MM14_TieredRisk_Manual.md](money_management/MM14_TieredRisk_Manual.md) | Tiered Risk | S03, S12 |
| MM15 | [money_management/MM15_AdaptiveWinStreak_Manual.md](money_management/MM15_AdaptiveWinStreak_Manual.md) | Adaptive Win Streak | S01, S10 |
| MM16 | [money_management/MM16_VolatilityPercentile_Manual.md](money_management/MM16_VolatilityPercentile_Manual.md) | Volatility Percentile | S09, S16 |
| MM17 | [money_management/MM17_RegimeBased_Manual.md](money_management/MM17_RegimeBased_Manual.md) | Regime-Based | S02, S06 |
| MM18 | [money_management/MM18_PortfolioCap_Manual.md](money_management/MM18_PortfolioCap_Manual.md) | Portfolio Cap | S05, S13 |
| MM19 | [money_management/MM19_DynamicMulti_Manual.md](money_management/MM19_DynamicMulti_Manual.md) | Dynamic Multi | S02, S08 |

---

## Operations & Production

| ไฟล์ | เนื้อหา |
|------|---------|
| [PRODUCTION_READY_CHECKLIST.md](PRODUCTION_READY_CHECKLIST.md) | checklist ก่อน go-live production |
| [deployment_checklist.md](deployment_checklist.md) | deployment steps |
| [first_day_runbook.md](first_day_runbook.md) | runbook วันแรก |
| [P9_5_SYSTEM_CONTEXT_AND_FLOW.md](P9_5_SYSTEM_CONTEXT_AND_FLOW.md) | P9-5 context, flow, bug fixes CF-1 ถึง CF-7 |
| [COMPLETE_SUMMARY.md](COMPLETE_SUMMARY.md) | สรุป system ภาพรวม |

---

## Bug Fixes & Development Notes

### Fix Notes (fixes/)

| ไฟล์ | ปัญหาที่แก้ |
|------|------------|
| [fixes/FIX_NOTES.md](FIX_NOTES.md) | รายการ fixes ทั้งหมด |
| [fixes/FIX_ACCESS_VIOLATION.md](fixes/FIX_ACCESS_VIOLATION.md) | Access violation fix |
| [fixes/FIX_PROGRAMC_ERRORS.md](fixes/FIX_PROGRAMC_ERRORS.md) | ProgramC compilation errors |
| [fixes/FIX_SYNTAX_ERROR.md](fixes/FIX_SYNTAX_ERROR.md) | Syntax error fixes |
| [fixes/FIX_TARGET_FOLDER_ERROR.md](fixes/FIX_TARGET_FOLDER_ERROR.md) | Target folder error |
| [fixes/FINAL_FIX_TIMESTAMP.md](fixes/FINAL_FIX_TIMESTAMP.md) | Timestamp double fix |

### Summaries (summaries/)

| ไฟล์ | เนื้อหา |
|------|---------|
| [summaries/MASTER_SUMMARY.md](summaries/MASTER_SUMMARY.md) | Master summary ระบบ |
| [summaries/PACKAGE_SUMMARY.md](summaries/PACKAGE_SUMMARY.md) | Package contents |
| [summaries/QUICK_SUMMARY.md](summaries/QUICK_SUMMARY.md) | Quick summary |
| [summaries/QUICK_FIX_SUMMARY.md](summaries/QUICK_FIX_SUMMARY.md) | Fix summary |
| [summaries/REFACTORING_COMPLETE.md](summaries/REFACTORING_COMPLETE.md) | Refactoring log |
| [summaries/DOWNLOAD_CHECKLIST.md](summaries/DOWNLOAD_CHECKLIST.md) | Download checklist |

---

## Analysis

| ไฟล์ | เนื้อหา |
|------|---------|
| [Analysis/Deep Dive Analysi.txt](Analysis/Deep%20Dive%20Analysi.txt) | Raw analysis notes |

---

## Folder Structure

```
docs/
├── README.md                          ← คุณอยู่ที่นี่
│
├── Deep-Dive Analysis (ภาษาไทย)
│   ├── SECTION1_SYSTEM_ARCHITECTURE.md
│   ├── SECTION2_BRAIN_LOGIC.md
│   ├── SECTION3_EXECUTION_STRATEGY.md
│   ├── SECTION4_PHILOSOPHY.md
│   └── SECTION5_DIAGRAM_READY_SUMMARY.md
│
├── Root Operations
│   ├── INSTALLATION_GUIDE.md
│   ├── PRODUCTION_READY_CHECKLIST.md
│   ├── P9_5_SYSTEM_CONTEXT_AND_FLOW.md
│   ├── COMPLETE_SUMMARY.md
│   ├── deployment_checklist.md
│   ├── first_day_runbook.md
│   ├── FIX_NOTES.md
│   └── mql5.pdf
│
├── guides/                            ← User guides (01–10)
│   ├── 00_INDEX.md
│   ├── 01_SystemOverview.md
│   ├── 02_InstallationGuide.md
│   ├── 03_StrategyReference.md
│   ├── 04_MoneyManagementReference.md
│   ├── 05_OperationManual.md
│   ├── 06_MonitoringGuide.md
│   ├── 07_BacktestingGuide.md
│   ├── 08_TroubleshootingGuide.md
│   ├── 09_EmergencyProcedures.md
│   └── 10_ProductionChecklist.md
│
├── strategies/                        ← 16 Strategy manuals
│   ├── S01_StatArb_DEEP_Manual.md
│   ├── S02_ML_Ensemble_Manual.md
│   └── ... (S03–S16)
│
├── money_management/                  ← 19 MM manuals
│   ├── MM01_FixedConservative_Manual.md
│   └── ... (MM02–MM19)
│
├── fixes/                             ← Bug fix notes
│   ├── FIX_ACCESS_VIOLATION.md
│   └── ...
│
├── installation/                      ← Installation helpers
│   ├── QUICK_START_THAI.md
│   ├── INSTALLATION_README.md
│   ├── QUICK_FIX_THAI.md
│   └── tree.txt
│
├── summaries/                         ← Session summaries
│   ├── MASTER_SUMMARY.md
│   └── ...
│
├── Analysis/                          ← Raw analysis notes
├── Manual/                            ← Word documents
├── DevelopingFiles/                   ← Working/development files
└── archive/                           ← Archived / old files
```

---

## System Quick Reference

### ZMQ Ports

| Port | Pattern | Direction | ข้อมูล |
|------|---------|-----------|--------|
| **7777** | PUB/SUB | FeederEA → Brain | Tick Array[7] |
| **7778** | PUB/SUB | Brain → Trader | Policy Array[11] |
| **7779** | PUSH/PULL | Trader → Brain | Feedback Array[12] |

### Emergency Thresholds

| Condition | ค่า | Level |
|-----------|-----|-------|
| Max Drawdown | 20% | HALT |
| Daily Loss | 5% | HALT |
| Consecutive Losses | 5 trades | PAUSE 60min |
| Heartbeat Timeout | 30s | → Standalone |
| CPU/RAM | 90% | WARNING |

### Key Files (Source Code)

| ไฟล์ | บทบาท |
|------|------|
| `02_Brain/main.py` | Python Brain entry point |
| `02_Brain/core/strategy/engine.py` | Spike/Grid scoring + policy |
| `03_Trader/ProgramC_Trader.mq5` | MQL5 trade executor |
| `Include/Logic/StrategyConstants.mqh` | 16 strategies table |
| `Include/Risk/RiskGuardian.mqh` | 4-gate risk validation |

---

*FlashEASuite V2 — Author: Dr. Suksaeng Kukanok | Phase P9-5 Complete*
