//+------------------------------------------------------------------+
//|                                                     Protocol.mqh |
//|                                    FlashEASuite V2 - Program C   |
//|                             Message Protocol Layer (Modular)     |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property link      "https://www.mql5.com"
#property strict

//+------------------------------------------------------------------+
//| Modular Protocol System                                          |
//|                                                                   |
//| This file serves as a wrapper that includes:                     |
//| - Definitions.mqh: Message type definitions and structures       |
//| - Serialization.mqh: Binary serialization/deserialization        |
//|                                                                   |
//| Split into modular files for better maintainability.             |
//+------------------------------------------------------------------+

// Include Protocol modules
#include "Protocol/Definitions.mqh"
#include "Protocol/Serialization.mqh"

//+------------------------------------------------------------------+
//| End of Protocol.mqh wrapper                                      |
//+------------------------------------------------------------------+
