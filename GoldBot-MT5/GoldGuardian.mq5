//+------------------------------------------------------------------+
//|                                               GoldGuardian.mq5   |
//|  Expert Advisor XAUUSD (Or) pour MetaTrader 5                    |
//|                                                                  |
//|  Stratégie : suivi de tendance multi-timeframe (H4 / H1 / M15)   |
//|  avec entrée sur repli (pullback), filtre d'actualités           |
//|  économiques (calendrier MQL5), filtre de session, filtre de     |
//|  spread, gestion du risque en % et protections "Prop Firm"       |
//|  (perte journalière max, drawdown max, nb de trades max).        |
//|                                                                  |
//|  AVERTISSEMENT : aucun gain n'est garanti. Testez d'abord en     |
//|  compte démo et dans le testeur de stratégie.                    |
//+------------------------------------------------------------------+
#property copyright "GoldGuardian"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//==================================================================
// PARAMÈTRES
//==================================================================
input group "=== Risque ==="
input double InpRiskPercent        = 0.5;   // Risque par trade (% de l'équité)
input double InpMaxLot             = 5.0;   // Lot maximum par trade
input int    InpMaxOpenPositions   = 1;     // Positions ouvertes max (ce robot)
input int    InpMaxTradesPerDay    = 3;     // Trades max par jour
input int    InpMaxConsecLosses    = 2;     // Pertes consécutives avant arrêt du jour

input group "=== Protections Prop Firm ==="
input double InpDailyLossLimitPct  = 4.0;   // Perte journalière max (%) - mettre sous la règle de la prop firm
input double InpMaxDrawdownPct     = 8.0;   // Drawdown total max (%) depuis le solde initial
input double InpInitialBalance     = 0.0;   // Solde initial du challenge (0 = auto)
input double InpDailyProfitStopPct = 0.0;   // Arrêt après X% de gain du jour (0 = désactivé)

input group "=== Stratégie ==="
input ENUM_TIMEFRAMES InpBiasTF    = PERIOD_H4;  // Timeframe de biais
input ENUM_TIMEFRAMES InpTrendTF   = PERIOD_H1;  // Timeframe de tendance
input ENUM_TIMEFRAMES InpEntryTF   = PERIOD_M15; // Timeframe d'entrée
input int    InpEmaFast            = 21;    // EMA rapide
input int    InpEmaSlow            = 50;    // EMA lente
input int    InpEmaTrend           = 200;   // EMA de tendance
input int    InpRsiPeriod          = 14;    // Période RSI
input int    InpAtrPeriod          = 14;    // Période ATR
input int    InpAdxPeriod          = 14;    // Période ADX
input double InpMinAdx             = 20.0;  // ADX minimum (force de tendance)
input double InpSlAtrMult          = 1.5;   // Stop loss = ATR x
input double InpMaxSlAtrMult       = 3.0;   // Stop loss max = ATR x (sinon pas de trade)
input double InpTpRR               = 2.5;   // Take profit final (ratio risque/rendement)

input group "=== Gestion de position ==="
input double InpPartialAtR         = 1.0;   // Prise partielle à X R
input double InpPartialPct         = 50.0;  // % fermé à la prise partielle
input double InpBreakEvenBufferAtr = 0.1;   // Break-even + ATR x (couvre les frais)
input double InpTrailAtrMult       = 1.5;   // Trailing stop = ATR x (après partiel)

input group "=== Filtres ==="
input int    InpSessionStartHour   = 8;     // Début session (heure SERVEUR)
input int    InpSessionEndHour     = 20;    // Fin session (heure SERVEUR)
input double InpMaxSpreadPrice     = 0.50;  // Spread max (en $ sur l'or, ex 0.50)
input bool   InpUseNewsFilter      = true;  // Filtre actualités (calendrier MT5)
input int    InpNewsMinutesBefore  = 45;    // Pas de trade X min avant news
input int    InpNewsMinutesAfter   = 45;    // Pas de trade X min après news
input bool   InpNewsIncludeMedium  = false; // Inclure news d'importance moyenne
input bool   InpCloseBeforeNews    = false; // Fermer les positions avant une news forte
input bool   InpCloseFriday        = true;  // Tout fermer le vendredi soir
input int    InpFridayCloseHour    = 20;    // Heure de fermeture vendredi (SERVEUR)

input group "=== Divers ==="
input long   InpMagic              = 7770777; // Numéro magique
input bool   InpPushNotifications  = true;  // Notifications push vers l'iPhone (app MT5)
input bool   InpShowDashboard      = true;  // Afficher le tableau de bord

//==================================================================
// VARIABLES GLOBALES
//==================================================================
CTrade trade;

int hBiasEma, hTrendEmaSlow, hTrendEmaTrend, hAdx;
int hEmaFast, hEmaSlow, hRsi, hAtr;

datetime g_lastEntryBar = 0;
string   g_status       = "Démarrage";
bool     g_haltedToday  = false;
datetime g_haltDay      = 0;
string   g_prefix;

//==================================================================
// OUTILS
//==================================================================
void Notify(const string msg)
{
   string full = "GoldGuardian " + _Symbol + ": " + msg;
   Print(full);
   if(InpPushNotifications && !MQLInfoInteger(MQL_TESTER))
      SendNotification(full);
}

double GetBuf(const int handle, const int buffer, const int shift)
{
   double v[];
   ArraySetAsSeries(v, true);
   if(CopyBuffer(handle, buffer, shift, 1, v) != 1) return EMPTY_VALUE;
   return v[0];
}

datetime DayStart()
{
   return iTime(_Symbol, PERIOD_D1, 0);
}

string GVName(const string key)
{
   return g_prefix + key;
}

//--- Équité de référence du jour (pour la perte journalière)
double DayReference()
{
   MqlDateTime t; TimeToStruct(DayStart(), t);
   string name = GVName(StringFormat("D%04d%02d%02d", t.year, t.mon, t.day));
   if(!GlobalVariableCheck(name))
   {
      double ref = MathMax(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
      GlobalVariableSet(name, ref);
   }
   return GlobalVariableGet(name);
}

//--- Solde initial (pour le drawdown max)
double InitialBalance()
{
   if(InpInitialBalance > 0) return InpInitialBalance;
   string name = GVName("INIT");
   if(!GlobalVariableCheck(name))
      GlobalVariableSet(name, AccountInfoDouble(ACCOUNT_BALANCE));
   return GlobalVariableGet(name);
}

bool IsMine()
{
   return PositionGetString(POSITION_SYMBOL) == _Symbol &&
          PositionGetInteger(POSITION_MAGIC) == InpMagic;
}

int CountMyPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk > 0 && PositionSelectByTicket(tk) && IsMine()) n++;
   }
   return n;
}

void CloseAll(const string reason)
{
   bool any = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk > 0 && PositionSelectByTicket(tk) && IsMine())
      {
         if(trade.PositionClose(tk)) any = true;
      }
   }
   if(any) Notify("Positions fermées : " + reason);
}

//--- Statistiques du jour depuis l'historique (robuste aux redémarrages)
void TodayStats(int &tradesToday, int &consecLosses)
{
   tradesToday  = 0;
   consecLosses = 0;
   if(!HistorySelect(DayStart(), TimeCurrent() + 60)) return;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic) continue;

      long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN)
         tradesToday++;
      else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      {
         double pl = HistoryDealGetDouble(d, DEAL_PROFIT) +
                     HistoryDealGetDouble(d, DEAL_SWAP) +
                     HistoryDealGetDouble(d, DEAL_COMMISSION);
         if(pl < 0) consecLosses++;
         else if(pl > 0) consecLosses = 0;
      }
   }
}

//==================================================================
// FILTRE ACTUALITÉS (calendrier économique intégré à MT5)
//==================================================================
bool NewsBlocked(string &eventName)
{
   eventName = "";
   if(!InpUseNewsFilter) return false;
   if(MQLInfoInteger(MQL_TESTER)) return false; // calendrier indisponible en backtest

   // Cache : on n'interroge le calendrier qu'une fois par minute
   static datetime lastCheck = 0;
   static bool     lastResult = false;
   static string   lastName = "";
   datetime now  = TimeTradeServer();
   if(now - lastCheck < 60) { eventName = lastName; return lastResult; }
   lastCheck = now; lastResult = false; lastName = "";


   datetime from = now - InpNewsMinutesAfter * 60;
   datetime to   = now + InpNewsMinutesBefore * 60;

   MqlCalendarValue values[];
   int n = CalendarValueHistory(values, from, to, NULL, "USD");
   for(int i = 0; i < n; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      bool important = (ev.importance == CALENDAR_IMPORTANCE_HIGH) ||
                       (InpNewsIncludeMedium && ev.importance == CALENDAR_IMPORTANCE_MODERATE);
      if(important)
      {
         eventName = ev.name + " @ " + TimeToString(values[i].time, TIME_MINUTES);
         lastName = eventName; lastResult = true;
         return true;
      }
   }
   return false;
}

//==================================================================
// PROTECTIONS DU COMPTE
//==================================================================
// Renvoie false si le trading doit être stoppé.
bool AccountGuards()
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayRef  = DayReference();
   double initBal = InitialBalance();

   // Réinitialiser l'arrêt journalier au changement de jour
   if(g_haltedToday && g_haltDay != DayStart()) g_haltedToday = false;

   // Drawdown max (définitif tant que l'EA n'est pas relancé manuellement)
   if(InpMaxDrawdownPct > 0 && equity <= initBal * (1.0 - InpMaxDrawdownPct / 100.0))
   {
      if(CountMyPositions() > 0) CloseAll("drawdown max atteint");
      g_status = "STOP : drawdown max atteint";
      return false;
   }

   // Perte journalière max
   double dayLoss = dayRef - equity;
   if(InpDailyLossLimitPct > 0 && dayLoss >= dayRef * InpDailyLossLimitPct / 100.0)
   {
      if(CountMyPositions() > 0) CloseAll("perte journalière max atteinte");
      if(!g_haltedToday) Notify("Arrêt pour aujourd'hui : perte journalière max");
      g_haltedToday = true; g_haltDay = DayStart();
   }

   // Objectif de gain journalier
   if(InpDailyProfitStopPct > 0 && (equity - dayRef) >= dayRef * InpDailyProfitStopPct / 100.0
      && CountMyPositions() == 0)
   {
      if(!g_haltedToday) Notify("Objectif journalier atteint, pause jusqu'à demain");
      g_haltedToday = true; g_haltDay = DayStart();
   }

   if(g_haltedToday)
   {
      g_status = "Pause jusqu'à demain";
      return false;
   }
   return true;
}

//==================================================================
// CALCUL DU LOT
//==================================================================
double CalcLot(const double slDistance)
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double step      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot    = MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), InpMaxLot);
   if(tickValue <= 0 || tickSize <= 0 || step <= 0 || slDistance <= 0) return 0;

   double riskMoney  = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   double lossPerLot = slDistance / tickSize * tickValue;
   double lots       = riskMoney / lossPerLot;

   lots = MathFloor(lots / step) * step;
   if(lots < minLot) return 0;          // risque trop petit pour le lot minimum : on ne force pas
   if(lots > maxLot) lots = maxLot;
   return NormalizeDouble(lots, 2);
}

//==================================================================
// SIGNAL D'ENTRÉE
//==================================================================
// +1 = achat, -1 = vente, 0 = rien
int GetSignal(double &atr)
{
   atr = GetBuf(hAtr, 0, 1);
   double biasEma   = GetBuf(hBiasEma, 0, 1);
   double trendSlow = GetBuf(hTrendEmaSlow, 0, 1);
   double trendBig  = GetBuf(hTrendEmaTrend, 0, 1);
   double adx       = GetBuf(hAdx, 0, 1);
   double emaFast   = GetBuf(hEmaFast, 0, 1);
   double emaSlow   = GetBuf(hEmaSlow, 0, 1);
   double rsi1      = GetBuf(hRsi, 0, 1);
   double rsi2      = GetBuf(hRsi, 0, 2);

   if(atr == EMPTY_VALUE || biasEma == EMPTY_VALUE || trendSlow == EMPTY_VALUE ||
      trendBig == EMPTY_VALUE || adx == EMPTY_VALUE || emaFast == EMPTY_VALUE ||
      emaSlow == EMPTY_VALUE || rsi1 == EMPTY_VALUE || rsi2 == EMPTY_VALUE)
      return 0;

   double biasClose  = iClose(_Symbol, InpBiasTF, 1);
   double trendClose = iClose(_Symbol, InpTrendTF, 1);
   double o = iOpen(_Symbol, InpEntryTF, 1);
   double h = iHigh(_Symbol, InpEntryTF, 1);
   double l = iLow(_Symbol, InpEntryTF, 1);
   double c = iClose(_Symbol, InpEntryTF, 1);

   if(adx < InpMinAdx) { g_status = "Tendance trop faible (ADX)"; return 0; }

   // --- ACHAT : tendance haussière sur les 3 unités de temps + repli sur EMA rapide
   bool upBias   = biasClose > biasEma;
   bool upTrend  = trendSlow > trendBig && trendClose > trendSlow;
   bool upStack  = emaFast > emaSlow;
   bool upPull   = l <= emaFast && c > emaFast && c > o;          // mèche dans la zone, clôture au-dessus
   bool upRsi    = rsi1 > 45 && rsi1 < 70 && rsi1 > rsi2;
   bool upNotExt = (c - emaSlow) < 1.5 * atr;                      // pas trop étiré

   if(upBias && upTrend && upStack && upPull && upRsi && upNotExt) return +1;

   // --- VENTE : symétrique
   bool dnBias   = biasClose < biasEma;
   bool dnTrend  = trendSlow < trendBig && trendClose < trendSlow;
   bool dnStack  = emaFast < emaSlow;
   bool dnPull   = h >= emaFast && c < emaFast && c < o;
   bool dnRsi    = rsi1 < 55 && rsi1 > 30 && rsi1 < rsi2;
   bool dnNotExt = (emaSlow - c) < 1.5 * atr;

   if(dnBias && dnTrend && dnStack && dnPull && dnRsi && dnNotExt) return -1;

   g_status = "En attente d'un signal";
   return 0;
}

//==================================================================
// OUVERTURE
//==================================================================
void TryEnter()
{
   // Une seule analyse par nouvelle bougie d'entrée
   datetime bar = iTime(_Symbol, InpEntryTF, 0);
   if(bar == g_lastEntryBar) return;
   g_lastEntryBar = bar;

   if(CountMyPositions() >= InpMaxOpenPositions) { g_status = "Position en cours"; return; }

   int tradesToday, consecLosses;
   TodayStats(tradesToday, consecLosses);
   if(tradesToday >= InpMaxTradesPerDay)  { g_status = "Nb max de trades du jour atteint"; return; }
   if(consecLosses >= InpMaxConsecLosses) { g_status = "Trop de pertes consécutives, pause"; return; }

   MqlDateTime t; TimeToStruct(TimeTradeServer(), t);
   if(t.hour < InpSessionStartHour || t.hour >= InpSessionEndHour) { g_status = "Hors session"; return; }
   if(InpCloseFriday && t.day_of_week == 5 && t.hour >= InpFridayCloseHour - 2) { g_status = "Fin de semaine"; return; }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask - bid > InpMaxSpreadPrice) { g_status = "Spread trop large"; return; }

   string ev;
   if(NewsBlocked(ev)) { g_status = "News : " + ev; return; }

   double atr;
   int sig = GetSignal(atr);
   if(sig == 0) return;

   // Stop loss : sous/sur le dernier swing ou ATR x mult (le plus large), plafonné
   double swingLow  = iLow(_Symbol, InpEntryTF, iLowest(_Symbol, InpEntryTF, MODE_LOW, 5, 1));
   double swingHigh = iHigh(_Symbol, InpEntryTF, iHighest(_Symbol, InpEntryTF, MODE_HIGH, 5, 1));
   double entry, sl, tp, dist;

   if(sig > 0)
   {
      entry = ask;
      sl    = MathMin(swingLow - 0.2 * atr, entry - InpSlAtrMult * atr);
      dist  = entry - sl;
   }
   else
   {
      entry = bid;
      sl    = MathMax(swingHigh + 0.2 * atr, entry + InpSlAtrMult * atr);
      dist  = sl - entry;
   }

   if(dist > InpMaxSlAtrMult * atr) { g_status = "Stop trop large, signal ignoré"; return; }

   double stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(dist < stopsLevel) dist = stopsLevel + _Point;

   tp = (sig > 0) ? entry + dist * InpTpRR : entry - dist * InpTpRR;
   sl = NormalizeDouble((sig > 0) ? entry - dist : entry + dist, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   double lots = CalcLot(dist);
   if(lots <= 0) { g_status = "Lot calculé trop petit (augmentez le capital ou le risque)"; return; }

   // Sécurité prop firm : la perte potentielle ne doit pas dépasser la limite du jour
   double dayRef    = DayReference();
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossSoFar = MathMax(0.0, dayRef - equity);
   double riskMoney = dist / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) *
                      SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) * lots;
   if(InpDailyLossLimitPct > 0 && lossSoFar + riskMoney > dayRef * InpDailyLossLimitPct / 100.0)
   {
      g_status = "Trade refusé : risquerait de dépasser la perte journalière";
      return;
   }

   bool ok = (sig > 0) ? trade.Buy(lots, _Symbol, 0, sl, tp, "GoldGuardian")
                       : trade.Sell(lots, _Symbol, 0, sl, tp, "GoldGuardian");
   if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED))
   {
      // On mémorise la distance de risque initiale (1R) pour la gestion
      ulong posTicket = trade.ResultOrder();
      GlobalVariableSet(GVName("R" + (string)posTicket), dist);
      Notify(StringFormat("%s %.2f lots @ %s | SL %s | TP %s",
             sig > 0 ? "ACHAT" : "VENTE", lots,
             DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits)));
      g_status = "Trade ouvert";
   }
   else
   {
      Print("Échec ouverture : ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
}

//==================================================================
// GESTION DES POSITIONS OUVERTES
//==================================================================
void ManagePositions()
{
   double atr = GetBuf(hAtr, 0, 1);
   if(atr == EMPTY_VALUE) return;

   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk) || !IsMine()) continue;

      long   type  = PositionGetInteger(POSITION_TYPE);
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      double vol   = PositionGetDouble(POSITION_VOLUME);
      double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      string rName = GVName("R" + (string)tk);
      double R = GlobalVariableCheck(rName) ? GlobalVariableGet(rName) : MathAbs(open - sl);
      if(R <= 0) continue;

      double profitDist = (type == POSITION_TYPE_BUY) ? price - open : open - price;
      string pName = GVName("P" + (string)tk);
      bool partialDone = GlobalVariableCheck(pName);

      // 1) Prise partielle + break-even
      if(!partialDone && profitDist >= InpPartialAtR * R)
      {
         double closeVol = MathFloor(vol * InpPartialPct / 100.0 / step) * step;
         if(closeVol >= minLot && vol - closeVol >= minLot)
         {
            if(trade.PositionClosePartial(tk, closeVol))
               Notify(StringFormat("Prise partielle %.2f lots (+%.1fR)", closeVol, profitDist / R));
         }
         double be = (type == POSITION_TYPE_BUY) ? open + InpBreakEvenBufferAtr * atr
                                                 : open - InpBreakEvenBufferAtr * atr;
         be = NormalizeDouble(be, _Digits);
         bool better = (type == POSITION_TYPE_BUY) ? (be > sl) : (sl == 0 || be < sl);
         bool valid  = (type == POSITION_TYPE_BUY) ? (price - be > stopsLevel) : (be - price > stopsLevel);
         if(better && valid && PositionSelectByTicket(tk))
            if(trade.PositionModify(tk, be, tp)) sl = be;
         GlobalVariableSet(pName, 1);
         partialDone = true;
      }

      // 2) Trailing stop ATR après la prise partielle
      if(partialDone && PositionSelectByTicket(tk))
      {
         double newSl = (type == POSITION_TYPE_BUY) ? price - InpTrailAtrMult * atr
                                                    : price + InpTrailAtrMult * atr;
         newSl = NormalizeDouble(newSl, _Digits);
         bool better = (type == POSITION_TYPE_BUY) ? (newSl > sl + _Point) : (sl == 0 || newSl < sl - _Point);
         bool valid  = (type == POSITION_TYPE_BUY) ? (price - newSl > stopsLevel) : (newSl - price > stopsLevel);
         if(better && valid) trade.PositionModify(tk, newSl, tp);
      }
   }
}

//--- Nettoyage des variables globales des positions fermées
void CleanupGlobals()
{
   int total = GlobalVariablesTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      string name = GlobalVariableName(i);
      if(StringFind(name, g_prefix) != 0) continue;
      string rest = StringSubstr(name, StringLen(g_prefix));
      string kind = StringSubstr(rest, 0, 1);
      if(kind != "R" && kind != "P") continue;
      ulong tk = (ulong)StringToInteger(StringSubstr(rest, 1));
      if(tk > 0 && !PositionSelectByTicket(tk)) GlobalVariableDel(name);
   }
}

//==================================================================
// TABLEAU DE BORD
//==================================================================
void Dashboard()
{
   if(!InpShowDashboard) return;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayRef = DayReference();
   double init   = InitialBalance();
   int tradesToday, consec;
   TodayStats(tradesToday, consec);

   string acc = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO) ? "DÉMO" :
                (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_CONTEST) ? "CONCOURS" : "RÉEL";

   Comment(StringFormat(
      "GoldGuardian v1.00  [%s]  %s\n"
      "Statut : %s\n"
      "Équité : %.2f | P/L jour : %.2f (%.2f%%)\n"
      "Drawdown total : %.2f%% / max %.1f%%\n"
      "Trades aujourd'hui : %d / %d | Pertes consécutives : %d\n"
      "Spread : %.2f",
      acc, _Symbol, g_status, equity,
      equity - dayRef, dayRef > 0 ? (equity - dayRef) / dayRef * 100.0 : 0.0,
      init > 0 ? MathMax(0.0, (init - equity) / init * 100.0) : 0.0, InpMaxDrawdownPct,
      tradesToday, InpMaxTradesPerDay, consec,
      SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)));
}

//==================================================================
// ÉVÉNEMENTS MT5
//==================================================================
int OnInit()
{
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
      Print("Attention : ce robot est conçu pour l'OR (XAUUSD). Symbole actuel : ", _Symbol);

   g_prefix = StringFormat("GG_%I64d_%I64d_", AccountInfoInteger(ACCOUNT_LOGIN), InpMagic);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFillingBySymbol(_Symbol);

   hBiasEma       = iMA(_Symbol, InpBiasTF,  InpEmaTrend, 0, MODE_EMA, PRICE_CLOSE);
   hTrendEmaSlow  = iMA(_Symbol, InpTrendTF, InpEmaSlow,  0, MODE_EMA, PRICE_CLOSE);
   hTrendEmaTrend = iMA(_Symbol, InpTrendTF, InpEmaTrend, 0, MODE_EMA, PRICE_CLOSE);
   hAdx           = iADX(_Symbol, InpTrendTF, InpAdxPeriod);
   hEmaFast       = iMA(_Symbol, InpEntryTF, InpEmaFast,  0, MODE_EMA, PRICE_CLOSE);
   hEmaSlow       = iMA(_Symbol, InpEntryTF, InpEmaSlow,  0, MODE_EMA, PRICE_CLOSE);
   hRsi           = iRSI(_Symbol, InpEntryTF, InpRsiPeriod, PRICE_CLOSE);
   hAtr           = iATR(_Symbol, InpEntryTF, InpAtrPeriod);

   if(hBiasEma == INVALID_HANDLE || hTrendEmaSlow == INVALID_HANDLE || hTrendEmaTrend == INVALID_HANDLE ||
      hAdx == INVALID_HANDLE || hEmaFast == INVALID_HANDLE || hEmaSlow == INVALID_HANDLE ||
      hRsi == INVALID_HANDLE || hAtr == INVALID_HANDLE)
   {
      Print("Erreur de création des indicateurs");
      return INIT_FAILED;
   }

   InitialBalance();
   DayReference();
   EventSetTimer(60);
   Notify("Robot démarré sur le compte " + (string)AccountInfoInteger(ACCOUNT_LOGIN));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   IndicatorRelease(hBiasEma);  IndicatorRelease(hTrendEmaSlow); IndicatorRelease(hTrendEmaTrend);
   IndicatorRelease(hAdx);      IndicatorRelease(hEmaFast);      IndicatorRelease(hEmaSlow);
   IndicatorRelease(hRsi);      IndicatorRelease(hAtr);
   Comment("");
}

void OnTimer()
{
   CleanupGlobals();
}

void OnTick()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      g_status = "Trading auto désactivé (bouton Algo Trading)";
      Dashboard();
      return;
   }

   bool canTrade = AccountGuards();

   // Fermeture du vendredi soir
   MqlDateTime t; TimeToStruct(TimeTradeServer(), t);
   if(InpCloseFriday && t.day_of_week == 5 && t.hour >= InpFridayCloseHour && CountMyPositions() > 0)
      CloseAll("fermeture du vendredi");

   // Fermeture avant news forte (optionnel)
   if(InpCloseBeforeNews && CountMyPositions() > 0)
   {
      string ev;
      if(NewsBlocked(ev)) CloseAll("news imminente : " + ev);
   }

   ManagePositions();
   if(canTrade) TryEnter();
   Dashboard();
}
//+------------------------------------------------------------------+
