# Deriv Pattern Scanner for MT5

`DerivPatternScanner.mq5` is a multi-symbol Expert Advisor for Deriv synthetic indices. It scans for double bottoms/tops and inverse/head-and-shoulders patterns, waits for a neckline close, and enters only when momentum agrees and price retests a supply/demand candle zone.

## Strategy behavior

- Momentum bias is the change in the bias-timeframe EMA over the configured period, scaled by ATR. A neutral reading blocks entries.
- A zone is currently defined mechanically as the last opposing candle before an ATR-sized impulse. The stop is placed beyond that candle's range with a small ATR buffer.
- Take profit targets the nearest confirmed swing high for buys or swing low for sells. Set `InpRewardRiskMinimum` to filter targets that are too close.
- Position size uses `InpRiskPercent` of current equity and the symbol's tick value/size. Broker minimum volume and volume step are applied; trades are skipped if the calculated size is below minimum.
- The EA permits one position per symbol and magic number at a time.

## MT5 setup

1. Copy the EA into the terminal's `MQL5/Experts` folder and compile it in MetaEditor.
2. Add the exact Deriv symbols available in Market Watch to `InpSymbols`. Broker labels can vary. The defaults include Boom/Crash 300, 500, 1000, 1500, Volatility 25 (1s), Volatility 75 (1s), and Step Index; unavailable names are logged and should be removed or corrected.
3. In Strategy Tester, select this EA, enable the symbols in Market Watch, choose a sufficiently detailed tick model, and start a visual test to see the per-symbol dashboard on the tester chart.
4. The dashboard reports closed-trade count, win rate, net profit, profit factor, and latest scan status per symbol. A CSV with the same per-symbol results is written to the terminal Common Files folder as `DerivPatternScanner_results.csv` by default.

The dashboard and CSV are designed to compare instruments within one multi-symbol test. The EA does not claim that these pattern and zone definitions are profitable; use tester results and demo forward-testing to tune the inputs before live use.


## Example configuration for testing

The following is an example configuration to investigate in the MT5 Strategy Tester. It is not a recommendation for live trading.

## Configuration reference

The Expert Advisor exposes the following inputs in MT5:

| Input | Default | Purpose |
|---|---|---|
| `InpSymbols` | Boom/Crash indices, Volatility 25 (1s), Volatility 75 (1s), Step Index | Comma-separated list of symbols to scan. |
| `InpSignalTimeframe` | M15 | Timeframe used to identify trading patterns and entries. |
| `InpBiasTimeframe` | H1 | Higher timeframe used to determine momentum bias. |
| `InpScanSeconds` | 5 | Interval between scanning cycles, in seconds. |
| `InpLookbackBars` | 180 | Number of historical bars considered during analysis. |
| `InpPivotRadius` | 3 | Number of surrounding bars used when identifying swing points. |
| `InpMomentumPeriod` | 20 | Period used for momentum calculations. |
| `InpMinMomentumATR` | 0.15 | Minimum momentum threshold, measured in ATR units. |
| `InpATRPeriod` | 14 | Period used to calculate the Average True Range. |
| `InpPatternToleranceATR` | 0.35 | Allowed difference between pattern levels, measured in ATR units. |
| `InpMinPatternDepthATR` | 1.0 | Minimum pattern depth, measured in ATR units. |
| `InpZoneImpulseATR` | 1.2 | Minimum impulse size used when identifying supply and demand zones. |
| `InpZoneMaxAgeBars` | 80 | Maximum age of a zone, measured in bars. |
| `InpRiskPercent` | 0.50 | Percentage of equity used to calculate trade risk. |
| `InpRewardRiskMinimum` | 1.0 | Minimum reward-to-risk ratio required for an entry. |
| `InpMaxPositionsPerSymbol` | 1 | Maximum permitted positions per symbol. |
| `InpMagic` | 25112026 | Magic number used to identify the EA's trades. |
| `InpDeviationPoints` | 30 | Maximum permitted price deviation, in points. |
| `InpAllowLongs` | true | Enables buy trades. |
| `InpAllowShorts` | true | Enables sell trades. |
| `InpShowDashboard` | true | Enables or disables the on-chart dashboard. |
| `InpWriteCSV` | true | Enables or disables CSV reporting. |
| `InpCSVFile` | DerivPatternScanner_results.csv | CSV filename used for reporting. |

### Customising the symbols

The default symbol list does not include every Deriv synthetic index. To test another instrument, add its exact broker symbol to `InpSymbols`. Remove instruments you do not want the EA to scan.