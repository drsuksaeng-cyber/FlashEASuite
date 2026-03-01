# MM15 — Adaptive Win Streak
## FlashEASuite V2 | Money Management Deep Dive Manual
### Generated: 2026-02-27 | Phase P9-5

---

## 1. Overview

| Field | Value |
|-------|-------|
| **MM ID** | MM15 |
| **Name** | Adaptive Win Streak |
| **MQL5 Class** | `CMM15_AdaptiveWinStreak` |
| **Magic Prefix** | MAGIC_MM15 |
| **Version** | 6.00 |
| **Standalone Ready** | Yes |

### สรุปแนวคิด (Thai)

MM15 เพิ่ม Lot Size เมื่อมี **Win Streak** ต่อเนื่อง แต่ต้องผ่าน Minimum Streak ก่อน (default 3 wins) จึงจะเริ่ม boost ต่างจาก MM06 (Anti-Martingale) ที่เพิ่มตั้งแต่ Win แรก MM15 ต้องการ streak ขั้นต่ำก่อน เมื่อถึง min streak → เพิ่ม +10% ต่อ extra win เกิน streak ขั้นต่ำ เมื่อแพ้ครั้งเดียว → Reset ทันที

---

## 2. Core Theory

### 2.1 Win Streak Tracking

```
m_consecutive_wins — tracks current win streak
m_min_streak       — minimum wins required before boosting (default 3)

UpdateTradeResult(profit):
  if profit > 0:
    m_consecutive_wins++
  else:
    m_consecutive_wins = 0  (immediate reset on any loss)
```

### 2.2 Lot Boost Formula

```
If m_consecutive_wins < m_min_streak:
  → Use base lot (no boost)

If m_consecutive_wins >= m_min_streak:
  extra_wins = m_consecutive_wins - m_min_streak
  boost = 1.0 + (extra_wins × m_boost_per_win)

  Example (m_boost_per_win = 0.10):
    Win streak = 3 (exactly min): extra_wins=0 → boost=1.0 (still base)
    Win streak = 4:               extra_wins=1 → boost=1.10 (+10%)
    Win streak = 5:               extra_wins=2 → boost=1.20 (+20%)
    Win streak = 6:               extra_wins=3 → boost=1.30 (+30%)
    Win streak = 7+:              capped at m_max_boost (default 2.0)
```

### 2.3 Difference from MM06 (Anti-Martingale)

```
MM06 Anti-Martingale:
  Boosts from WIN #1 (+10% per win, no minimum)
  More aggressive — starts boosting immediately

MM15 Adaptive Win Streak:
  Requires MIN_STREAK consecutive wins before any boost
  Conservative — needs confirmed streak before scaling
  Logic: 1-2 lucky wins might be noise; 3+ wins suggest real edge
```

### 2.4 Final Lot Calculation

```
base_lot = (balance × base_risk_pct / 100) / (sl_pips × pip_value)
final_lot = base_lot × min(boost, m_max_boost)

Boost is applied multiplicatively on base_lot.
Reset: single loss → boost = 1.0 immediately next trade
```

---

## 3. Parameter Reference

### 3.1 MQL5 Input Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `AWS_BaseRisk` | 1.0 | Base risk % per trade |
| `AWS_MinStreak` | 3 | Wins required before boosting starts |
| `AWS_BoostPerWin` | 0.10 | Lot boost per extra win above min streak |
| `AWS_MaxBoost` | 2.0 | Hard cap on total boost multiplier |

### 3.2 CONFIG_PUSH Keys (Server Mode)

| Key | Type | Default | Maps To |
|-----|------|---------|---------|
| `MM15_BASE_RISK` | float | 1.0 | `m_base_risk_pct` |
| `MM15_MIN_STREAK` | int | 3 | `m_min_streak` |
| `MM15_BOOST_PER_WIN` | float | 0.10 | `m_boost_per_win` |
| `MM15_MAX_BOOST` | float | 2.0 | `m_max_boost` |

---

## 4. Performance Characteristics

| Aspect | Detail |
|--------|--------|
| **Best Condition** | Trending market with extended win streaks |
| **Worst Condition** | Alternating wins/losses — never reaches min_streak |
| **Conservative Default** | Min streak 3 → only boosts after 3+ consecutive wins |
| **Max Risk** | base_risk × 2.0 (100% increase at max boost) |
| **Reset Speed** | Instant on first loss |
| **Standalone Ready** | Yes |

---

## 5. Files Reference

| File | Role |
|------|------|
| `Include/Logic/MM/MM15_AdaptiveWinStreak.mqh` | `CMM15_AdaptiveWinStreak` full implementation |

---

## 6. Quick Diagnostics

```mql5
mm15.GetDiagnostic();
// Output:
//   [MM15] WinStreak | ConsecWins=5 (min=3) | ExtraWins=2 | Boost=1.20x
//   [MM15] BaseLot=0.10 → BoostedLot=0.12
//   [MM15] MaxBoost=2.0x | Status=BOOSTING

int streak = mm15.GetCurrentStreak();
double boost = mm15.GetCurrentBoost();
```

### Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Boost never activates | Strategy rarely produces 3 consecutive wins | Lower `AWS_MinStreak` to 2 |
| Boost too aggressive | `AWS_MaxBoost` = 2.0 too high | Reduce to 1.5 |
| Lots spike too fast | `AWS_BoostPerWin` = 0.10 × many wins | Lower to 0.05 per win |
| Resets too easily | Any loss kills streak | Expected behavior — one loss = full reset |

---

*MM15 Manual — FlashEASuite V2 | Phase P9-5 | Generated 2026-02-27*
