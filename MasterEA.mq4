//+------------------------------------------------------------------+
//|                                                     MasterEA.mq4 |
//|                              Master EA - Trade Risk Controller   |
//|                                                                  |
//|  Description:                                                    |
//|  This EA monitors trades opened by a slave EA and enforces       |
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
#property strict

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
// Magic Number Filter
input int      MagicNumber           = 12345;     // Magic Number of Slave EA to manage

// Trading Hours Settings
input bool     UseTradingHours       = true;      // Use Trading Hours Filter
input int      StartHour             = 8;         // Start Hour (0-23)
input int      StartMinute           = 0;         // Start Minute (0-59)
input int      EndHour               = 17;        // End Hour (0-23)
input int      EndMinute             = 0;         // End Minute (0-59)
input bool     CloseOutsideHours     = true;      // Close trades outside trading hours

// Max Trades Settings
input bool     UseMaxTrades          = true;      // Use Max Trades Limit
input int      MaxRunningTrades      = 5;         // Maximum Running Trades Allowed

// Time Interval Settings
input bool     UseTimeInterval       = true;      // Use Time Interval Between Orders
input int      IntervalMinutes       = 1;         // Minimum Interval (Minutes)
input int      IntervalSeconds       = 0;         // Minimum Interval (Seconds)

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
datetime lastOrderTime = 0;           // Timestamp of last order opened by slave EA
int totalIntervalSeconds = 0;         // Total interval in seconds

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Calculate total interval in seconds
   totalIntervalSeconds = (IntervalMinutes * 60) + IntervalSeconds;

   // Find the most recent order time for the slave EA
   lastOrderTime = GetLastOrderTime();

   // Log initialization
   Print("==============================================");
   Print("Master EA Initialized");
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
   Print("Master EA Stopped. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check and enforce all rules
   CheckTradingHoursRule();
   CheckMaxTradesRule();
   CheckTimeIntervalRule();
}

//+------------------------------------------------------------------+
//| Check Trading Hours Rule                                          |
//| Closes trades if current time is outside allowed trading hours    |
//+------------------------------------------------------------------+
void CheckTradingHoursRule()
{
   if(!UseTradingHours || !CloseOutsideHours)
      return;

   if(!IsWithinTradingHours())
   {
      // Close all trades from slave EA - outside trading hours
      int closedCount = CloseAllSlaveEATrades("TRADING HOURS VIOLATION");
      if(closedCount > 0)
      {
         Print("Trading Hours Rule: Closed ", closedCount, " trade(s) - Outside allowed session");
      }
   }
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                     |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   datetime currentTime = TimeCurrent();
   int currentHour = TimeHour(currentTime);
   int currentMinute = TimeMinute(currentTime);

   // Convert to minutes for easier comparison
   int currentTotalMinutes = currentHour * 60 + currentMinute;
   int startTotalMinutes = StartHour * 60 + StartMinute;
   int endTotalMinutes = EndHour * 60 + EndMinute;

   // Handle overnight sessions (e.g., 22:00 to 06:00)
   if(startTotalMinutes > endTotalMinutes)
   {
      // Overnight session
      return (currentTotalMinutes >= startTotalMinutes || currentTotalMinutes < endTotalMinutes);
   }
   else
   {
      // Normal session (same day)
      return (currentTotalMinutes >= startTotalMinutes && currentTotalMinutes < endTotalMinutes);
   }
}

//+------------------------------------------------------------------+
//| Check Max Trades Rule                                             |
//| Closes newest trades if count exceeds maximum allowed             |
//+------------------------------------------------------------------+
void CheckMaxTradesRule()
{
   if(!UseMaxTrades)
      return;

   int tradeCount = CountSlaveEATrades();

   if(tradeCount > MaxRunningTrades)
   {
      int excessTrades = tradeCount - MaxRunningTrades;
      Print("Max Trades Rule: ", tradeCount, " trades open, max allowed is ", MaxRunningTrades);

      // Close the newest trades (LIFO - Last In First Out)
      int closedCount = CloseNewestSlaveEATrades(excessTrades, "MAX TRADES VIOLATION");
      if(closedCount > 0)
      {
         Print("Max Trades Rule: Closed ", closedCount, " excess trade(s)");
      }
   }
}

//+------------------------------------------------------------------+
//| Check Time Interval Rule                                          |
//| Closes trades opened too quickly after the previous one           |
//+------------------------------------------------------------------+
void CheckTimeIntervalRule()
{
   if(!UseTimeInterval || totalIntervalSeconds <= 0)
      return;

   // Find trades opened within the forbidden interval
   datetime currentTime = TimeCurrent();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      // Only check trades from our slave EA
      if(OrderMagicNumber() != MagicNumber)
         continue;

      datetime orderOpenTime = OrderOpenTime();

      // Check if this order was opened too soon after the last recorded order
      if(lastOrderTime > 0 && orderOpenTime > lastOrderTime)
      {
         int timeDiff = (int)(orderOpenTime - lastOrderTime);

         if(timeDiff < totalIntervalSeconds)
         {
            // This trade violated the time interval rule
            Print("Time Interval Rule: Trade #", OrderTicket(),
                  " opened only ", timeDiff, "s after previous (min: ", totalIntervalSeconds, "s)");

            if(CloseTradeByTicket(OrderTicket(), "TIME INTERVAL VIOLATION"))
            {
               Print("Time Interval Rule: Closed trade #", OrderTicket());
            }
         }
         else
         {
            // Update last order time
            lastOrderTime = orderOpenTime;
         }
      }
      else if(orderOpenTime > lastOrderTime)
      {
         // First trade or newer trade found - update timestamp
         lastOrderTime = orderOpenTime;
      }
   }
}

//+------------------------------------------------------------------+
//| Count open trades from slave EA                                   |
//+------------------------------------------------------------------+
int CountSlaveEATrades()
{
   int count = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderMagicNumber() == MagicNumber)
         count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| Get the open time of the most recent slave EA order               |
//+------------------------------------------------------------------+
datetime GetLastOrderTime()
{
   datetime latestTime = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderMagicNumber() == MagicNumber)
      {
         if(OrderOpenTime() > latestTime)
            latestTime = OrderOpenTime();
      }
   }

   // Also check order history for recent orders
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;

      if(OrderMagicNumber() == MagicNumber)
      {
         if(OrderOpenTime() > latestTime)
            latestTime = OrderOpenTime();
      }
   }

   return latestTime;
}

//+------------------------------------------------------------------+
//| Close all trades from slave EA                                    |
//+------------------------------------------------------------------+
int CloseAllSlaveEATrades(string reason)
{
   int closedCount = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderMagicNumber() != MagicNumber)
         continue;

      if(CloseTradeByTicket(OrderTicket(), reason))
         closedCount++;
   }

   return closedCount;
}

//+------------------------------------------------------------------+
//| Close the N newest trades from slave EA (LIFO)                    |
//+------------------------------------------------------------------+
int CloseNewestSlaveEATrades(int count, string reason)
{
   if(count <= 0)
      return 0;

   // Build array of tickets sorted by open time (newest first)
   int tickets[];
   datetime openTimes[];
   int totalTrades = 0;

   // First pass: count and collect trades
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderMagicNumber() == MagicNumber)
         totalTrades++;
   }

   if(totalTrades == 0)
      return 0;

   ArrayResize(tickets, totalTrades);
   ArrayResize(openTimes, totalTrades);

   // Second pass: fill arrays
   int idx = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderMagicNumber() == MagicNumber)
      {
         tickets[idx] = OrderTicket();
         openTimes[idx] = OrderOpenTime();
         idx++;
      }
   }

   // Sort by open time (newest first) - simple bubble sort
   for(int i = 0; i < totalTrades - 1; i++)
   {
      for(int j = i + 1; j < totalTrades; j++)
      {
         if(openTimes[j] > openTimes[i])
         {
            // Swap
            datetime tempTime = openTimes[i];
            openTimes[i] = openTimes[j];
            openTimes[j] = tempTime;

            int tempTicket = tickets[i];
            tickets[i] = tickets[j];
            tickets[j] = tempTicket;
         }
      }
   }

   // Close the newest trades
   int closedCount = 0;
   for(int i = 0; i < count && i < totalTrades; i++)
   {
      if(CloseTradeByTicket(tickets[i], reason))
         closedCount++;
   }

   return closedCount;
}

//+------------------------------------------------------------------+
//| Close a trade by ticket number                                    |
//+------------------------------------------------------------------+
bool CloseTradeByTicket(int ticket, string reason)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
   {
      Print("Error: Could not select order #", ticket);
      return false;
   }

   string symbol = OrderSymbol();
   int orderType = OrderType();
   double lots = OrderLots();

   // Determine close price
   double closePrice;
   if(orderType == OP_BUY)
      closePrice = MarketInfo(symbol, MODE_BID);
   else if(orderType == OP_SELL)
      closePrice = MarketInfo(symbol, MODE_ASK);
   else
   {
      // Pending order - delete it
      if(OrderDelete(ticket))
      {
         Print("MASTER EA ACTION: Deleted pending order #", ticket, " | Reason: ", reason);
         return true;
      }
      else
      {
         Print("Error deleting pending order #", ticket, " | Error: ", GetLastError());
         return false;
      }
   }

   // Close market order
   if(OrderClose(ticket, lots, closePrice, 3))
   {
      Print("MASTER EA ACTION: Closed trade #", ticket, " | ", symbol, " | ",
            (orderType == OP_BUY ? "BUY" : "SELL"), " | ", lots, " lots | Reason: ", reason);
      return true;
   }
   else
   {
      Print("Error closing order #", ticket, " | Error: ", GetLastError());
      return false;
   }
}

//+------------------------------------------------------------------+
