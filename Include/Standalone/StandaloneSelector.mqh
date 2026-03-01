//+------------------------------------------------------------------+
//| StandaloneSelector.mqh                                           |
//| FlashEASuite V2 — P6-2: CStandaloneSelector                    |
//+------------------------------------------------------------------+
//| Orchestrates standalone trading when Python server is offline    |
//| Flow per tick:                                                   |
//|   DetectRegime() → SelectStrategies() → CalculateConfidence()   |
//|   → Execute() via StrategyManager_V6                            |
//|                                                                  |
//| Regime → Active Strategies:                                      |
//|   TRENDING  → KAMA (S06) + Turtle (S10) + BBSqueeze (S14)      |
//|   RANGING   → Grid (S15) + StatArb (S01) + MeanRev (S07)       |
//|   VOLATILE  → Spike (S16) + BBSqueeze (S14)                    |
//|   SQUEEZE   → BBSqueeze (S14) + Turtle (S10)                   |
//|   UNKNOWN   → Grid (S15) + MeanRev (S07)  [conservative]       |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property strict

#ifndef STANDALONE_SELECTOR_MQH
#define STANDALONE_SELECTOR_MQH

#include "SimpleRegime.mqh"
#include "StandaloneConfig.mqh"
#include "../Logic/IStrategy.mqh"
#include "../Logic/StrategyConstants.mqh"
#include "../Logic/StrategyManager_V6.mqh"

//+------------------------------------------------------------------+
//| CStandaloneSelector: Main P6-2 class                             |
//| ใช้ direct members — ไม่ใช้ pointer/new/delete (lessons learned) |
//+------------------------------------------------------------------+
class CStandaloneSelector
{
private:
    // ── Core components (direct objects per lessons learned) ─────────
    CSimpleRegime       m_regime_det;      // Regime detector
    CStandaloneConfig   m_cfg_mgr;         // Config file manager
    SStandaloneConfig   m_cfg;             // Active config values

    // ── External references (pointers supplied by caller) ───────────
    CStrategyManager_V6* m_strategy_mgr;  // StrategyManager_V6 owned by ProgramC_Trader

    // ── State ────────────────────────────────────────────────────────
    string              m_symbol;
    ENUM_TIMEFRAMES     m_tf;
    string              m_config_file;    // filename in MQL5/Files/

    ENUM_MARKET_REGIME  m_current_regime;
    ENUM_MARKET_REGIME  m_prev_regime;
    double              m_confidence;
    bool                m_initialized;

    // Active strategy IDs for current regime (max 4)
    ENUM_STRATEGY_ID    m_active_ids[4];
    int                 m_active_count;

    // Per-tick counters
    int                 m_regime_change_count;
    datetime            m_last_regime_change_time;
    int                 m_tick_count;

    // Cooldown after regime change (bars to wait before re-selecting)
    int                 m_cooldown_bars;
    int                 m_cooldown_bars_left;

public:
    //+------------------------------------------------------------------+
    //| Init: Load config, init detector, apply initial strategy set     |
    //| @param strategy_mgr  Pointer to StrategyManager_V6 in Trader     |
    //| @param symbol        Trading symbol                              |
    //| @param tf            Primary timeframe                           |
    //| @param config_file   INI file in MQL5/Files/                     |
    //| @return true on success                                          |
    //+------------------------------------------------------------------+
    bool Init(CStrategyManager_V6* strategy_mgr,
              string symbol,
              ENUM_TIMEFRAMES tf,
              string config_file = "standalone_selector.dat")
    {
        if(strategy_mgr == NULL)
        {
            Print("[StandaloneSelector] ❌ strategy_mgr is NULL");
            return false;
        }

        m_strategy_mgr    = strategy_mgr;
        m_symbol          = symbol;
        m_tf              = tf;
        m_config_file     = config_file;
        m_current_regime  = REGIME_UNKNOWN;
        m_prev_regime     = REGIME_UNKNOWN;
        m_confidence      = 0.0;
        m_active_count    = 0;
        m_regime_change_count    = 0;
        m_last_regime_change_time= 0;
        m_tick_count      = 0;
        m_cooldown_bars_left = 0;
        m_cooldown_bars      = 3;  // bars to wait after regime change
        m_initialized     = false;
        ArrayInitialize(m_active_ids, S01_STAT_ARB);

        // 1. Load config file (or use defaults)
        if(!m_cfg_mgr.Load(m_config_file, m_cfg))
        {
            m_cfg_mgr.SetDefaults(m_cfg);
            PrintFormat("[StandaloneSelector] No config file — using defaults | conf_min=%.2f risk=%.2f",
                        m_cfg.confidence_min, m_cfg.risk_multiplier);
        }

        // 2. Init regime detector with loaded thresholds
        if(!m_regime_det.Setup(m_symbol, m_tf,
                               m_cfg.adx_trend_enter,
                               m_cfg.adx_trend_exit,
                               m_cfg.adx_volatile,
                               m_cfg.squeeze_mult))
        {
            Print("[StandaloneSelector] ❌ Regime detector init failed");
            return false;
        }

        // 3. Restore last known regime (before first real detection)
        m_current_regime = m_cfg.last_regime;

        // 4. Apply initial strategy set based on last saved regime
        _ApplyRegime(m_current_regime, false);  // silent: no cooldown reset

        m_initialized = true;
        PrintFormat("[StandaloneSelector] ✅ Initialized | %s %s | start_regime=%s | active=%d strategies",
                    m_symbol, EnumToString(m_tf),
                    RegimeToString(m_current_regime), m_active_count);
        return true;
    }

    //+------------------------------------------------------------------+
    //| Deinit: Release indicators and save final state                  |
    //+------------------------------------------------------------------+
    void Deinit()
    {
        if(!m_initialized) return;

        // Save current state before shutdown
        m_cfg.last_regime = m_current_regime;
        m_cfg.last_saved  = TimeCurrent();
        m_cfg_mgr.Save(m_config_file, m_cfg);

        m_regime_det.Deinit();
        m_initialized = false;
        Print("[StandaloneSelector] Deinit — config saved");
    }

    //+------------------------------------------------------------------+
    //| OnTick: Main entry point — call every 100ms timer               |
    //| Flow: DetectRegime → SelectStrategies → CalculateConfidence      |
    //|       → If regime changed + confidence OK → Execute             |
    //+------------------------------------------------------------------+
    void OnTick(const MqlTick &tick)
    {
        if(!m_initialized) return;
        m_tick_count++;

        // ── Step 1: Detect regime ─────────────────────────────────────
        ENUM_MARKET_REGIME new_regime = DetectRegime(tick);

        // ── Step 2: On regime change — select strategies (with cooldown)
        if(new_regime != m_current_regime)
        {
            m_prev_regime   = m_current_regime;
            m_current_regime= new_regime;
            m_cooldown_bars_left = m_cooldown_bars;  // wait 3 bars
            m_regime_change_count++;
            m_last_regime_change_time = TimeCurrent();
            SelectStrategies(m_current_regime);
        }

        // Decrement cooldown bar counter (bar-level)
        if(m_cooldown_bars_left > 0)
        {
            static datetime _last_bar = 0;
            datetime _cur_bar = (datetime)SeriesInfoInteger(m_symbol, m_tf, SERIES_LASTBAR_DATE);
            if(_cur_bar != _last_bar)
            {
                _last_bar = _cur_bar;
                m_cooldown_bars_left--;
            }
        }

        // ── Step 3: Confidence check ──────────────────────────────────
        m_confidence = CalculateConfidence();
        if(m_confidence < m_cfg.confidence_min) return;  // below threshold

        // ── Step 4: Execute via StrategyManager (StrategyManager already
        //    has the correct strategies enabled; OnTick forwards to them)
        // Note: execution is implicit — StrategyManager_V6.OnTick() is
        // called by ProgramC_Trader.OnTimer_V6(), which calls:
        //   g_strategy_manager_v6.OnTick(tick)
        // We only need to ensure the right strategies are ENABLED.
        // Nothing extra needed here.
    }

    //+------------------------------------------------------------------+
    //| DetectRegime: Run CSimpleRegime detector                         |
    //+------------------------------------------------------------------+
    ENUM_MARKET_REGIME DetectRegime(const MqlTick &tick)
    {
        if(!m_initialized || !m_regime_det.IsReady())
            return m_current_regime;
        return m_regime_det.Detect(tick);
    }

    //+------------------------------------------------------------------+
    //| SelectStrategies: Enable correct standalone strategies for regime |
    //| Uses GetStandaloneStrategiesForRegime() from StrategyConstants   |
    //+------------------------------------------------------------------+
    void SelectStrategies(ENUM_MARKET_REGIME regime)
    {
        if(m_strategy_mgr == NULL) return;

        // 1. Get IDs for this regime
        ENUM_STRATEGY_ID regime_ids[];
        int count = GetStandaloneStrategiesForRegime(regime, regime_ids);

        // 2. Disable ALL strategies first
        m_strategy_mgr.EnableAllStandalone();  // resets to only SA-capable
        // Now selectively disable those NOT in this regime's list
        _DisableExcept(regime_ids, count);

        // 3. Cache active IDs
        m_active_count = MathMin(count, 4);
        for(int i = 0; i < m_active_count; i++)
            m_active_ids[i] = regime_ids[i];

        // 4. Announce selection
        string id_str = "";
        for(int i = 0; i < m_active_count; i++)
        {
            SStrategyInfo info = GetStrategyInfo(regime_ids[i]);
            id_str += info.short_name;
            if(i < m_active_count - 1) id_str += "+";
        }

        PrintFormat("[StandaloneSelector] 🎯 REGIME=%s → Active: [%s] | conf=%.2f",
                    RegimeToString(regime), id_str, m_confidence);

        // 5. Auto-save when regime changes
        m_cfg.last_regime = regime;
        m_cfg.last_saved  = TimeCurrent();
        m_cfg_mgr.Save(m_config_file, m_cfg);
    }

    //+------------------------------------------------------------------+
    //| CalculateConfidence: Return detector confidence                  |
    //| @return 0.0-1.0; acts when ≥ confidence_min threshold           |
    //+------------------------------------------------------------------+
    double CalculateConfidence()
    {
        return m_regime_det.GetConfidence();
    }

    // ── Config update from server (hot-reload without restart) ─────────

    //+------------------------------------------------------------------+
    //| UpdateThresholds: Server can push new thresholds at runtime      |
    //| Called when COMMAND="UPDATE_THRESHOLDS" received                 |
    //+------------------------------------------------------------------+
    void UpdateThresholds(double adx_enter, double adx_exit,
                          double adx_vol,   double sq_mult,
                          double conf_min,  double risk_mult)
    {
        m_cfg.adx_trend_enter = adx_enter;
        m_cfg.adx_trend_exit  = adx_exit;
        m_cfg.adx_volatile    = adx_vol;
        m_cfg.squeeze_mult    = sq_mult;
        m_cfg.confidence_min  = conf_min;
        m_cfg.risk_multiplier = risk_mult;

        // Re-init detector with new thresholds (cheap — just re-creates handles)
        m_regime_det.Deinit();
        m_regime_det.Setup(m_symbol, m_tf,
                           m_cfg.adx_trend_enter, m_cfg.adx_trend_exit,
                           m_cfg.adx_volatile, m_cfg.squeeze_mult);

        PrintFormat("[StandaloneSelector] Thresholds updated | ADX enter=%.1f exit=%.1f vol=%.1f sq=%.2f",
                    adx_enter, adx_exit, adx_vol, sq_mult);
    }

    //+------------------------------------------------------------------+
    //| SaveConfig: Explicit save (called from ProgramC_Trader OnDeinit) |
    //+------------------------------------------------------------------+
    bool SaveConfig()
    {
        m_cfg.last_regime = m_current_regime;
        m_cfg.last_saved  = TimeCurrent();
        return m_cfg_mgr.Save(m_config_file, m_cfg);
    }

    //+------------------------------------------------------------------+
    //| LoadConfig: Reload from file (hot-reload without restart)        |
    //+------------------------------------------------------------------+
    bool LoadConfig()
    {
        SStandaloneConfig new_cfg;
        if(!m_cfg_mgr.Load(m_config_file, new_cfg)) return false;
        m_cfg = new_cfg;
        return true;
    }

    // ── Accessors ────────────────────────────────────────────────────

    ENUM_MARKET_REGIME  GetCurrentRegime()  const { return m_current_regime; }
    ENUM_MARKET_REGIME  GetPrevRegime()     const { return m_prev_regime; }
    double              GetConfidence()     const { return m_confidence; }
    int                 GetActiveCount()    const { return m_active_count; }
    bool                IsInitialized()     const { return m_initialized; }
    int                 GetRegimeChanges()  const { return m_regime_change_count; }
    SStandaloneConfig   GetConfig()         const { return m_cfg; }
    double              GetADX()            const { return m_regime_det.GetADX(); }
    double              GetBBWidth()        const { return m_regime_det.GetBBWidth(); }

    //+------------------------------------------------------------------+
    //| PrintStatus: Detailed status for Expert tab                      |
    //+------------------------------------------------------------------+
    void PrintStatus()
    {
        Print("───── StandaloneSelector Status ─────");
        PrintFormat("  Regime:   %s (prev=%s)",
                    RegimeToString(m_current_regime),
                    RegimeToString(m_prev_regime));
        PrintFormat("  Detector: %s", m_regime_det.GetStatusString());
        PrintFormat("  Confidence: %.2f (min=%.2f)", m_confidence, m_cfg.confidence_min);
        PrintFormat("  Risk mult:  %.2f | MM: %s",
                    m_cfg.risk_multiplier, m_cfg.mm_method);
        PrintFormat("  Active strategies (%d):", m_active_count);
        for(int i = 0; i < m_active_count; i++)
        {
            SStrategyInfo info = GetStrategyInfo(m_active_ids[i]);
            PrintFormat("    [%d] %s — %s", i+1, info.short_name, info.name);
        }
        PrintFormat("  Regime changes: %d | Cooldown: %d bars",
                    m_regime_change_count, m_cooldown_bars_left);
        Print("─────────────────────────────────────");
    }

private:
    //+------------------------------------------------------------------+
    //| _ApplyRegime: Enable strategies for regime (no announcement)     |
    //| Used on Init() to restore last state quietly                     |
    //+------------------------------------------------------------------+
    void _ApplyRegime(ENUM_MARKET_REGIME regime, bool save = true)
    {
        if(m_strategy_mgr == NULL) return;

        ENUM_STRATEGY_ID regime_ids[];
        int count = GetStandaloneStrategiesForRegime(regime, regime_ids);

        m_strategy_mgr.EnableAllStandalone();
        _DisableExcept(regime_ids, count);

        m_active_count = MathMin(count, 4);
        for(int i = 0; i < m_active_count; i++)
            m_active_ids[i] = regime_ids[i];

        if(save)
        {
            m_cfg.last_regime = regime;
            m_cfg.last_saved  = TimeCurrent();
            m_cfg_mgr.Save(m_config_file, m_cfg);
        }
    }

    //+------------------------------------------------------------------+
    //| _DisableExcept: Disable standalone strategies NOT in ids[]       |
    //| Called after EnableAllStandalone() to narrow to regime subset    |
    //+------------------------------------------------------------------+
    void _DisableExcept(ENUM_STRATEGY_ID &ids[], int count)
    {
        // List of all 7 standalone strategy IDs
        ENUM_STRATEGY_ID all_sa[7];
        all_sa[0] = S01_STAT_ARB;
        all_sa[1] = S06_KAMA;
        all_sa[2] = S07_MEAN_REVERSION;
        all_sa[3] = S10_TURTLE;
        all_sa[4] = S14_BB_SQUEEZE;
        all_sa[5] = S15_GRID;
        all_sa[6] = S16_SPIKE;

        for(int i = 0; i < 7; i++)
        {
            bool in_regime = false;
            for(int j = 0; j < count; j++)
            {
                if(all_sa[i] == ids[j]) { in_regime = true; break; }
            }
            if(!in_regime)
            {
                IStrategy* s = m_strategy_mgr.GetStrategyByID(all_sa[i]);
                if(s != NULL) s.Disable();
            }
        }
    }
};

#endif // STANDALONE_SELECTOR_MQH
//+------------------------------------------------------------------+
