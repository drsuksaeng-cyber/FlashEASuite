//+------------------------------------------------------------------+
//|                                        Protocol/Serialization.mqh |
//|                                    FlashEASuite V2 - Program C   |
//|                     Message Protocol - Serialization Layer       |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property link      "https://www.mql5.com"
#property strict

#include "Definitions.mqh"

class CProtocol
  {
private:
   // Write primitives to buffer
   static bool       WriteInt32(uchar &buffer[], int &offset, const int value);
   static bool       WriteInt64(uchar &buffer[], int &offset, const long value);
   static bool       WriteDouble(uchar &buffer[], int &offset, const double value);
   static bool       WriteUInt64(uchar &buffer[], int &offset, const ulong value);
   static bool       WriteString(uchar &buffer[], int &offset, const string value);
   
   // Read primitives from buffer
   static bool       ReadInt32(const uchar &buffer[], int &offset, int &value);
   static bool       ReadInt64(const uchar &buffer[], int &offset, long &value);
   static bool       ReadDouble(const uchar &buffer[], int &offset, double &value);
   static bool       ReadUInt64(const uchar &buffer[], int &offset, ulong &value);
   static bool       ReadString(const uchar &buffer[], int &offset, string &value);

public:
   // Serialization methods
   static bool       SerializeTickMessage(const TickMessage &msg, uchar &buffer[]);
   static bool       SerializePolicyMessage(const PolicyMessage &msg, uchar &buffer[]);
   static bool       SerializeHeartbeat(const Heartbeat &msg, uchar &buffer[]);
   
   // Deserialization methods
   static bool       DeserializeTickMessage(const uchar &buffer[], TickMessage &msg);
   static bool       DeserializePolicyMessage(const uchar &buffer[], PolicyMessage &msg);
   static bool       DeserializeHeartbeat(const uchar &buffer[], Heartbeat &msg);
   
   // Utility methods
   static ENUM_MESSAGE_TYPE GetMessageType(const uchar &buffer[]);
  };

//+------------------------------------------------------------------+
//| Write Int32 to buffer                                             |
//+------------------------------------------------------------------+
static bool CProtocol::WriteInt32(uchar &buffer[], int &offset, const int value)
  {
   if(ArraySize(buffer) < offset + 4)
     {
      int new_size = offset + 4;
      if(ArrayResize(buffer, new_size) < new_size)
         return false;
     }
   
   buffer[offset]     = (uchar)((value >> 24) & 0xFF);
   buffer[offset + 1] = (uchar)((value >> 16) & 0xFF);
   buffer[offset + 2] = (uchar)((value >> 8) & 0xFF);
   buffer[offset + 3] = (uchar)(value & 0xFF);
   offset += 4;
   return true;
  }

//+------------------------------------------------------------------+
//| Write Int64 to buffer                                             |
//+------------------------------------------------------------------+
static bool CProtocol::WriteInt64(uchar &buffer[], int &offset, const long value)
  {
   if(ArraySize(buffer) < offset + 8)
     {
      int new_size = offset + 8;
      if(ArrayResize(buffer, new_size) < new_size)
         return false;
     }
   
   for(int i = 0; i < 8; i++)
     {
      buffer[offset + i] = (uchar)((value >> (56 - i * 8)) & 0xFF);
     }
   offset += 8;
   return true;
  }

//+------------------------------------------------------------------+
//| Write UInt64 to buffer                                            |
//+------------------------------------------------------------------+
static bool CProtocol::WriteUInt64(uchar &buffer[], int &offset, const ulong value)
  {
   if(ArraySize(buffer) < offset + 8)
     {
      int new_size = offset + 8;
      if(ArrayResize(buffer, new_size) < new_size)
         return false;
     }
   
   for(int i = 0; i < 8; i++)
     {
      buffer[offset + i] = (uchar)((value >> (56 - i * 8)) & 0xFF);
     }
   offset += 8;
   return true;
  }

//+------------------------------------------------------------------+
//| Write Double to buffer                                            |
//+------------------------------------------------------------------+
static bool CProtocol::WriteDouble(uchar &buffer[], int &offset, const double value)
  {
   if(ArraySize(buffer) < offset + 8)
     {
      int new_size = offset + 8;
      if(ArrayResize(buffer, new_size) < new_size)
         return false;
     }
   
   // Convert double to bytes using union trick
   union DoubleBytes
     {
      double d;
      uchar  b[8];
     } db = {0};
   
   db.d = value;
   
   // Write in big-endian order
   for(int i = 0; i < 8; i++)
     {
      buffer[offset + i] = db.b[7 - i];
     }
   offset += 8;
   return true;
  }

//+------------------------------------------------------------------+
//| Write String to buffer                                            |
//+------------------------------------------------------------------+
static bool CProtocol::WriteString(uchar &buffer[], int &offset, const string value)
  {
   uchar str_bytes[];
   int str_len = StringToCharArray(value, str_bytes, 0, WHOLE_ARRAY, CP_UTF8) - 1; // Exclude null terminator
   
   if(str_len < 0)
      str_len = 0;
   
   // Write string length first
   if(!WriteInt32(buffer, offset, str_len))
      return false;
   
   // Write string bytes
   if(str_len > 0)
     {
      if(ArraySize(buffer) < offset + str_len)
        {
         int new_size = offset + str_len;
         if(ArrayResize(buffer, new_size) < new_size)
            return false;
        }
      
      ArrayCopy(buffer, str_bytes, offset, 0, str_len);
      offset += str_len;
     }
   
   return true;
  }

//+------------------------------------------------------------------+
//| Read Int32 from buffer                                            |
//+------------------------------------------------------------------+
static bool CProtocol::ReadInt32(const uchar &buffer[], int &offset, int &value)
  {
   if(ArraySize(buffer) < offset + 4)
      return false;
   
   value = ((int)buffer[offset] << 24) |
           ((int)buffer[offset + 1] << 16) |
           ((int)buffer[offset + 2] << 8) |
           ((int)buffer[offset + 3]);
   
   offset += 4;
   return true;
  }

//+------------------------------------------------------------------+
//| Read Int64 from buffer                                            |
//+------------------------------------------------------------------+
static bool CProtocol::ReadInt64(const uchar &buffer[], int &offset, long &value)
  {
   if(ArraySize(buffer) < offset + 8)
      return false;
   
   value = 0;
   for(int i = 0; i < 8; i++)
     {
      value |= ((long)buffer[offset + i] << (56 - i * 8));
     }
   
   offset += 8;
   return true;
  }

//+------------------------------------------------------------------+
//| Read UInt64 from buffer                                           |
//+------------------------------------------------------------------+
static bool CProtocol::ReadUInt64(const uchar &buffer[], int &offset, ulong &value)
  {
   if(ArraySize(buffer) < offset + 8)
      return false;
   
   value = 0;
   for(int i = 0; i < 8; i++)
     {
      value |= ((ulong)buffer[offset + i] << (56 - i * 8));
     }
   
   offset += 8;
   return true;
  }

//+------------------------------------------------------------------+
//| Read Double from buffer                                           |
//+------------------------------------------------------------------+
static bool CProtocol::ReadDouble(const uchar &buffer[], int &offset, double &value)
  {
   if(ArraySize(buffer) < offset + 8)
      return false;
   
   union DoubleBytes
     {
      double d;
      uchar  b[8];
     } db;
   
   // Read in big-endian order
   for(int i = 0; i < 8; i++)
     {
      db.b[7 - i] = buffer[offset + i];
     }
   
   value = db.d;
   offset += 8;
   return true;
  }

//+------------------------------------------------------------------+
//| Read String from buffer                                           |
//+------------------------------------------------------------------+
static bool CProtocol::ReadString(const uchar &buffer[], int &offset, string &value)
  {
   int str_len;
   if(!ReadInt32(buffer, offset, str_len))
      return false;
   
   if(str_len < 0 || ArraySize(buffer) < offset + str_len)
      return false;
   
   if(str_len == 0)
     {
      value = "";
      return true;
     }
   
   uchar str_bytes[];
   ArrayResize(str_bytes, str_len + 1);
   ArrayCopy(str_bytes, buffer, 0, offset, str_len);
   str_bytes[str_len] = 0; // Null terminator
   
   value = CharArrayToString(str_bytes, 0, WHOLE_ARRAY, CP_UTF8);
   offset += str_len;
   return true;
  }

//+------------------------------------------------------------------+
//| Serialize Tick Message                                            |
//+------------------------------------------------------------------+
static bool CProtocol::SerializeTickMessage(const TickMessage &msg, uchar &buffer[])
  {
   ArrayResize(buffer, 0);
   int offset = 0;
   
   // Message type
   if(!WriteInt32(buffer, offset, MSG_TYPE_TICK))
      return false;
   
   // Fields
   if(!WriteString(buffer, offset, msg.symbol))
      return false;
   if(!WriteInt64(buffer, offset, msg.time_msc))
      return false;
   if(!WriteDouble(buffer, offset, msg.bid))
      return false;
   if(!WriteDouble(buffer, offset, msg.ask))
      return false;
   if(!WriteDouble(buffer, offset, msg.last))
      return false;
   if(!WriteUInt64(buffer, offset, msg.volume))
      return false;
   if(!WriteInt64(buffer, offset, msg.time_msc_sent))
      return false;
   
   return true;
  }

//+------------------------------------------------------------------+
//| Serialize Policy Message                                          |
//+------------------------------------------------------------------+
static bool CProtocol::SerializePolicyMessage(const PolicyMessage &msg, uchar &buffer[])
  {
   ArrayResize(buffer, 0);
   int offset = 0;
   
   // Message type
   if(!WriteInt32(buffer, offset, MSG_TYPE_POLICY))
      return false;
   
   // Fields
   if(!WriteString(buffer, offset, msg.symbol))
      return false;
   if(!WriteInt32(buffer, offset, msg.action))
      return false;
   if(!WriteDouble(buffer, offset, msg.confidence))
      return false;
   if(!WriteDouble(buffer, offset, msg.entry_price))
      return false;
   if(!WriteDouble(buffer, offset, msg.stop_loss))
      return false;
   if(!WriteDouble(buffer, offset, msg.take_profit))
      return false;
   if(!WriteDouble(buffer, offset, msg.position_size))
      return false;
   if(!WriteInt64(buffer, offset, msg.timestamp_ms))
      return false;
   if(!WriteString(buffer, offset, msg.model_version))
      return false;
   
   return true;
  }

//+------------------------------------------------------------------+
//| Serialize Heartbeat                                               |
//+------------------------------------------------------------------+
static bool CProtocol::SerializeHeartbeat(const Heartbeat &msg, uchar &buffer[])
  {
   ArrayResize(buffer, 0);
   int offset = 0;
   
   // Message type
   if(!WriteInt32(buffer, offset, MSG_TYPE_HEARTBEAT))
      return false;
   
   // Fields
   if(!WriteString(buffer, offset, msg.source))
      return false;
   if(!WriteInt64(buffer, offset, msg.timestamp_ms))
      return false;
   if(!WriteInt32(buffer, offset, msg.sequence))
      return false;
   if(!WriteInt32(buffer, offset, msg.is_alive ? 1 : 0))
      return false;
   
   return true;
  }

//+------------------------------------------------------------------+
//| Deserialize Tick Message                                          |
//+------------------------------------------------------------------+
static bool CProtocol::DeserializeTickMessage(const uchar &buffer[], TickMessage &msg)
  {
   int offset = 0;
   int msg_type;
   
   // Read and verify message type
   if(!ReadInt32(buffer, offset, msg_type))
      return false;
   if(msg_type != MSG_TYPE_TICK)
      return false;
   
   // Read fields
   if(!ReadString(buffer, offset, msg.symbol))
      return false;
   if(!ReadInt64(buffer, offset, msg.time_msc))
      return false;
   if(!ReadDouble(buffer, offset, msg.bid))
      return false;
   if(!ReadDouble(buffer, offset, msg.ask))
      return false;
   if(!ReadDouble(buffer, offset, msg.last))
      return false;
   if(!ReadUInt64(buffer, offset, msg.volume))
      return false;
   if(!ReadInt64(buffer, offset, msg.time_msc_sent))
      return false;
   
   return true;
  }

//+------------------------------------------------------------------+
//| Deserialize Policy Message                                        |
//+------------------------------------------------------------------+
static bool CProtocol::DeserializePolicyMessage(const uchar &buffer[], PolicyMessage &msg)
  {
   int offset = 0;
   int msg_type;
   
   // Read and verify message type
   if(!ReadInt32(buffer, offset, msg_type))
      return false;
   if(msg_type != MSG_TYPE_POLICY)
      return false;
   
   // Read fields
   if(!ReadString(buffer, offset, msg.symbol))
      return false;
   if(!ReadInt32(buffer, offset, msg.action))
      return false;
   if(!ReadDouble(buffer, offset, msg.confidence))
      return false;
   if(!ReadDouble(buffer, offset, msg.entry_price))
      return false;
   if(!ReadDouble(buffer, offset, msg.stop_loss))
      return false;
   if(!ReadDouble(buffer, offset, msg.take_profit))
      return false;
   if(!ReadDouble(buffer, offset, msg.position_size))
      return false;
   if(!ReadInt64(buffer, offset, msg.timestamp_ms))
      return false;
   if(!ReadString(buffer, offset, msg.model_version))
      return false;
   
   return true;
  }

//+------------------------------------------------------------------+
//| Deserialize Heartbeat                                             |
//+------------------------------------------------------------------+
static bool CProtocol::DeserializeHeartbeat(const uchar &buffer[], Heartbeat &msg)
  {
   int offset = 0;
   int msg_type;
   
   // Read and verify message type
   if(!ReadInt32(buffer, offset, msg_type))
      return false;
   if(msg_type != MSG_TYPE_HEARTBEAT)
      return false;
   
   // Read fields
   if(!ReadString(buffer, offset, msg.source))
      return false;
   if(!ReadInt64(buffer, offset, msg.timestamp_ms))
      return false;
   if(!ReadInt32(buffer, offset, msg.sequence))
      return false;
   
   int alive_flag;
   if(!ReadInt32(buffer, offset, alive_flag))
      return false;
   msg.is_alive = (alive_flag != 0);
   
   return true;
  }

//+------------------------------------------------------------------+
//| Get Message Type from buffer                                      |
//+------------------------------------------------------------------+
static ENUM_MESSAGE_TYPE CProtocol::GetMessageType(const uchar &buffer[])
  {
   if(ArraySize(buffer) < 4)
      return MSG_TYPE_UNKNOWN;
   
   int offset = 0;
   int msg_type;
   
   if(!ReadInt32(buffer, offset, msg_type))
      return MSG_TYPE_UNKNOWN;
   
   switch(msg_type)
     {
      case MSG_TYPE_TICK:
         return MSG_TYPE_TICK;
      case MSG_TYPE_POLICY:
         return MSG_TYPE_POLICY;
      case MSG_TYPE_HEARTBEAT:
         return MSG_TYPE_HEARTBEAT;
      default:
         return MSG_TYPE_UNKNOWN;
     }
  }
//+------------------------------------------------------------------+
