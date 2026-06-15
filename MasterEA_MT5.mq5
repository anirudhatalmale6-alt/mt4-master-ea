//+------------------------------------------------------------------+
//|                                                 MasterEA_MT5.mq5 |
//|                              Master EA - Trade Risk Controller   |
//|                                                                  |
//|  MT5 version of Master EA.                                       |
//|  Monitors trades opened by a slave EA and enforces               |
//|  three risk-control rules:                                       |
//|  1. Trading hours restriction                                    |
//|  2. Maximum simultaneous trades limit                            |
//|  3. Minimum time interval between orders                         |
//|                                                                  |
//|  Violations result in automatic trade closure with logging.      |
//+------------------------------------------------------------------+
#property copyright "Master EA"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input int      MagicNumber           = 12345;     // Magic Number of Slave EA to manage

input bool     UseTradingHours       = true;      // Use Trading Hours Filter
input int      StartHour             = 8;         // Start Hour (0-23)
input int      StartMinute           = 0;         // Start Minute (0-59)
input int      EndHour               = 17;        // End Hour (0-23)
input int      EndMinute             = 0;         // End Minute (0-59)
input bool     CloseOutsideHours     = true;      // Close trades outside trading hours

input bool     UseMaxTrades          = true;      // Use Max Trades Limit
input int      MaxRunningTrades      = 5;         // Maximum Running Trades Allowed

input bool     UseTimeInterval       = true;      // Use Time Interval Between Orders
input int      IntervalMinutes       = 1;         // Minimum Interval (Minutes)
input int      IntervalSeconds       = 0;         // Minimum Interval (Seconds)

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
datetime lastOrderTime = 0;
int totalIntervalSeconds = 0;
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   totalIntervalSeconds = (IntervalMinutes * 60) + IntervalSeconds;
   lastOrderTime = GetLastOrderTime();

   trade.SetExpertMagicNumber(MagicNumber);

   Print("==============================================");
   Print("Master EA MT5 Initialized");
   Print("Monitoring Magic Number: ", MagicNumber);
   Print("Trading Hours: ", UseTradingHours ? "ENABLED" : "DISABLED");
   if(UseTradingHours)
      Print("  Session: ", StringFormat("%02d:%02d", StartHour, StartMinute),
            " to ", StringFormat("%02d:%02d", EndHour, EndMinute));
   Print("Max Trades Limit: ", UseMaxTrades ? "ENABLED" : "DISABLED");
   if(UseMaxTrades)
      Print("  Max Trades: ", MaxRunningTrades);
   Print("Time Interval: ", UseTimeInterval ? "ENABLED" : "DISABLED");
   if(UseTimeInterval)
      Print("  Interval: ", IntervalMinutes, "m ", IntervalSeconds, "s");
   Print("==============================================");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Master EA MT5 Stopped. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckTradingHoursRule();
   CheckMaxTradesRule();
   CheckTimeIntervalRule();
}

//+------------------------------------------------------------------+
//| Check Trading Hours Rule                                          |
//+------------------------------------------------------------------+
void CheckTradingHoursRule()
{
   if(!UseTradingHours || !CloseOutsideHours)
      return;

   if(!IsWithinTradingHours())
   {
      int closedCount = CloseAllSlavePositions("TRADING HOURS VIOLATION");
      int deletedCount = DeleteAllSlavePendingOrders("TRADING HOURS VIOLATION");
      if(closedCount > 0 || deletedCount > 0)
      {
         Print("Trading Hours Rule: Closed ", closedCount, " position(s), deleted ",
               deletedCount, " pending order(s) - Outside allowed session");
      }
   }
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                     |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeCurrent(dt);

   int currentTotalMinutes = dt.hour * 60 + dt.min;
   int startTotalMinutes = StartHour * 60 + StartMinute;
   int endTotalMinutes = EndHour * 60 + EndMinute;

   if(startTotalMinutes > endTotalMinutes)
   {
      return (currentTotalMinutes >= startTotalMinutes || currentTotalMinutes < endTotalMinutes);
   }
   else
   {
      return (currentTotalMinutes >= startTotalMinutes && currentTotalMinutes < endTotalMinutes);
   }
}

//+------------------------------------------------------------------+
//| Check Max Trades Rule                                             |
//+------------------------------------------------------------------+
void CheckMaxTradesRule()
{
   if(!UseMaxTrades)
      return;

   int tradeCount = CountSlavePositions();

   if(tradeCount > MaxRunningTrades)
   {
      int excessTrades = tradeCount - MaxRunningTrades;
      Print("Max Trades Rule: ", tradeCount, " positions open, max allowed is ", MaxRunningTrades);

      int closedCount = CloseNewestSlavePositions(excessTrades, "MAX TRADES VIOLATION");
      if(closedCount > 0)
      {
         Print("Max Trades Rule: Closed ", closedCount, " excess position(s)");
      }
   }
}

//+------------------------------------------------------------------+
//| Check Time Interval Rule                                          |
//+------------------------------------------------------------------+
void CheckTimeIntervalRule()
{
   if(!UseTimeInterval || totalIntervalSeconds <= 0)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

      if(lastOrderTime > 0 && openTime > lastOrderTime)
      {
         int timeDiff = (int)(openTime - lastOrderTime);

         if(timeDiff < totalIntervalSeconds)
         {
            Print("Time Interval Rule: Position #", ticket,
                  " opened only ", timeDiff, "s after previous (min: ", totalIntervalSeconds, "s)");

            if(ClosePositionByTicket(ticket, "TIME INTERVAL VIOLATION"))
            {
               Print("Time Interval Rule: Closed position #", ticket);
            }
         }
         else
         {
            lastOrderTime = openTime;
         }
      }
      else if(openTime > lastOrderTime)
      {
         lastOrderTime = openTime;
      }
   }
}

//+------------------------------------------------------------------+
//| Count open positions from slave EA                                |
//+------------------------------------------------------------------+
int CountSlavePositions()
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| Get the open time of the most recent slave EA position            |
//+------------------------------------------------------------------+
datetime GetLastOrderTime()
{
   datetime latestTime = 0;

   // Check open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
         if(openTime > latestTime)
            latestTime = openTime;
      }
   }

   // Check deal history for recent trades
   HistorySelect(TimeCurrent() - 86400, TimeCurrent());
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;

      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == MagicNumber &&
         HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_IN)
      {
         datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
         if(dealTime > latestTime)
            latestTime = dealTime;
      }
   }

   return latestTime;
}

//+------------------------------------------------------------------+
//| Close all positions from slave EA                                 |
//+------------------------------------------------------------------+
int CloseAllSlavePositions(string reason)
{
   int closedCount = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      if(ClosePositionByTicket(ticket, reason))
         closedCount++;
   }

   return closedCount;
}

//+------------------------------------------------------------------+
//| Delete all pending orders from slave EA                           |
//+------------------------------------------------------------------+
int DeleteAllSlavePendingOrders(string reason)
{
   int deletedCount = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;

      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber)
         continue;

      if(trade.OrderDelete(ticket))
      {
         Print("MASTER EA ACTION: Deleted pending order #", ticket, " | Reason: ", reason);
         deletedCount++;
      }
      else
      {
         Print("Error deleting pending order #", ticket, " | Error: ", GetLastError());
      }
   }

   return deletedCount;
}

//+------------------------------------------------------------------+
//| Close the N newest positions from slave EA (LIFO)                 |
//+------------------------------------------------------------------+
int CloseNewestSlavePositions(int count, string reason)
{
   if(count <= 0)
      return 0;

   ulong tickets[];
   datetime openTimes[];
   int totalPositions = 0;

   // First pass: count
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         totalPositions++;
   }

   if(totalPositions == 0)
      return 0;

   ArrayResize(tickets, totalPositions);
   ArrayResize(openTimes, totalPositions);

   // Second pass: fill arrays
   int idx = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         tickets[idx] = ticket;
         openTimes[idx] = (datetime)PositionGetInteger(POSITION_TIME);
         idx++;
      }
   }

   // Sort by open time (newest first)
   for(int i = 0; i < totalPositions - 1; i++)
   {
      for(int j = i + 1; j < totalPositions; j++)
      {
         if(openTimes[j] > openTimes[i])
         {
            datetime tempTime = openTimes[i];
            openTimes[i] = openTimes[j];
            openTimes[j] = tempTime;

            ulong tempTicket = tickets[i];
            tickets[i] = tickets[j];
            tickets[j] = tempTicket;
         }
      }
   }

   // Close the newest positions
   int closedCount = 0;
   for(int i = 0; i < count && i < totalPositions; i++)
   {
      if(ClosePositionByTicket(tickets[i], reason))
         closedCount++;
   }

   return closedCount;
}

//+------------------------------------------------------------------+
//| Close a position by ticket number                                 |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(ulong ticket, string reason)
{
   if(!PositionSelectByTicket(ticket))
   {
      Print("Error: Could not select position #", ticket);
      return false;
   }

   string symbol = PositionGetString(POSITION_SYMBOL);
   long posType = PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);

   if(trade.PositionClose(ticket))
   {
      Print("MASTER EA ACTION: Closed position #", ticket, " | ", symbol, " | ",
            (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"), " | ",
            volume, " lots | Reason: ", reason);
      return true;
   }
   else
   {
      Print("Error closing position #", ticket, " | Error: ", GetLastError());
      return false;
   }
}
//+------------------------------------------------------------------+
