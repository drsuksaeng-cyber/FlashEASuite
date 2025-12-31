//+------------------------------------------------------------------+
//|                                        Protocol/Serialization.mqh |
//|                                    FlashEASuite V2 - Program C   |
//|                         MessagePack Manual Parsing (No Library)  |
//|                      SIMPLIFIED: Array Format Only               |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property link      "https://www.mql5.com"
#property strict

//+------------------------------------------------------------------+
//| MessagePack Manual Parser                                         |
//+------------------------------------------------------------------+
class CMsgPackParser
  {
private:
   int m_pos;
   uchar m_data[];
   
   // Read functions
   long ReadInt64()
     {
      long value = 0;
      for(int i = 0; i < 8; i++)
        {
         value = (value << 8) | m_data[m_pos++];
        }
      return value;
     }
   
   int ReadInt32()
     {
      int value = 0;
      for(int i = 0; i < 4; i++)
        {
         value = (value << 8) | m_data[m_pos++];
        }
      return value;
     }
   
   double ReadDouble()
     {
      ulong bits = 0;
      for(int i = 0; i < 8; i++)
        {
         bits = (bits << 8) | m_data[m_pos++];
        }
      
      // Convert bits to double
      double result[];
      ArrayResize(result, 1);
      ulong temp[];
      ArrayResize(temp, 1);
      temp[0] = bits;
      ArrayCopy(result, temp);
      return result[0];
     }
   
   string ReadString()
     {
      uchar type = m_data[m_pos++];
      int len = 0;
      
      // fixstr (0xa0 - 0xbf)
      if((type & 0xe0) == 0xa0)
        {
         len = type & 0x1f;
        }
      // str 8 (0xd9)
      else if(type == 0xd9)
        {
         len = m_data[m_pos++];
        }
      // str 16 (0xda)
      else if(type == 0xda)
        {
         len = (m_data[m_pos] << 8) | m_data[m_pos + 1];
         m_pos += 2;
        }
      // str 32 (0xdb)
      else if(type == 0xdb)
        {
         len = ReadInt32();
        }
      else
        {
         Print("❌ Unknown string type: ", IntegerToString(type, 16, 2));
         return "";
        }
      
      // Read string bytes
      string result = "";
      for(int i = 0; i < len; i++)
        {
         result += CharToString(m_data[m_pos++]);
        }
      return result;
     }
   
   void SkipValue()
     {
      uchar type = m_data[m_pos++];
      
      // Positive fixint (0x00 - 0x7f)
      if(type <= 0x7f) return;
      
      // Negative fixint (0xe0 - 0xff)
      if(type >= 0xe0) return;
      
      // nil, false, true (0xc0, 0xc2, 0xc3)
      if(type == 0xc0 || type == 0xc2 || type == 0xc3) return;
      
      // uint8, int8 (0xcc, 0xd0)
      if(type == 0xcc || type == 0xd0) { m_pos++; return; }
      
      // uint16, int16 (0xcd, 0xd1)
      if(type == 0xcd || type == 0xd1) { m_pos += 2; return; }
      
      // uint32, int32, float (0xce, 0xd2, 0xca)
      if(type == 0xce || type == 0xd2 || type == 0xca) { m_pos += 4; return; }
      
      // uint64, int64, double (0xcf, 0xd3, 0xcb)
      if(type == 0xcf || type == 0xd3 || type == 0xcb) { m_pos += 8; return; }
      
      // string
      if((type & 0xe0) == 0xa0 || type == 0xd9 || type == 0xda || type == 0xdb)
        {
         m_pos--; // Go back
         ReadString(); // This will skip the string
         return;
        }
      
      Print("❌ Cannot skip type: ", IntegerToString(type, 16, 2));
     }
   
public:
   void SetData(uchar &data[])
     {
      ArrayResize(m_data, ArraySize(data));
      ArrayCopy(m_data, data);
      m_pos = 0;
     }
   
   int ReadArraySize()
     {
      uchar type = m_data[m_pos++];
      
      // fixarray (0x90 - 0x9f)
      if((type & 0xf0) == 0x90)
        {
         return (type & 0x0f);
        }
      // array 16 (0xdc)
      else if(type == 0xdc)
        {
         int size = (m_data[m_pos] << 8) | m_data[m_pos + 1];
         m_pos += 2;
         return size;
        }
      // array 32 (0xdd)
      else if(type == 0xdd)
        {
         return ReadInt32();
        }
      
      Print("❌ Not an array, type: ", IntegerToString(type, 16, 2));
      return -1;
     }
   
   long ReadNextInt()
     {
      uchar type = m_data[m_pos++];
      
      // Positive fixint (0x00 - 0x7f)
      if(type <= 0x7f) return (long)type;
      
      // Negative fixint (0xe0 - 0xff)
      if(type >= 0xe0) return (long)((char)type);
      
      // uint8 (0xcc)
      if(type == 0xcc) return (long)m_data[m_pos++];
      
      // int8 (0xd0)
      if(type == 0xd0) return (long)((char)m_data[m_pos++]);
      
      // uint16 (0xcd)
      if(type == 0xcd)
        {
         int val = (m_data[m_pos] << 8) | m_data[m_pos + 1];
         m_pos += 2;
         return (long)val;
        }
      
      // int16 (0xd1)
      if(type == 0xd1)
        {
         short val = (short)((m_data[m_pos] << 8) | m_data[m_pos + 1]);
         m_pos += 2;
         return (long)val;
        }
      
      // uint32 (0xce)
      if(type == 0xce)
        {
         return (long)ReadInt32();
        }
      
      // int32 (0xd2)
      if(type == 0xd2)
        {
         return (long)ReadInt32();
        }
      
      // uint64 (0xcf)
      if(type == 0xcf)
        {
         return ReadInt64();
        }
      
      // int64 (0xd3)
      if(type == 0xd3)
        {
         return ReadInt64();
        }
      
      Print("❌ Unknown int type: ", IntegerToString(type, 16, 2));
      return 0;
     }
   
   double ReadNextDouble()
     {
      uchar type = m_data[m_pos++];
      
      // float (0xca)
      if(type == 0xca)
        {
         // Skip float (not used)
         m_pos += 4;
         return 0.0;
        }
      
      // double (0xcb)
      if(type == 0xcb)
        {
         return ReadDouble();
        }
      
      // Might be int
      m_pos--;
      return (double)ReadNextInt();
     }
   
   string ReadNextString()
     {
      return ReadString();
     }
  };

//+------------------------------------------------------------------+
//| Protocol Handler Class                                            |
//+------------------------------------------------------------------+
class CProtocol
  {
public:
   //+------------------------------------------------------------------+
   //| Deserialize Policy Message from MessagePack ARRAY               |
   //| Format: [type, symbol, action, conf, entry, sl, tp, lots, ts, ver] |
   //+------------------------------------------------------------------+
   static bool DeserializePolicyMessage(uchar &data[], PolicyMessage &policy)
     {
      // Initialize policy with defaults
      policy.PolicyMessage();
      
      CMsgPackParser parser;
      parser.SetData(data);
      
      // Read array size
      int array_size = parser.ReadArraySize();
      if(array_size < 0)
        {
         Print("❌ Not a MessagePack array");
         return false;
        }
      
      Print("📦 MessagePack array size: ", array_size);
      
      if(array_size < 10)
        {
         Print("❌ Array too small, expected 10 elements, got ", array_size);
         return false;
        }
      
      // Read elements
      // [0] type
      long msg_type = parser.ReadNextInt();
      Print("  [0] type = ", msg_type);
      
      // [1] symbol
      policy.symbol = parser.ReadNextString();
      Print("  [1] symbol = ", policy.symbol);
      
      // [2] action
      policy.action = (int)parser.ReadNextInt();
      Print("  [2] action = ", policy.action);
      
      // [3] confidence
      policy.confidence = parser.ReadNextDouble();
      Print("  [3] confidence = ", policy.confidence);
      
      // [4] entry_price
      policy.entry_price = parser.ReadNextDouble();
      Print("  [4] entry_price = ", policy.entry_price);
      
      // [5] stop_loss
      policy.stop_loss = parser.ReadNextDouble();
      Print("  [5] stop_loss = ", policy.stop_loss);
      
      // [6] take_profit
      policy.take_profit = parser.ReadNextDouble();
      Print("  [6] take_profit = ", policy.take_profit);
      
      // [7] position_size
      policy.position_size = parser.ReadNextDouble();
      Print("  [7] position_size = ", policy.position_size);
      
      // [8] timestamp_ms
      policy.timestamp_ms = parser.ReadNextInt();
      Print("  [8] timestamp = ", policy.timestamp_ms);
      
      // [9] model_version
      policy.model_version = parser.ReadNextString();
      Print("  [9] model_version = ", policy.model_version);
      
      // Validate
      if(policy.symbol == "")
        {
         Print("❌ Invalid symbol");
         return false;
        }
      
      Print("✅ Policy deserialized successfully: ", policy.symbol);
      return true;
     }
  };
//+------------------------------------------------------------------+
