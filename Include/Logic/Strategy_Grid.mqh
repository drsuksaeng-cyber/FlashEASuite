//+------------------------------------------------------------------+
//|                                          Strategy_Grid.mqh       |
//|                                      FlashEASuite V2 - Program C |
//|                       Grid Strategy V2 Wrapper (Week 1-4)        |
//+------------------------------------------------------------------+
#property strict

// Include base interface
#include "StrategyBase.mqh"

// Include Grid modules
#include "Grid/GridCore.mqh"

// Optional: Include Week 3-4 modules if they need to be exposed
// These are typically included by GridCore.mqh internally, but can be
// explicitly included here if needed for direct access:
//
// #include "Grid/MarketAnalysis.mqh"
// #include "Grid/GridExecution.mqh"
// #include "Grid/GridDecision.mqh"
// #include "Grid/GridRiskManager.mqh"
// #include "Grid/SpreadFilter.mqh"
// #include "Grid/SlippageController.mqh"

//+------------------------------------------------------------------+
//| Note: CStrategyGrid class is defined in Grid/GridCore.mqh       |
//|       This file acts as a wrapper to include all Grid modules   |
//|       No class redefinition needed here!                        |
//+------------------------------------------------------------------+
