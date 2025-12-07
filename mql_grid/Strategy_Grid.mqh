//+------------------------------------------------------------------+
//|                                             Strategy_Grid.mqh    |
//|                                      FlashEASuite V2 - Program C |
//|                  Elastic Grid Strategy with ATR Spacing (Modular)|
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Modular Grid Strategy System                                     |
//|                                                                   |
//| This file serves as a wrapper that includes:                     |
//| - GridConfig.mqh: Configuration and parameters                   |
//| - GridState.mqh: State management and position tracking          |
//| - GridCore.mqh: Main strategy logic and execution                |
//|                                                                   |
//| Split into modular files for better maintainability.             |
//| Each file < 200 lines for easy reading and debugging.            |
//+------------------------------------------------------------------+

// Include Grid modules (order matters - inheritance chain)
#include "Grid/GridCore.mqh"

//+------------------------------------------------------------------+
//| End of Strategy_Grid.mqh wrapper                                 |
//+------------------------------------------------------------------+
