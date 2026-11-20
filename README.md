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

### Volatility 50 (1s) Index

- Entry timeframe: M5
- Momentum bias timeframe: H4
- Proposed risk per trade: 12% of equity
- Target reward-to-risk ratio: 1:3

Risk warning: A 12% risk allocation is highly aggressive and can result in substantial drawdowns. Test with historical data and demo trading, and investigate lower risk settings before considering live deployment.