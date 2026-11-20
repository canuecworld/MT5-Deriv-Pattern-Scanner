#property strict
#property version   "1.00"
#property description "Multi-symbol Deriv EA: momentum-filtered double bottoms/tops and head-and-shoulders with pullback entries."

#include <Trade/Trade.mqh>

input string          InpSymbols = "Boom 300 Index,Boom 500 Index,Boom 1000 Index,Boom 1500 Index,Crash 300 Index,Crash 500 Index,Crash 1000 Index,Crash 1500 Index,Volatility 25 (1s) Index,Volatility 75 (1s) Index,Step Index";
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_M15;
input ENUM_TIMEFRAMES InpBiasTimeframe = PERIOD_H1;
input int             InpScanSeconds = 5;
input int             InpLookbackBars = 180;
input int             InpPivotRadius = 3;
input int             InpMomentumPeriod = 20;
input double          InpMinMomentumATR = 0.15;
input int             InpATRPeriod = 14;
input double          InpPatternToleranceATR = 0.35;
input double          InpMinPatternDepthATR = 1.0;
input double          InpZoneImpulseATR = 1.2;
input int             InpZoneMaxAgeBars = 80;
input double          InpRiskPercent = 0.50;
input double          InpRewardRiskMinimum = 1.0;
input int             InpMaxPositionsPerSymbol = 1;
input ulong           InpMagic = 25112026;
input int             InpDeviationPoints = 30;
input bool            InpAllowLongs = true;
input bool            InpAllowShorts = true;
input bool            InpShowDashboard = true;
input bool            InpWriteCSV = true;
input string          InpCSVFile = "DerivPatternScanner_results.csv";

CTrade trade;

enum PatternType { PAT_NONE=0, PAT_DOUBLE_BOTTOM=1, PAT_INVERSE_HS=2, PAT_DOUBLE_TOP=-1, PAT_HEAD_SHOULDERS=-2 };
struct Pivot { int shift; double price; };
struct SymbolState
  {
   string name;
   datetime last_bar;
   int trades,wins,losses;
   double net_profit,gross_profit,gross_loss;
   string last_signal;
  };

SymbolState states[];
string symbols[];
int symbol_count=0;
int atr_handles[];
int bias_handles[];
int momentum_handles[];
string dashboard_prefix="DPS_";

int OnInit()
  {
   string raw[];
   int n=StringSplit(InpSymbols,',',raw);
   if(n<=0) return INIT_PARAMETERS_INCORRECT;
   ArrayResize(symbols,n); ArrayResize(states,n); ArrayResize(atr_handles,n); ArrayResize(bias_handles,n); ArrayResize(momentum_handles,n);
   for(int i=0;i<n;i++)
     {
      StringTrimLeft(raw[i]); StringTrimRight(raw[i]);
      if(raw[i]=="") continue;
      symbols[symbol_count]=raw[i];
      states[symbol_count].name=raw[i]; states[symbol_count].last_bar=0;
      states[symbol_count].trades=0; states[symbol_count].wins=0; states[symbol_count].losses=0;
      states[symbol_count].net_profit=0; states[symbol_count].gross_profit=0; states[symbol_count].gross_loss=0;
      states[symbol_count].last_signal="Waiting";
      if(!SymbolSelect(raw[i],true)) Print("Could not select symbol: ",raw[i],". Check the exact Market Watch name.");
      atr_handles[symbol_count]=iATR(raw[i],InpSignalTimeframe,InpATRPeriod);
      bias_handles[symbol_count]=iMA(raw[i],InpBiasTimeframe,InpMomentumPeriod,0,MODE_EMA,PRICE_CLOSE);
      momentum_handles[symbol_count]=iATR(raw[i],InpBiasTimeframe,InpATRPeriod);
      if(atr_handles[symbol_count]==INVALID_HANDLE || bias_handles[symbol_count]==INVALID_HANDLE || momentum_handles[symbol_count]==INVALID_HANDLE)
         Print("Indicator handle error for ",raw[i]);
      symbol_count++;
     }
   if(symbol_count==0) return INIT_PARAMETERS_INCORRECT;
   ArrayResize(symbols,symbol_count); ArrayResize(states,symbol_count); ArrayResize(atr_handles,symbol_count); ArrayResize(bias_handles,symbol_count); ArrayResize(momentum_handles,symbol_count);
   trade.SetExpertMagicNumber(InpMagic); trade.SetDeviationInPoints(InpDeviationPoints); trade.SetAsyncMode(false);
   EventSetTimer(MathMax(1,InpScanSeconds));
   if(InpShowDashboard) DrawDashboard();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i=0;i<symbol_count;i++)
     { if(atr_handles[i]!=INVALID_HANDLE) IndicatorRelease(atr_handles[i]); if(bias_handles[i]!=INVALID_HANDLE) IndicatorRelease(bias_handles[i]); if(momentum_handles[i]!=INVALID_HANDLE) IndicatorRelease(momentum_handles[i]); }
   ObjectsDeleteAll(0,dashboard_prefix);
   if(InpWriteCSV) WriteStatsCSV();
  }

void OnTick() { }

void OnTimer()
  {
   for(int i=0;i<symbol_count;i++) ScanSymbol(i);
   if(InpShowDashboard) DrawDashboard();
  }

void ScanSymbol(const int idx)
  {
   string sym=symbols[idx];
   datetime bar=iTime(sym,InpSignalTimeframe,0);
   if(bar<=0 || bar==states[idx].last_bar) return;
   states[idx].last_bar=bar;
   MqlRates rates[]; ArraySetAsSeries(rates,true);
   int copied=CopyRates(sym,InpSignalTimeframe,0,InpLookbackBars,rates);
   if(copied<60) { states[idx].last_signal="Insufficient history"; return; }
   double atrbuf[],emabuf[],biasatr[]; ArraySetAsSeries(atrbuf,true); ArraySetAsSeries(emabuf,true); ArraySetAsSeries(biasatr,true);
   if(CopyBuffer(atr_handles[idx],0,0,3,atrbuf)<3 || CopyBuffer(bias_handles[idx],0,0,InpMomentumPeriod+3,emabuf)<InpMomentumPeriod+3 || CopyBuffer(momentum_handles[idx],0,0,3,biasatr)<3)
     { states[idx].last_signal="Waiting for indicators"; return; }
   double atr=atrbuf[1]; if(atr<=0 || biasatr[1]<=0) return;
   double momentum=(emabuf[1]-emabuf[InpMomentumPeriod+1])/biasatr[1];
   int bias=(momentum>InpMinMomentumATR ? 1 : (momentum < -InpMinMomentumATR ? -1 : 0));
   int highs[],lows[]; ArrayResize(highs,0); ArrayResize(lows,0);
   FindPivots(rates,copied,highs,lows);
   int direction=0; PatternType pattern=PAT_NONE; int neckline_shift=-1; double neckline=0;
   if(bias>0 && InpAllowLongs && DetectLongPattern(rates,highs,lows,atr,pattern,neckline_shift,neckline)) direction=1;
   if(direction==0 && bias<0 && InpAllowShorts && DetectShortPattern(rates,highs,lows,atr,pattern,neckline_shift,neckline)) direction=-1;
   if(direction==0) { states[idx].last_signal=(bias==0 ? "No momentum bias" : "No confirmed pattern"); return; }
   if(HasPosition(sym)) { states[idx].last_signal="Position open"; return; }
   double zone_low,zone_high; int zone_shift;
   if(!FindRetestZone(rates,copied,direction,neckline_shift,atr,zone_low,zone_high,zone_shift)) { states[idx].last_signal="Waiting for supply/demand retest"; return; }
   double close1=rates[1].close;
   if(close1<zone_low || close1>zone_high) { states[idx].last_signal="Waiting for zone touch"; return; }
   double entry=(direction>0 ? SymbolInfoDouble(sym,SYMBOL_ASK) : SymbolInfoDouble(sym,SYMBOL_BID));
   if(entry<zone_low || entry>zone_high) { states[idx].last_signal="Price moved out of zone"; return; }
   double sl=(direction>0 ? zone_low-0.15*atr : zone_high+0.15*atr);
   double tp=FindNextTarget(rates,highs,lows,direction,entry,atr);
   if(tp<=0) { states[idx].last_signal="No valid swing target"; return; }
   double risk=MathAbs(entry-sl),reward=MathAbs(tp-entry);
   if(risk<=0 || reward/risk<InpRewardRiskMinimum) { states[idx].last_signal="Target below minimum R:R"; return; }
   double volume=CalculateVolume(sym,risk);
   if(volume<=0) { states[idx].last_signal="Invalid risk volume"; return; }
   int digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS); sl=NormalizeDouble(sl,digits); tp=NormalizeDouble(tp,digits);
   bool ok=false;
   if(direction>0) ok=trade.Buy(volume,sym,0,sl,tp,"DB/Inverse-HS retest");
   else ok=trade.Sell(volume,sym,0,sl,tp,"DT/H&S retest");
   states[idx].last_signal=(ok ? (direction>0 ? "BUY placed" : "SELL placed") : "Order rejected: "+trade.ResultRetcodeDescription());
   if(ok) Print(sym," ",states[idx].last_signal," pattern=",EnumToString(pattern)," lots=",DoubleToString(volume,2)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
  }

void FindPivots(MqlRates &r[],int count,int &highs[],int &lows[])
  {
   // Series arrays use larger shifts for older bars; walk old-to-new for pattern sequencing.
   for(int s=count-InpPivotRadius-1;s>=InpPivotRadius+1;s--)
     {
      bool ph=true,pl=true;
      for(int k=1;k<=InpPivotRadius;k++)
        { if(r[s].high<=r[s-k].high || r[s].high<r[s+k].high) ph=false; if(r[s].low>=r[s-k].low || r[s].low>r[s+k].low) pl=false; }
      if(ph) { int n=ArraySize(highs); ArrayResize(highs,n+1); highs[n]=s; }
      if(pl) { int n=ArraySize(lows); ArrayResize(lows,n+1); lows[n]=s; }
     }
  }

bool DetectLongPattern(MqlRates &r[],int &highs[],int &lows[],double atr,PatternType &kind,int &neckshift,double &neck)
  {
   int nl=ArraySize(lows),nh=ArraySize(highs); if(nl<2 || nh<1) return false;
   // Pivots are stored oldest to newest. Use the latest two lows for a double bottom.
   int a=lows[nl-2],b=lows[nl-1];
   int h=-1; double hprice=-DBL_MAX;
   for(int j=0;j<nh;j++) if(highs[j]>b && highs[j]<a) { h=highs[j]; hprice=r[h].high; }
   if(h>=0 && MathAbs(r[a].low-r[b].low)<=InpPatternToleranceATR*atr && hprice-MathMin(r[a].low,r[b].low)>=InpMinPatternDepthATR*atr)
     { kind=PAT_DOUBLE_BOTTOM; neckshift=b; neck=hprice; if(RecentBreakout(r,neck,1,b)) return true; }
   // Inverse H&S: three successive troughs with a lower central head and a neckline break.
   if(nl>=3)
     {
      int l=lows[nl-3],head=lows[nl-2],rs=lows[nl-1];
      if(l>head && head>rs && r[head].low<r[l].low && r[head].low<r[rs].low && MathAbs(r[l].low-r[rs].low)<=InpPatternToleranceATR*atr)
        {
         int n1=-1,n2=-1; double p1=0,p2=0;
         for(int j=0;j<nh;j++) { if(highs[j]>head && highs[j]<l) { n1=highs[j]; p1=r[n1].high; } if(highs[j]>rs && highs[j]<head) { n2=highs[j]; p2=r[n2].high; } }
         if(n1>=0 && n2>=0) { neckshift=rs; neck=(p1+p2)*0.5; if(neck-r[head].low>=InpMinPatternDepthATR*atr && RecentBreakout(r,neck,1,rs)) { kind=PAT_INVERSE_HS; return true; } }
        }
     }
   return false;
  }

bool DetectShortPattern(MqlRates &r[],int &highs[],int &lows[],double atr,PatternType &kind,int &neckshift,double &neck)
  {
   int nh=ArraySize(highs),nl=ArraySize(lows); if(nh<2 || nl<1) return false;
   int a=highs[nh-2],b=highs[nh-1];
   int l=-1; double lprice=DBL_MAX;
   for(int j=0;j<nl;j++) if(lows[j]>b && lows[j]<a) { l=lows[j]; lprice=r[l].low; }
   if(l>=0 && MathAbs(r[a].high-r[b].high)<=InpPatternToleranceATR*atr && MathMax(r[a].high,r[b].high)-lprice>=InpMinPatternDepthATR*atr)
     { kind=PAT_DOUBLE_TOP; neckshift=b; neck=lprice; if(RecentBreakout(r,neck,-1,b)) return true; }
   if(nh>=3)
     {
      int ls=highs[nh-3],head=highs[nh-2],rs=highs[nh-1];
      if(ls>head && head>rs && r[head].high>r[ls].high && r[head].high>r[rs].high && MathAbs(r[ls].high-r[rs].high)<=InpPatternToleranceATR*atr)
        {
         int n1=-1,n2=-1; double p1=0,p2=0;
         for(int j=0;j<nl;j++) { if(lows[j]>head && lows[j]<ls) { n1=lows[j]; p1=r[n1].low; } if(lows[j]>rs && lows[j]<head) { n2=lows[j]; p2=r[n2].low; } }
         if(n1>=0 && n2>=0) { neckshift=rs; neck=(p1+p2)*0.5; if(r[head].high-neck>=InpMinPatternDepthATR*atr && RecentBreakout(r,neck,-1,rs)) { kind=PAT_HEAD_SHOULDERS; return true; } }
        }
     }
   return false;
  }

bool RecentBreakout(MqlRates &r[],double neckline,int dir,int pattern_end_shift)
  {
   int limit=(int)MathMin(MathMin(12,ArraySize(r)-2),pattern_end_shift-1);
   for(int s=1;s<=limit;s++) if((dir>0 && r[s].close>neckline) || (dir<0 && r[s].close<neckline)) return true;
   return false;
  }

bool FindRetestZone(MqlRates &r[],int count,int dir,int broken_shift,double atr,double &zl,double &zh,int &zshift)
  {
   // The demand/supply zone is the last opposing candle preceding a decisive ATR-sized impulse.
   int limit=(int)MathMin(InpZoneMaxAgeBars,broken_shift);
   for(int s=2;s<=limit && s<count-2;s++)
     {
      bool opposing=(dir>0 ? r[s].close<r[s].open : r[s].close>r[s].open);
      double impulse=(dir>0 ? r[s-1].close-r[s].low : r[s].high-r[s-1].close);
      if(opposing && impulse>=InpZoneImpulseATR*atr)
        { zl=r[s].low; zh=r[s].high; zshift=s; return true; }
     }
   return false;
  }

double FindNextTarget(MqlRates &r[],int &highs[],int &lows[],int dir,double entry,double atr)
  {
   double target=0;
   if(dir>0) { for(int i=0;i<ArraySize(highs);i++) if(r[highs[i]].high>entry && (target==0 || r[highs[i]].high<target)) target=r[highs[i]].high; }
   else { for(int i=0;i<ArraySize(lows);i++) if(r[lows[i]].low<entry && (target==0 || r[lows[i]].low>target)) target=r[lows[i]].low; }
   // If the target swing was consumed on the breakout, use the latest confirmed outer swing.
   if(target==0 && dir>0 && ArraySize(highs)>0) target=r[highs[ArraySize(highs)-1]].high;
   if(target==0 && dir<0 && ArraySize(lows)>0) target=r[lows[ArraySize(lows)-1]].low;
   if((dir>0 && target<=entry+0.2*atr) || (dir<0 && target>=entry-0.2*atr)) return 0;
   return target;
  }

bool HasPosition(string sym)
  {
   for(int i=PositionsTotal()-1;i>=0;i--) { ulong ticket=PositionGetTicket(i); if(ticket>0 && PositionGetString(POSITION_SYMBOL)==sym && (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic) return true; }
   return false;
  }

double CalculateVolume(string sym,double risk_price)
  {
   double equity=AccountInfoDouble(ACCOUNT_EQUITY),risk_money=equity*InpRiskPercent/100.0;
   double tick_value=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE),tick_size=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   if(tick_value<=0 || tick_size<=0 || risk_price<=0) return 0;
   double loss_per_lot=(risk_price/tick_size)*tick_value; if(loss_per_lot<=0) return 0;
   double vol=risk_money/loss_per_lot,step=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   double vmin=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN),vmax=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   vol=MathFloor(vol/step)*step; vol=MathMin(vmax,vol);
   if(vol<vmin) return 0;
   return NormalizeDouble(vol,VolumeDigits(step));
  }

int VolumeDigits(double step) { int d=0; while(d<8 && MathAbs(step-NormalizeDouble(step,d))>1e-9) d++; return d; }

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0 || !HistoryDealSelect(trans.deal)) return;
   if((ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpMagic || HistoryDealGetInteger(trans.deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;
   string sym=HistoryDealGetString(trans.deal,DEAL_SYMBOL); double p=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+HistoryDealGetDouble(trans.deal,DEAL_SWAP)+HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
   for(int i=0;i<symbol_count;i++) if(states[i].name==sym) { states[i].trades++; states[i].net_profit+=p; if(p>=0) { states[i].wins++; states[i].gross_profit+=p; } else { states[i].losses++; states[i].gross_loss+=MathAbs(p); } break; }
   if(InpWriteCSV) WriteStatsCSV();
  }

void WriteStatsCSV()
  {
   int f=FileOpen(InpCSVFile,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,','); if(f==INVALID_HANDLE) { Print("CSV open failed: ",GetLastError()); return; }
   FileWrite(f,"Symbol","Trades","Wins","Losses","Win rate %","Net profit","Profit factor","Last signal");
   for(int i=0;i<symbol_count;i++) { double wr=(states[i].trades>0 ? 100.0*states[i].wins/states[i].trades : 0); double pf=(states[i].gross_loss>0 ? states[i].gross_profit/states[i].gross_loss : 0); FileWrite(f,states[i].name,states[i].trades,states[i].wins,states[i].losses,DoubleToString(wr,1),DoubleToString(states[i].net_profit,2),DoubleToString(pf,2),states[i].last_signal); }
   FileClose(f);
  }

void DrawDashboard()
  {
   int x=12,y=22,row=18; string title=dashboard_prefix+"title";
   SetLabel(title,x,y,"DERIV PATTERN SCANNER | "+EnumToString(InpSignalTimeframe)+" | momentum: "+EnumToString(InpBiasTimeframe),clrWhite,10); y+=row+3;
   SetLabel(dashboard_prefix+"header",x,y,"INSTRUMENT                 TRADES    WIN%       NET P/L       PROFIT FACTOR     STATUS",clrSilver,9); y+=row;
   for(int i=0;i<symbol_count;i++)
     {
      double wr=(states[i].trades>0 ? 100.0*states[i].wins/states[i].trades : 0); double pf=(states[i].gross_loss>0 ? states[i].gross_profit/states[i].gross_loss : 0);
      string line=StringFormat("%-27s %5d %7.1f%% %12.2f %12.2f   %s",states[i].name,states[i].trades,wr,states[i].net_profit,pf,states[i].last_signal);
      color c=(states[i].net_profit>0 ? clrLime : (states[i].net_profit<0 ? clrTomato : clrWhite));
      SetLabel(dashboard_prefix+IntegerToString(i),x,y,line,c,9); y+=row;
     }
   ChartRedraw(0);
  }

void SetLabel(string name,int x,int y,string text,color c,int size)
  {
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER); ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_COLOR,c); ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size); ObjectSetString(0,name,OBJPROP_FONT,"Consolas"); ObjectSetString(0,name,OBJPROP_TEXT,text);
  }
