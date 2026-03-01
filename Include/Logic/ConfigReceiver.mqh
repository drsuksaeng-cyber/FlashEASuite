//+------------------------------------------------------------------+
//| ConfigReceiver.mqh                                               |
//| FlashEASuite V2 V6 — Full CONFIG_PUSH Handler + 15 Message Types |
//| Phase P6-1: Full Implementation                                  |
//+------------------------------------------------------------------+
//| Changes from P0-3 skeleton:                                      |
//|  - ReceiveMessage(): routes all 15 message types                 |
//|  - _ParseConfigPush(): full MessagePack → SConfigData           |
//|  - _ParseInitialConfig(): same structure as ConfigPush          |
//|  - _ParseNewsAlert(): populate news fields                      |
//|  - _ParseRegimeChange(): update regime in last config           |
//|  - _ParseCommand(): store pending command for main EA           |
//|  - SaveStandaloneConfig(): real file write (INI text format)    |
//|  - LoadStandaloneConfig(): real file read                       |
//|  - ParseDynamicParams(): full MessagePack V2 key-value parse    |
//|  - Private MessagePack helpers: _MP_ReadXxx, _MP_Skip, etc.    |
//+------------------------------------------------------------------+
//| File format for standalone_config.dat:                          |
//|   FLASHEA_V6_CONFIG                                             |
//|   timestamp=<epoch>                                              |
//|   regime=<0-4>                                                   |
//|   tf=<ENUM_TIMEFRAMES int>                                       |
//|   mm_method=<MM01..MM19>                                        |
//|   risk_mult=<double>                                             |
//|   has_news=<0|1>                                                 |
//|   news_desc=<string>                                             |
//|   seq=<int>                                                      |
//|   s00=<enabled>|<confidence>|<json_params>                       |
//|   s01=...  (16 lines, s00-s15)                                  |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.01"
#property strict

#ifndef CONFIG_RECEIVER_MQH
#define CONFIG_RECEIVER_MQH

#include "../Network/Protocol/Definitions.mqh"
#include "IStrategy.mqh"
#include "StrategyConstants.mqh"

// Forward declaration to avoid circular include
class CStrategyManager_V6;

// NOTE: SConfigData struct is defined in IStrategy.mqh
// NOTE: SDynamicParams struct is defined in IStrategy.mqh

//+------------------------------------------------------------------+
//| Type-punning structs for MessagePack float decoding             |
//| Placed at file scope (outside class) — MQL5 requires this      |
//+------------------------------------------------------------------+
struct S_MP_Double { double val; };
struct S_MP_Float  { float  val; };

//+------------------------------------------------------------------+
//| CLASS: CConfigReceiver                                           |
//| Full implementation for P6-1                                    |
//+------------------------------------------------------------------+
class CConfigReceiver
{
private:
    //--- Last received config
    SConfigData         m_last_config;
    datetime            m_last_config_time;
    int                 m_config_count;

    //--- Dynamic params cache (one SDynamicParams per strategy)
    SDynamicParams      m_strategy_params[TOTAL_STRATEGIES];
    bool                m_dynamic_params_received;
    string              m_last_change_summary;

    //--- Standalone config file name
    string              m_standalone_config_file;

    //--- Current symbol this EA is trading (for multi-symbol ConfigPush filtering)
    string              m_my_symbol;

    //--- Pending COMMAND from server (type 40)
    string              m_pending_command;     // e.g. "STOP","START","CLOSE_ALL"
    string              m_command_target;      // "" = broadcast, else client_id
    datetime            m_command_time;

    //--- Regime change tracking
    ENUM_MARKET_REGIME  m_prev_regime;
    datetime            m_regime_change_time;
    string              m_regime_change_method; // "RULE","RF_ML","HMM"

    //--- News alert tracking
    string              m_last_news_name;
    string              m_last_news_currency;
    int                 m_last_news_impact;     // 1=Low 2=Med 3=High
    long                m_last_news_time_ms;
    bool                m_has_unread_news;

    //=================================================================
    //  PRIVATE: MessagePack Container Helpers
    //=================================================================

    //+------------------------------------------------------------------+
    //| _MP_GetContainerSize: Read array/map header, return count       |
    //| Advances pos past the header byte(s).                           |
    //| Returns -1 on error or if not an array/map byte                 |
    //+------------------------------------------------------------------+
    int _MP_GetContainerSize(const uchar &data[], int &pos)
    {
        int sz = ArraySize(data);
        if(pos >= sz) return -1;

        uchar b = data[pos];
        pos++;

        // fixarray: 0x90-0x9F
        if(b >= 0x90 && b <= 0x9F) return (int)(b & 0x0F);

        // array16: 0xDC + 2 bytes BE
        if(b == 0xDC)
        {
            if(pos + 1 >= sz) return -1;
            int n = ((int)data[pos] << 8) | (int)data[pos + 1];
            pos += 2;
            return n;
        }

        // array32: 0xDD + 4 bytes BE
        if(b == 0xDD)
        {
            if(pos + 3 >= sz) return -1;
            long n = ((long)data[pos] << 24) | ((long)data[pos+1] << 16) |
                     ((long)data[pos+2] << 8) | (long)data[pos+3];
            pos += 4;
            return (int)n;
        }

        // fixmap: 0x80-0x8F (returns pair count)
        if(b >= 0x80 && b <= 0x8F) return (int)(b & 0x0F);

        // map16: 0xDE + 2 bytes BE
        if(b == 0xDE)
        {
            if(pos + 1 >= sz) return -1;
            int n = ((int)data[pos] << 8) | (int)data[pos + 1];
            pos += 2;
            return n;
        }

        // map32: 0xDF + 4 bytes BE
        if(b == 0xDF)
        {
            if(pos + 3 >= sz) return -1;
            long n = ((long)data[pos] << 24) | ((long)data[pos+1] << 16) |
                     ((long)data[pos+2] << 8) | (long)data[pos+3];
            pos += 4;
            return (int)n;
        }

        pos--;  // not an array/map header — put back
        return -1;
    }

    //+------------------------------------------------------------------+
    //| _MP_ReadInt: Read MessagePack integer (all int formats)         |
    //+------------------------------------------------------------------+
    int _MP_ReadInt(const uchar &data[], int &pos)
    {
        int sz = ArraySize(data);
        if(pos >= sz) return 0;

        uchar b = data[pos];
        pos++;

        if(b <= 0x7F) return (int)b;                          // positive fixint
        if(b >= 0xE0) return (int)((char)b);                  // negative fixint

        if(b == 0xC0) return 0;                                // nil
        if(b == 0xC2) return 0;                                // false
        if(b == 0xC3) return 1;                                // true

        if(b == 0xCC) { if(pos < sz) return (int)data[pos++]; return 0; }   // uint8
        if(b == 0xD0) { if(pos < sz) return (int)((char)data[pos++]); return 0; } // int8

        if(b == 0xCD) // uint16
        {
            if(pos + 1 < sz) { int v = ((int)data[pos] << 8) | (int)data[pos+1]; pos += 2; return v; }
            return 0;
        }
        if(b == 0xD1) // int16
        {
            if(pos + 1 < sz) { int v = (int)((short)(((int)data[pos] << 8) | (int)data[pos+1])); pos += 2; return v; }
            return 0;
        }
        if(b == 0xCE) // uint32
        {
            if(pos + 3 < sz)
            {
                long v = ((long)data[pos]<<24)|((long)data[pos+1]<<16)|((long)data[pos+2]<<8)|(long)data[pos+3];
                pos += 4; return (int)v;
            }
            return 0;
        }
        if(b == 0xD2) // int32
        {
            if(pos + 3 < sz)
            {
                int v = (int)(((long)data[pos]<<24)|((long)data[pos+1]<<16)|((long)data[pos+2]<<8)|(long)data[pos+3]);
                pos += 4; return v;
            }
            return 0;
        }
        if(b == 0xCF || b == 0xD3) { pos += 8; return 0; } // uint64/int64 — skip (too large)

        pos--;
        _MP_Skip(data, pos);
        return 0;
    }

    //+------------------------------------------------------------------+
    //| _MP_ReadLong: Read MessagePack integer into long (64-bit safe)  |
    //+------------------------------------------------------------------+
    long _MP_ReadLong(const uchar &data[], int &pos)
    {
        int sz = ArraySize(data);
        if(pos >= sz) return 0;

        uchar b = data[pos];
        pos++;

        if(b <= 0x7F) return (long)b;
        if(b >= 0xE0) return (long)((char)b);
        if(b == 0xC0) return 0;

        if(b == 0xCC) { if(pos < sz) return (long)data[pos++]; return 0; }
        if(b == 0xD0) { if(pos < sz) return (long)((char)data[pos++]); return 0; }

        if(b == 0xCD)
        {
            if(pos + 1 < sz) { long v = ((long)data[pos]<<8)|(long)data[pos+1]; pos+=2; return v; }
            return 0;
        }
        if(b == 0xD1)
        {
            if(pos + 1 < sz) { long v = (long)((short)(((int)data[pos]<<8)|(int)data[pos+1])); pos+=2; return v; }
            return 0;
        }
        if(b == 0xCE)
        {
            if(pos + 3 < sz)
            {
                long v = ((long)data[pos]<<24)|((long)data[pos+1]<<16)|((long)data[pos+2]<<8)|(long)data[pos+3];
                pos += 4; return v;
            }
            return 0;
        }
        if(b == 0xD2)
        {
            if(pos + 3 < sz)
            {
                long v = (long)(int)(((long)data[pos]<<24)|((long)data[pos+1]<<16)|((long)data[pos+2]<<8)|(long)data[pos+3]);
                pos += 4; return v;
            }
            return 0;
        }
        if(b == 0xCF || b == 0xD3) // uint64 / int64 — read all 8 bytes
        {
            if(pos + 7 < sz)
            {
                long v = 0;
                for(int i = 0; i < 8; i++) v = (v << 8) | (long)data[pos + i];
                pos += 8; return v;
            }
            return 0;
        }

        pos--;
        _MP_Skip(data, pos);
        return 0;
    }

    //+------------------------------------------------------------------+
    //| _MP_ReadDouble: Read MessagePack float32 or float64             |
    //| Uses CharArrayToStruct for safe byte-reinterpretation           |
    //+------------------------------------------------------------------+
    double _MP_ReadDouble(const uchar &data[], int &pos)
    {
        int sz = ArraySize(data);
        if(pos >= sz) return 0.0;

        uchar b = data[pos];
        pos++;

        if(b == 0xCB) // float64 (8 bytes big-endian IEEE 754)
        {
            if(pos + 7 >= sz) { pos = MathMin(pos + 8, sz); return 0.0; }
            uchar tmp[8];
            // Reverse byte order: big-endian → little-endian (x86)
            for(int i = 0; i < 8; i++) tmp[i] = data[pos + 7 - i];
            pos += 8;
            S_MP_Double sd;
            CharArrayToStruct(sd, tmp, 0);
            return sd.val;
        }

        if(b == 0xCA) // float32 (4 bytes big-endian IEEE 754)
        {
            if(pos + 3 >= sz) { pos = MathMin(pos + 4, sz); return 0.0; }
            uchar tmp[4];
            for(int i = 0; i < 4; i++) tmp[i] = data[pos + 3 - i];
            pos += 4;
            S_MP_Float sf;
            CharArrayToStruct(sf, tmp, 0);
            return (double)sf.val;
        }

        // Integer types — cast to double
        pos--;
        return (double)_MP_ReadLong(data, pos);
    }

    //+------------------------------------------------------------------+
    //| _MP_ReadBoolVal: Read MessagePack bool (or int cast to bool)    |
    //+------------------------------------------------------------------+
    bool _MP_ReadBoolVal(const uchar &data[], int &pos)
    {
        int sz = ArraySize(data);
        if(pos >= sz) return false;

        uchar b = data[pos];

        if(b == 0xC3) { pos++; return true;  } // true
        if(b == 0xC2) { pos++; return false; } // false
        if(b == 0xC0) { pos++; return false; } // nil → false

        // Integer → non-zero = true
        return (_MP_ReadInt(data, pos) != 0);
    }

    //+------------------------------------------------------------------+
    //| _MP_ReadStr: Read MessagePack string into MQL5 string           |
    //| Returns true if successful, false on parse error               |
    //+------------------------------------------------------------------+
    bool _MP_ReadStr(const uchar &data[], int &pos, string &out)
    {
        int sz = ArraySize(data);
        if(pos >= sz) { out = ""; return false; }

        uchar b = data[pos];
        pos++;
        int len = 0;

        if(b >= 0xA0 && b <= 0xBF)      // fixstr (0-31 chars)
        {
            len = (int)(b & 0x1F);
        }
        else if(b == 0xD9)               // str8
        {
            if(pos >= sz) { out = ""; return false; }
            len = (int)data[pos++];
        }
        else if(b == 0xDA)               // str16
        {
            if(pos + 1 >= sz) { out = ""; return false; }
            len = ((int)data[pos] << 8) | (int)data[pos+1];
            pos += 2;
        }
        else if(b == 0xDB)               // str32
        {
            if(pos + 3 >= sz) { out = ""; return false; }
            len = (int)(((long)data[pos]<<24)|((long)data[pos+1]<<16)|((long)data[pos+2]<<8)|(long)data[pos+3]);
            pos += 4;
        }
        else if(b == 0xC0)               // nil → empty string
        {
            out = ""; return true;
        }
        else
        {
            out = "";
            pos--;
            _MP_Skip(data, pos);
            return false;
        }

        if(len <= 0) { out = ""; return true; }
        if(pos + len > sz) { out = ""; return false; }

        uchar tmp[];
        ArrayResize(tmp, len);
        ArrayCopy(tmp, data, 0, pos, len);
        out = CharArrayToString(tmp, 0, len, CP_UTF8);
        pos += len;
        return true;
    }

    //+------------------------------------------------------------------+
    //| _MP_Skip: Skip one MessagePack value of any type                |
    //| Handles nested arrays and maps recursively                      |
    //+------------------------------------------------------------------+
    void _MP_Skip(const uchar &data[], int &pos)
    {
        int sz = ArraySize(data);
        if(pos >= sz) return;

        uchar b = data[pos];
        pos++;

        if(b <= 0x7F) return;                // positive fixint
        if(b >= 0xE0) return;                // negative fixint

        if(b >= 0xA0 && b <= 0xBF) { pos += (int)(b & 0x1F); return; } // fixstr

        if(b == 0xC0 || b == 0xC2 || b == 0xC3) return; // nil/false/true

        if(b == 0xCA) { pos += 4; return; }  // float32
        if(b == 0xCB) { pos += 8; return; }  // float64
        if(b == 0xCC || b == 0xD0) { pos += 1; return; } // uint8/int8
        if(b == 0xCD || b == 0xD1) { pos += 2; return; } // uint16/int16
        if(b == 0xCE || b == 0xD2) { pos += 4; return; } // uint32/int32
        if(b == 0xCF || b == 0xD3) { pos += 8; return; } // uint64/int64

        // str8/str16/str32
        if(b == 0xD9) { if(pos < sz) pos += 1 + (int)data[pos]; else pos++; return; }
        if(b == 0xDA) { if(pos+1<sz){ int n=((int)data[pos]<<8)|(int)data[pos+1]; pos+=2+n;} return; }
        if(b == 0xDB) { if(pos+3<sz){ long n=((long)data[pos]<<24)|((long)data[pos+1]<<16)|((long)data[pos+2]<<8)|(long)data[pos+3]; pos+=4+(int)n;} return; }

        // bin8/bin16/bin32
        if(b == 0xC4) { if(pos < sz) pos += 1 + (int)data[pos]; else pos++; return; }
        if(b == 0xC5) { if(pos+1<sz){ int n=((int)data[pos]<<8)|(int)data[pos+1]; pos+=2+n;} return; }
        if(b == 0xC6) { if(pos+3<sz){ long n=((long)data[pos]<<24)|((long)data[pos+1]<<16)|((long)data[pos+2]<<8)|(long)data[pos+3]; pos+=4+(int)n;} return; }

        // fixarray: 0x90-0x9F
        if(b >= 0x90 && b <= 0x9F) { int n=(int)(b&0x0F); for(int i=0;i<n;i++) _MP_Skip(data,pos); return; }
        // array16
        if(b == 0xDC) { if(pos+1<sz){ int n=((int)data[pos]<<8)|(int)data[pos+1]; pos+=2; for(int i=0;i<n;i++) _MP_Skip(data,pos);} return; }
        // array32
        if(b == 0xDD) { if(pos+3<sz){ long n=((long)data[pos]<<24)|((long)data[pos+1]<<16)|((long)data[pos+2]<<8)|(long)data[pos+3]; pos+=4; for(int i=0;i<(int)n;i++) _MP_Skip(data,pos);} return; }

        // fixmap: 0x80-0x8F
        if(b >= 0x80 && b <= 0x8F) { int n=(int)(b&0x0F); for(int i=0;i<n*2;i++) _MP_Skip(data,pos); return; }
        // map16
        if(b == 0xDE) { if(pos+1<sz){ int n=((int)data[pos]<<8)|(int)data[pos+1]; pos+=2; for(int i=0;i<n*2;i++) _MP_Skip(data,pos);} return; }
        // map32
        if(b == 0xDF) { if(pos+3<sz){ long n=((long)data[pos]<<24)|((long)data[pos+1]<<16)|((long)data[pos+2]<<8)|(long)data[pos+3]; pos+=4; for(int i=0;i<(int)n*2;i++) _MP_Skip(data,pos);} return; }
    }

    //+------------------------------------------------------------------+
    //| _MP_GetMsgType: Peek at message and return msg_type             |
    //| Does NOT advance any position cursor                            |
    //| Supports both array format [type,...] and map {"msg_type": N}  |
    //+------------------------------------------------------------------+
    int _MP_GetMsgType(const uchar &data[], int size)
    {
        if(size < 2) return 0;
        int pos = 0;
        uchar b = data[pos];

        // Array format (primary): first element = msg_type
        if((b >= 0x91 && b <= 0x9F) || b == 0xDC || b == 0xDD)
        {
            _MP_GetContainerSize(data, pos);   // skip array header (advances pos)
            return _MP_ReadInt(data, pos);
        }

        // Map format (dict): look for "msg_type" key
        if((b >= 0x81 && b <= 0x8F) || b == 0xDE || b == 0xDF)
        {
            int map_cnt = _MP_GetContainerSize(data, pos);
            for(int i = 0; i < map_cnt; i++)
            {
                string key = "";
                if(!_MP_ReadStr(data, pos, key)) return 0;
                if(key == "msg_type") return _MP_ReadInt(data, pos);
                _MP_Skip(data, pos);
            }
        }

        return 0; // unknown format
    }

    //+------------------------------------------------------------------+
    //| _MapStratIDToIndex: Convert "S01".."S16" or "1".."16" → 0..15  |
    //| Returns -1 if invalid                                           |
    //+------------------------------------------------------------------+
    int _MapStratIDToIndex(const string id_str)
    {
        if(StringLen(id_str) == 0) return -1;

        // "S01"-"S16" format
        if(StringLen(id_str) >= 2 && StringSubstr(id_str, 0, 1) == "S")
        {
            int num = (int)StringToInteger(StringSubstr(id_str, 1));
            if(num >= 1 && num <= 16) return num - 1;
        }

        // Numeric string "0"-"15" or "1"-"16"
        int num = (int)StringToInteger(id_str);
        if(num >= 0 && num < TOTAL_STRATEGIES) return num;
        if(num >= 1 && num <= TOTAL_STRATEGIES) return num - 1;

        return -1;
    }

    //=================================================================
    //  PRIVATE: Message Handlers (called from ReceiveMessage)
    //=================================================================

    //+------------------------------------------------------------------+
    //| _ParseConfigPush: Handle CONFIG_PUSH (msg_type = 10)            |
    //| MessagePack array format:                                       |
    //|  [msg_type, timestamp_ms, regime_str, symbol_count, symbols[]] |
    //|  Each symbol: [symbol_name, strat_count, strategies[]]         |
    //|  Each strategy: [id, name, enabled, confidence, tf, mm_method] |
    //+------------------------------------------------------------------+
    bool _ParseConfigPush(const uchar &data[], int size)
    {
        int pos = 0;
        int arr_cnt = _MP_GetContainerSize(data, pos);
        if(arr_cnt < 4)
        {
            Print("[ConfigReceiver] _ParseConfigPush: too few elements (", arr_cnt, ")");
            return false;
        }

        _MP_Skip(data, pos);                   // [0] msg_type
        long ts_ms  = _MP_ReadLong(data, pos); // [1] timestamp_ms
        string regime_str = "";
        _MP_ReadStr(data, pos, regime_str);    // [2] regime string
        int sym_count = _MP_ReadInt(data, pos);// [3] symbol_count

        SConfigData new_cfg;
        new_cfg.Reset();
        new_cfg.timestamp       = (datetime)(ts_ms / 1000LL);
        new_cfg.regime          = StringToRegime(regime_str);
        new_cfg.recommended_tf  = PERIOD_M15;
        new_cfg.mm_method       = "MM01";
        new_cfg.risk_multiplier = 1.0;
        new_cfg.sequence_number = m_last_config.sequence_number + 1;

        // Keep existing news state (NEWS_ALERT is a separate message)
        new_cfg.has_news_event    = m_last_config.has_news_event;
        new_cfg.news_description  = m_last_config.news_description;

        // [4] symbols array
        int syms_arr_cnt = _MP_GetContainerSize(data, pos);
        if(syms_arr_cnt < 0) syms_arr_cnt = 0;

        bool found_my_symbol = false;

        for(int s = 0; s < syms_arr_cnt; s++)
        {
            int sym_el_cnt = _MP_GetContainerSize(data, pos);
            if(sym_el_cnt < 3) { _MP_Skip(data, pos); continue; }

            // [symbol_name, strat_count, strategies[]]
            string sym_name = "";
            _MP_ReadStr(data, pos, sym_name);
            int strat_count = _MP_ReadInt(data, pos);
            int strat_arr_cnt = _MP_GetContainerSize(data, pos);
            if(strat_arr_cnt < 0) strat_arr_cnt = 0;

            // Use this symbol's data if it matches ours (or as fallback first symbol)
            bool use_this = (sym_name == m_my_symbol) || 
                            (!found_my_symbol && s == syms_arr_cnt - 1);

            if(sym_name == m_my_symbol) found_my_symbol = true;

            for(int st = 0; st < strat_arr_cnt; st++)
            {
                // Each strategy: [id_str, name_str, enabled, confidence, tf_str, mm_method]
                int sel_cnt = _MP_GetContainerSize(data, pos);
                if(sel_cnt < 1) break;

                string strat_id = "";
                _MP_ReadStr(data, pos, strat_id);

                string strat_name = "";
                if(sel_cnt >= 2) _MP_ReadStr(data, pos, strat_name);

                bool enabled = false;
                if(sel_cnt >= 3) enabled = _MP_ReadBoolVal(data, pos);

                double confidence = 0.0;
                if(sel_cnt >= 4) confidence = _MP_ReadDouble(data, pos);

                string tf_str = "";
                if(sel_cnt >= 5) _MP_ReadStr(data, pos, tf_str);

                string mm_str = "";
                if(sel_cnt >= 6) _MP_ReadStr(data, pos, mm_str);

                // Skip any extra elements beyond 6
                for(int ex = 6; ex < sel_cnt; ex++) _MP_Skip(data, pos);

                if(use_this)
                {
                    int idx = _MapStratIDToIndex(strat_id);
                    if(idx >= 0 && idx < TOTAL_STRATEGIES)
                    {
                        new_cfg.strategy_enabled[idx]    = enabled;
                        new_cfg.strategy_confidence[idx] = confidence;
                        if(mm_str != "") new_cfg.mm_method = mm_str; // use last seen mm_method
                    }
                }
            }

            // Skip any extra elements in symbol entry beyond 3
            for(int ex = 3; ex < sym_el_cnt; ex++) _MP_Skip(data, pos);
        }

        m_last_config     = new_cfg;
        m_last_config_time = TimeCurrent();
        m_config_count++;

        PrintFormat("[ConfigReceiver] CONFIG_PUSH #%d: regime=%s | enabled=%d/16 | mm=%s",
            m_config_count, regime_str, CountEnabledStrategies(new_cfg), new_cfg.mm_method);

        return true;
    }

    //+------------------------------------------------------------------+
    //| _ParseInitialConfig: Handle INITIAL_CONFIG (msg_type = 12)      |
    //| Same structure as CONFIG_PUSH, applied once on first connect    |
    //+------------------------------------------------------------------+
    bool _ParseInitialConfig(const uchar &data[], int size)
    {
        bool ok = _ParseConfigPush(data, size);
        if(ok)
        {
            // Save immediately as standalone backup after initial config
            SaveStandaloneConfig();
            Print("[ConfigReceiver] INITIAL_CONFIG applied and saved to standalone backup");
        }
        return ok;
    }

    //+------------------------------------------------------------------+
    //| _ParseNewsAlert: Handle NEWS_ALERT (msg_type = 30)              |
    //| MessagePack array: [type, ts, event_name, currency, impact,     |
    //|                     forecast, previous, event_time_ms]          |
    //+------------------------------------------------------------------+
    bool _ParseNewsAlert(const uchar &data[], int size)
    {
        int pos = 0;
        int arr_cnt = _MP_GetContainerSize(data, pos);
        if(arr_cnt < 4) return false;

        _MP_Skip(data, pos);                             // msg_type
        long ts_ms = _MP_ReadLong(data, pos);            // timestamp

        _MP_ReadStr(data, pos, m_last_news_name);        // event_name
        _MP_ReadStr(data, pos, m_last_news_currency);    // currency

        m_last_news_impact = (arr_cnt >= 5) ? _MP_ReadInt(data, pos) : 0;

        string forecast = "", previous = "";
        if(arr_cnt >= 6) _MP_ReadStr(data, pos, forecast);
        if(arr_cnt >= 7) _MP_ReadStr(data, pos, previous);

        m_last_news_time_ms = (arr_cnt >= 8) ? _MP_ReadLong(data, pos) : ts_ms;

        // High-impact news (>=2) → mark in config
        if(m_last_news_impact >= 2)
        {
            m_last_config.has_news_event   = true;
            m_last_config.news_description = m_last_news_name + " (" + m_last_news_currency + ")";
        }

        m_has_unread_news = true;

        PrintFormat("[ConfigReceiver] NEWS ALERT: %s %s | Impact:%d | Forecast:%s | Prev:%s",
            m_last_news_currency, m_last_news_name,
            m_last_news_impact, forecast, previous);
        return true;
    }

    //+------------------------------------------------------------------+
    //| _ParseRegimeChange: Handle REGIME_CHANGE (msg_type = 31)        |
    //| MessagePack array: [type, ts, old_regime, new_regime, conf, method]
    //+------------------------------------------------------------------+
    bool _ParseRegimeChange(const uchar &data[], int size)
    {
        int pos = 0;
        int arr_cnt = _MP_GetContainerSize(data, pos);
        if(arr_cnt < 4) return false;

        _MP_Skip(data, pos);                        // msg_type
        long ts_ms = _MP_ReadLong(data, pos);       // timestamp

        string old_str = "", new_str = "";
        _MP_ReadStr(data, pos, old_str);
        _MP_ReadStr(data, pos, new_str);

        double confidence = (arr_cnt >= 5) ? _MP_ReadDouble(data, pos) : 0.0;

        m_regime_change_method = "";
        if(arr_cnt >= 6) _MP_ReadStr(data, pos, m_regime_change_method);

        // Update state
        m_prev_regime               = m_last_config.regime;
        m_last_config.regime        = StringToRegime(new_str);
        m_regime_change_time        = TimeCurrent();

        PrintFormat("[ConfigReceiver] REGIME CHANGE: %s → %s | conf=%.2f | method=%s",
            old_str, new_str, confidence, m_regime_change_method);
        return true;
    }

    //+------------------------------------------------------------------+
    //| _ParseCommand: Handle COMMAND (msg_type = 40)                   |
    //| MessagePack array: [type, ts, target_client, command]           |
    //| Stores in m_pending_command for main EA to check               |
    //+------------------------------------------------------------------+
    bool _ParseCommand(const uchar &data[], int size)
    {
        int pos = 0;
        int arr_cnt = _MP_GetContainerSize(data, pos);
        if(arr_cnt < 3) return false;

        _MP_Skip(data, pos);                             // msg_type
        long ts_ms = _MP_ReadLong(data, pos);            // timestamp

        _MP_ReadStr(data, pos, m_command_target);        // target_client ("" = broadcast)
        _MP_ReadStr(data, pos, m_pending_command);       // command string

        m_command_time = TimeCurrent();

        PrintFormat("[ConfigReceiver] COMMAND: '%s' → target='%s'",
            m_pending_command,
            (m_command_target == "" ? "ALL" : m_command_target));
        return true;
    }

    //+------------------------------------------------------------------+
    //| _ParseHeartbeat: Handle HEARTBEAT (msg_type = 13)               |
    //| MessagePack array: [type, ts, source, sequence, is_alive]       |
    //| Note: ConnectionMonitor.UpdateHeartbeat() is called by main EA  |
    //+------------------------------------------------------------------+
    bool _ParseHeartbeat(const uchar &data[], int size)
    {
        int pos = 0;
        int arr_cnt = _MP_GetContainerSize(data, pos);
        if(arr_cnt < 2) return false;

        _MP_Skip(data, pos);                        // msg_type
        long ts_ms  = _MP_ReadLong(data, pos);      // timestamp

        string source = "";
        if(arr_cnt >= 3) _MP_ReadStr(data, pos, source);

        int seq = 0;
        if(arr_cnt >= 4) seq = _MP_ReadInt(data, pos);

        // Logging (not every heartbeat to avoid log flood)
        if(seq % 30 == 0 || seq == 1)
            PrintFormat("[ConfigReceiver] HEARTBEAT seq=%d src=%s", seq, source);

        return true;
    }

    //+------------------------------------------------------------------+
    //| _ParseError: Handle ERROR (msg_type = 99)                       |
    //| MessagePack array: [type, ts, source, error_code, error_message]|
    //+------------------------------------------------------------------+
    bool _ParseError(const uchar &data[], int size)
    {
        int pos = 0;
        int arr_cnt = _MP_GetContainerSize(data, pos);
        if(arr_cnt < 3) return false;

        _MP_Skip(data, pos);                        // msg_type
        long ts_ms = _MP_ReadLong(data, pos);

        string source = "", err_msg = "";
        int err_code = 0;

        if(arr_cnt >= 3) _MP_ReadStr(data, pos, source);
        if(arr_cnt >= 4) err_code = _MP_ReadInt(data, pos);
        if(arr_cnt >= 5) _MP_ReadStr(data, pos, err_msg);

        PrintFormat("[ConfigReceiver] SERVER ERROR: code=%d src=%s msg=%s",
            err_code, source, err_msg);
        return true;
    }

    //=================================================================
    //  PRIVATE: Utilities
    //=================================================================

    //+------------------------------------------------------------------+
    //| CountEnabledStrategies: Count enabled entries in SConfigData    |
    //+------------------------------------------------------------------+
    int CountEnabledStrategies(const SConfigData &config)
    {
        int count = 0;
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
            if(config.strategy_enabled[i]) count++;
        return count;
    }

    //+------------------------------------------------------------------+
    //| _WriteConfigLine: Helper for SaveStandaloneConfig               |
    //+------------------------------------------------------------------+
    void _WriteConfigLine(int fh, const string line)
    {
        FileWriteString(fh, line + "\r\n");
    }

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CConfigReceiver() :
        m_last_config_time(0),
        m_config_count(0),
        m_standalone_config_file("standalone_config.dat"),
        m_dynamic_params_received(false),
        m_last_change_summary(""),
        m_my_symbol(""),
        m_pending_command(""),
        m_command_target(""),
        m_command_time(0),
        m_prev_regime(REGIME_UNKNOWN),
        m_regime_change_time(0),
        m_regime_change_method(""),
        m_last_news_name(""),
        m_last_news_currency(""),
        m_last_news_impact(0),
        m_last_news_time_ms(0),
        m_has_unread_news(false)
    {
        m_last_config.Reset();
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
            m_strategy_params[i].Reset();
    }

    ~CConfigReceiver() {}

    //+------------------------------------------------------------------+
    //| Init: Initialize ConfigReceiver                                 |
    //| @param my_symbol  Symbol this EA is trading (for multi-symbol  |
    //|                   ConfigPush filtering). Empty = use Symbol()  |
    //+------------------------------------------------------------------+
    void Init(string my_symbol = "")
    {
        m_my_symbol = (my_symbol != "") ? my_symbol : Symbol();

        m_last_config.Reset();
        m_last_config_time        = 0;
        m_config_count            = 0;
        m_dynamic_params_received = false;
        m_last_change_summary     = "";
        m_pending_command         = "";
        m_command_target          = "";
        m_prev_regime             = REGIME_UNKNOWN;
        m_has_unread_news         = false;

        // Seed all strategies with hardcoded defaults from StrategyConstants
        ApplyDefaultDynamicParams();

        PrintFormat("[ConfigReceiver] Initialized | symbol=%s | config_file=%s",
            m_my_symbol, m_standalone_config_file);
    }

    //=================================================================
    //  CORE: Main Message Entry Point
    //=================================================================

    //+------------------------------------------------------------------+
    //| ReceiveMessage: Route incoming raw bytes to correct handler     |
    //| Call this from FlashEA_V6.mq5 OnTimer/OnTick with ZmqHub data |
    //| @param data  Raw MessagePack bytes from ZmqHub.Poll()          |
    //| @param size  Byte count                                         |
    //| @return ENUM_MSG_TYPE_V6 value (0 = MSG_V6_UNKNOWN on error)   |
    //|                                                                  |
    //| After calling this, if return == MSG_HEARTBEAT (13),           |
    //| the main EA must call g_connection_monitor.UpdateHeartbeat()   |
    //| (ConfigReceiver does NOT own ConnectionMonitor)                 |
    //+------------------------------------------------------------------+
    int ReceiveMessage(const uchar &data[], int size)
    {
        if(size <= 0) return MSG_V6_UNKNOWN;

        int msg_type = _MP_GetMsgType(data, size);

        switch(msg_type)
        {
            case MSG_CONFIG_PUSH:      _ParseConfigPush(data, size);    break;
            case MSG_INITIAL_CONFIG:   _ParseInitialConfig(data, size); break;
            case MSG_HEARTBEAT:        _ParseHeartbeat(data, size);     break;
            case MSG_NEWS_ALERT:       _ParseNewsAlert(data, size);     break;
            case MSG_REGIME_CHANGE:    _ParseRegimeChange(data, size);  break;
            case MSG_COMMAND:          _ParseCommand(data, size);       break;
            case MSG_POLICY_UPDATE:    /* handled by PolicyVerifier */  break;
            case MSG_ERROR:            _ParseError(data, size);         break;

            // Feeder messages (Trader shouldn't receive these, but handle gracefully)
            case MSG_TICK_DATA:
            case MSG_OHLC_DATA:
            case MSG_INDICATOR_DATA:
                // silently ignore
                break;

            // Client-outbound messages (Trader sends these, shouldn't receive)
            case MSG_CLIENT_HELLO:
            case MSG_TRADE_REPORT:
            case MSG_POSITION_UPDATE:
            case MSG_PERFORMANCE_METRICS:
                break;

            default:
                if(msg_type != MSG_V6_UNKNOWN)
                    PrintFormat("[ConfigReceiver] Unknown msg_type: %d (%d bytes)", msg_type, size);
                break;
        }

        return msg_type;
    }

    //+------------------------------------------------------------------+
    //| ReceiveConfig: Backward-compatible wrapper (P0-3 interface)     |
    //| Returns true if message was CONFIG_PUSH or INITIAL_CONFIG       |
    //+------------------------------------------------------------------+
    bool ReceiveConfig(const uchar &raw_data[], int data_size)
    {
        int t = ReceiveMessage(raw_data, data_size);
        return (t == MSG_CONFIG_PUSH || t == MSG_INITIAL_CONFIG);
    }

    //+------------------------------------------------------------------+
    //| ParseDynamicParams: Parse CONFIG_PUSH V2 (targeted per-strategy)|
    //| MessagePack array format:                                       |
    //|  [0] msg_type (int)                                             |
    //|  [1] timestamp_ms (long)                                        |
    //|  [2] strategy_id (int 0-15)                                     |
    //|  [3] mm_method (string e.g. "MM04")                             |
    //|  [4] risk_multiplier (double)                                   |
    //|  [5,6] param1_name(str), param1_val(double)                     |
    //|  [7,8] param2_name(str), param2_val(double)  ...               |
    //+------------------------------------------------------------------+
    bool ParseDynamicParams(uchar &data[], int size)
    {
        if(size <= 0)
        {
            Print("[ConfigReceiver] ParseDynamicParams: Empty data");
            return false;
        }

        int pos = 0;
        int arr_cnt = _MP_GetContainerSize(data, pos);
        if(arr_cnt < 5)
        {
            PrintFormat("[ConfigReceiver] ParseDynamicParams: Need >=5 elements, got %d", arr_cnt);
            return false;
        }

        _MP_Skip(data, pos);                            // [0] msg_type
        long ts_ms = _MP_ReadLong(data, pos);           // [1] timestamp_ms
        int strat_idx = _MP_ReadInt(data, pos);         // [2] strategy_id (0-15)

        if(strat_idx < 0 || strat_idx >= TOTAL_STRATEGIES)
        {
            PrintFormat("[ConfigReceiver] ParseDynamicParams: Invalid strategy_id=%d", strat_idx);
            return false;
        }

        string mm_method = "";
        _MP_ReadStr(data, pos, mm_method);              // [3] mm_method
        double risk_mult = _MP_ReadDouble(data, pos);   // [4] risk_multiplier

        // Reset this strategy's params and load fresh from server
        m_strategy_params[strat_idx].Reset();
        m_strategy_params[strat_idx].mm_method       = mm_method;
        m_strategy_params[strat_idx].risk_multiplier = risk_mult;

        // [5..N] param pairs: name(str), value(double)
        int remaining   = arr_cnt - 5;
        int pair_count  = remaining / 2;
        int parsed      = 0;

        for(int i = 0; i < pair_count && m_strategy_params[strat_idx].strategy_param_count < 20; i++)
        {
            string pname = "";
            if(!_MP_ReadStr(data, pos, pname)) break;
            double pval = _MP_ReadDouble(data, pos);
            m_strategy_params[strat_idx].SetParam(pname, pval);
            parsed++;
        }

        m_dynamic_params_received = true;
        m_last_change_summary = StringFormat(
            "S%02d params: mm=%s risk=%.2f params=%d",
            strat_idx + 1, mm_method, risk_mult, parsed);

        PrintFormat("[ConfigReceiver] Dynamic params for S%02d: %s", strat_idx + 1, m_last_change_summary);
        return true;
    }

    //+------------------------------------------------------------------+
    //| ApplyDefaultDynamicParams: Seed all strategies with defaults    |
    //| Called on Init() so strategies always have valid param bundles  |
    //+------------------------------------------------------------------+
    void ApplyDefaultDynamicParams()
    {
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
        {
            ENUM_STRATEGY_ID sid = (ENUM_STRATEGY_ID)i;
            m_strategy_params[i].Reset();
            m_strategy_params[i].mm_method       = GetDefaultMM(sid);
            m_strategy_params[i].risk_multiplier = 1.0;

            // Load default numeric params from StrategyConstants
            SStrategyDefaults def = GetStrategyDefaults(sid);
            for(int p = 0; p < def.param_count && p < 20; p++)
            {
                m_strategy_params[i].SetParam(def.param_names[p], def.param_values[p]);
            }
        }
    }

    //=================================================================
    //  PERSISTENCE: standalone_config.dat
    //=================================================================

    //+------------------------------------------------------------------+
    //| SaveStandaloneConfig: Persist current config to file            |
    //| Format: INI-style text, one field per line                     |
    //| Location: MQL5/Files/standalone_config.dat                     |
    //+------------------------------------------------------------------+
    void SaveStandaloneConfig()
    {
        int fh = FileOpen(m_standalone_config_file, FILE_WRITE | FILE_TXT | FILE_ANSI);
        if(fh == INVALID_HANDLE)
        {
            PrintFormat("[ConfigReceiver] SaveStandaloneConfig: Cannot open '%s' (error %d)",
                m_standalone_config_file, GetLastError());
            return;
        }

        _WriteConfigLine(fh, "FLASHEA_V6_CONFIG");
        _WriteConfigLine(fh, "version=1");
        _WriteConfigLine(fh, "timestamp=" + IntegerToString((long)m_last_config.timestamp));
        _WriteConfigLine(fh, "regime=" + IntegerToString((int)m_last_config.regime));
        _WriteConfigLine(fh, "tf=" + IntegerToString((int)m_last_config.recommended_tf));
        _WriteConfigLine(fh, "mm_method=" + m_last_config.mm_method);
        _WriteConfigLine(fh, "risk_mult=" + DoubleToString(m_last_config.risk_multiplier, 6));
        _WriteConfigLine(fh, "has_news=" + (m_last_config.has_news_event ? "1" : "0"));
        _WriteConfigLine(fh, "news_desc=" + m_last_config.news_description);
        _WriteConfigLine(fh, "seq=" + IntegerToString(m_last_config.sequence_number));
        _WriteConfigLine(fh, "symbol=" + m_my_symbol);

        for(int i = 0; i < TOTAL_STRATEGIES; i++)
        {
            string line = "s" + IntegerToString(i) + "=" +
                          (m_last_config.strategy_enabled[i] ? "1" : "0") + "|" +
                          DoubleToString(m_last_config.strategy_confidence[i], 4) + "|" +
                          m_last_config.strategy_params[i];
            _WriteConfigLine(fh, line);
        }

        FileClose(fh);

        PrintFormat("[ConfigReceiver] Standalone config SAVED: %s | regime=%s | %d strategies enabled",
            m_standalone_config_file,
            RegimeToString(m_last_config.regime),
            CountEnabledStrategies(m_last_config));
    }

    //+------------------------------------------------------------------+
    //| LoadStandaloneConfig: Load config from standalone_config.dat   |
    //| Called during OnInit() when server is not available            |
    //| @return true if file found and loaded successfully             |
    //+------------------------------------------------------------------+
    bool LoadStandaloneConfig()
    {
        if(!FileIsExist(m_standalone_config_file))
        {
            PrintFormat("[ConfigReceiver] No standalone config file: '%s' — using defaults",
                m_standalone_config_file);
            return false;
        }

        int fh = FileOpen(m_standalone_config_file, FILE_READ | FILE_TXT | FILE_ANSI);
        if(fh == INVALID_HANDLE)
        {
            PrintFormat("[ConfigReceiver] LoadStandaloneConfig: Cannot open '%s' (error %d)",
                m_standalone_config_file, GetLastError());
            return false;
        }

        // Verify file header
        string header = FileReadString(fh);
        if(header != "FLASHEA_V6_CONFIG")
        {
            PrintFormat("[ConfigReceiver] Invalid file header: '%s'", header);
            FileClose(fh);
            return false;
        }

        SConfigData loaded;
        loaded.Reset();

        while(!FileIsEnding(fh))
        {
            string line = FileReadString(fh);
            if(StringLen(line) == 0) continue;

            int eq = StringFind(line, "=");
            if(eq < 1) continue;

            string key = StringSubstr(line, 0, eq);
            string val = StringSubstr(line, eq + 1);

            if(key == "timestamp")    loaded.timestamp        = (datetime)StringToInteger(val);
            else if(key == "regime")  loaded.regime           = (ENUM_MARKET_REGIME)(int)StringToInteger(val);
            else if(key == "tf")      loaded.recommended_tf   = (ENUM_TIMEFRAMES)(int)StringToInteger(val);
            else if(key == "mm_method") loaded.mm_method      = val;
            else if(key == "risk_mult") loaded.risk_multiplier = StringToDouble(val);
            else if(key == "has_news")  loaded.has_news_event = (val == "1");
            else if(key == "news_desc") loaded.news_description = val;
            else if(key == "seq")       loaded.sequence_number  = (int)StringToInteger(val);
            else if(key == "symbol" && m_my_symbol == "") m_my_symbol = val;
            else if(StringLen(key) >= 2 && StringSubstr(key, 0, 1) == "s")
            {
                int idx = (int)StringToInteger(StringSubstr(key, 1));
                if(idx >= 0 && idx < TOTAL_STRATEGIES)
                {
                    // Format: "<enabled>|<confidence>|<json_params>"
                    int p1 = StringFind(val, "|");
                    int p2 = (p1 >= 0) ? StringFind(val, "|", p1 + 1) : -1;

                    if(p1 >= 0)
                    {
                        loaded.strategy_enabled[idx]    = (StringSubstr(val, 0, p1) == "1");
                        if(p2 > p1)
                        {
                            loaded.strategy_confidence[idx] = StringToDouble(
                                StringSubstr(val, p1 + 1, p2 - p1 - 1));
                            loaded.strategy_params[idx] = StringSubstr(val, p2 + 1);
                        }
                    }
                }
            }
        }

        FileClose(fh);

        m_last_config      = loaded;
        m_last_config_time = TimeCurrent();
        m_config_count++;

        PrintFormat("[ConfigReceiver] Standalone config LOADED: %s | regime=%s | %d strategies",
            m_standalone_config_file,
            RegimeToString(m_last_config.regime),
            CountEnabledStrategies(m_last_config));

        return true;
    }

    //=================================================================
    //  GETTERS: Dynamic Params
    //=================================================================

    SDynamicParams GetDynamicParamsForStrategy(ENUM_STRATEGY_ID id)
    {
        if((int)id < 0 || (int)id >= TOTAL_STRATEGIES)
        {
            SDynamicParams empty;
            empty.Reset();
            return empty;
        }
        return m_strategy_params[(int)id];
    }

    string GetMMMethodForStrategy(ENUM_STRATEGY_ID id)
    {
        if((int)id < 0 || (int)id >= TOTAL_STRATEGIES) return GetDefaultMM(id);
        string mm = m_strategy_params[(int)id].mm_method;
        return (mm != "") ? mm : GetDefaultMM(id);
    }

    string GetChangeSummary()             { return m_last_change_summary; }
    bool   HasDynamicParams()             { return m_dynamic_params_received; }

    //=================================================================
    //  GETTERS: Config Data
    //=================================================================

    SConfigData GetLastConfig()           { return m_last_config; }
    datetime    GetLastConfigTime()       { return m_last_config_time; }

    int GetSecondsSinceLastConfig()
    {
        if(m_last_config_time == 0) return -1;
        return (int)(TimeCurrent() - m_last_config_time);
    }

    int                GetConfigCount()       { return m_config_count; }
    ENUM_MARKET_REGIME GetCurrentRegime()     { return m_last_config.regime; }
    double             GetRiskMultiplier()    { return m_last_config.risk_multiplier; }

    bool IsStrategyEnabled(ENUM_STRATEGY_ID strategy_id)
    {
        if((int)strategy_id < 0 || (int)strategy_id >= TOTAL_STRATEGIES) return false;
        return m_last_config.strategy_enabled[(int)strategy_id];
    }

    double GetStrategyConfidence(ENUM_STRATEGY_ID strategy_id)
    {
        if((int)strategy_id < 0 || (int)strategy_id >= TOTAL_STRATEGIES) return 0.0;
        return m_last_config.strategy_confidence[(int)strategy_id];
    }

    bool   HasNewsEvent()       { return m_last_config.has_news_event; }
    string GetNewsDescription() { return m_last_config.news_description; }

    //=================================================================
    //  GETTERS: Pending Command (type 40)
    //=================================================================

    bool   HasPendingCommand()      { return (m_pending_command != ""); }
    string GetPendingCommand()      { return m_pending_command; }
    string GetCommandTarget()       { return m_command_target; }
    datetime GetCommandTime()       { return m_command_time; }

    void ClearPendingCommand()
    {
        m_pending_command = "";
        m_command_target  = "";
    }

    //=================================================================
    //  GETTERS: News Alert (type 30)
    //=================================================================

    bool   HasUnreadNews()          { return m_has_unread_news; }
    string GetLastNewsName()        { return m_last_news_name; }
    string GetLastNewsCurrency()    { return m_last_news_currency; }
    int    GetLastNewsImpact()      { return m_last_news_impact; }
    long   GetLastNewsTimeMs()      { return m_last_news_time_ms; }
    void   MarkNewsAsRead()         { m_has_unread_news = false; }

    //=================================================================
    //  GETTERS: Regime Change (type 31)
    //=================================================================

    ENUM_MARKET_REGIME GetPreviousRegime()    { return m_prev_regime; }
    datetime           GetRegimeChangeTime()  { return m_regime_change_time; }
    string             GetRegimeChangeMethod(){ return m_regime_change_method; }

    bool HasRecentRegimeChange(int within_seconds = 60)
    {
        if(m_regime_change_time == 0) return false;
        return ((int)(TimeCurrent() - m_regime_change_time) <= within_seconds);
    }
};

// Forward declaration (preserved from original skeleton)
class CStrategyManager;

#endif // CONFIG_RECEIVER_MQH
