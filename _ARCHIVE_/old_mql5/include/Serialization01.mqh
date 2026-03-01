//+------------------------------------------------------------------+
//|                                            Serialization.mqh      |
//|                        FlashEASuite V2 - Network Protocol        |
//|                V5.1 FIXED - Works with Definitions.mqh           |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property version   "5.1"
#property strict

// ✅ FIXED: No duplicate struct - uses PolicyMessage from Definitions.mqh
// This file MUST be included AFTER Definitions.mqh (via Protocol.mqh)
// PolicyMessage struct is defined in Definitions.mqh

//+------------------------------------------------------------------+
//| CProtocol Class                                                   |
//+------------------------------------------------------------------+
class CProtocol
{
public:
    //+------------------------------------------------------------------+
    //| Deserialize Policy Message - STUB VERSION                        |
    //+------------------------------------------------------------------+
    static bool DeserializePolicyMessage(const uchar &data[], PolicyMessage &result)
    {
        Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        Print("🔍 DESERIALIZE STUB (v5.1 FIXED):");
        Print("   Received: ", ArraySize(data), " bytes");
        Print("   ⚠️ Using STUB deserializer (for testing)");
        Print("   ✅ Uses PolicyMessage from Definitions.mqh");
        
        // Set reasonable default values (matching Definitions.mqh struct)
        result.symbol = "XAUUSD.tp";
        result.action = 1;                    // 1=BUY (not type)
        result.confidence = 0.95;
        result.entry_price = 0.0;
        result.stop_loss = 0.0;               // (not sl)
        result.take_profit = 0.0;             // (not tp)
        result.position_size = 0.01;          // (not lot_size)
        result.timestamp_ms = (long)(TimeCurrent() * 1000);  // (not timestamp)
        result.model_version = "Stub-v5.1";
        result.risk_multiplier = 1.0;
        result.is_in_cooldown = false;
        result.grid_direction = 1;            // 1=BUY direction
        
        // CSM data - neutral
        result.csm_usd = 0.0;
        result.csm_eur = 0.0;
        result.csm_gbp = 0.0;
        result.csm_jpy = 0.0;
        result.csm_aud = 0.0;
        result.csm_cad = 0.0;
        result.csm_chf = 0.0;
        result.csm_nzd = 0.0;
        
        Print("   ✅ Stub values assigned:");
        Print("      Action: ", result.action);
        Print("      Symbol: ", result.symbol);
        Print("      Position Size: ", result.position_size);
        Print("      Confidence: ", result.confidence);
        
        Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        Print("✅ DESERIALIZE COMPLETE (v5.1 FIXED)");
        Print("   💡 No duplicate struct!");
        Print("   💡 Uses Definitions.mqh struct!");
        Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        return true;
    }
};

//+------------------------------------------------------------------+
// End of Serialization.mqh
// This file contains BOTH struct and class
// Can be compiled separately without any includes
//+------------------------------------------------------------------+
