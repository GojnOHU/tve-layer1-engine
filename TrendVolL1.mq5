#property strict
#property script_show_inputs

enum EMetricStatus
{
   METRIC_VALID,
   METRIC_UNAVAILABLE,
   METRIC_INSUFFICIENT_HISTORY,
   METRIC_INVALID_INPUT,
   METRIC_CALCULATION_ERROR
};

struct SMetric
{
   double value;
   bool valid;
   EMetricStatus status;
   int lookback_bars;
   int sample_bars;
};

struct STrendVolConfig
{
   int trend_1m_bars;
   int trend_3m_bars;
   int trend_6m_bars;
   int trend_12m_bars;

   int ema_fast_bars;
   int ema_slow_bars;

   int atr_short_bars;
   int atr_long_bars;

   int breakout_bars;

   int volatility_rank_bars;
   int volume_bars;
};

struct STrendVolL1Result
{
   string          symbol;
   ENUM_TIMEFRAMES timeframe;
   datetime        closed_bar_time;
   int             source_shift;
   int             source_bar_count;
   int             required_bar_count;

   bool            series_synchronized;
   bool            calculation_valid;
   EMetricStatus   overall_status;

   double log_return_1m;
   double log_return_3m;
   double log_return_6m;
   double log_return_12m;

   double trend_slope_3m;
   double trend_slope_6m;
   double trend_slope_12m;

   double trend_tstat_3m;
   double trend_tstat_6m;
   double trend_tstat_12m;

   double trend_r2_3m;
   double trend_r2_6m;
   double trend_r2_12m;

   double efficiency_ratio_3m;
   double efficiency_ratio_6m;
   double efficiency_ratio_12m;

   double ema_fast;
   double ema_slow;
   double ema_spread_pct;

   double true_range;
   double atr_short;
   double atr_long;
   double atr_short_pct_price;
   double atr_long_pct_price;
   double atr_expansion_ratio;
   double tr_to_atr_ratio;

   double realized_vol_3m;
   double realized_vol_12m;
   double realized_vol_ratio;

   double atr_percentile_rank;
   double realized_vol_percentile_rank;

   double donchian_high;
   double donchian_low;
   double donchian_width;
   double donchian_width_pct_price;
   double donchian_width_atr;

   double breakout_distance_up_atr;
   double breakout_distance_down_atr;
   int    breakout_side;

   double close_location_value;
   double body_fraction;

   long   tick_volume;
   double tick_volume_ratio;

   long   real_volume;
   double real_volume_ratio;
   EMetricStatus real_volume_status;

   string methodology_id;
   string engine_version;
};

input bool InProcessAllTimeframes = true;
input bool InUseChartSymbol = true;
input string InSymbol = "";
input ENUM_TIMEFRAMES InTimeframe = PERIOD_D1;

string TimeframeToString(ENUM_TIMEFRAMES timeframe)
{
   switch(timeframe)
   {
      case PERIOD_MN1: return "MN1";
      case PERIOD_W1:  return "W1";
      case PERIOD_D1:  return "D1";
      default:         return "UNKNOWN";
   }
}

string StatusToText(EMetricStatus status)
{
   switch(status)
   {
      case METRIC_VALID:              return "VALID";
      case METRIC_UNAVAILABLE:        return "UNAVAILABLE";
      case METRIC_INSUFFICIENT_HISTORY: return "INSUFFICIENT_HISTORY";
      case METRIC_INVALID_INPUT:      return "INVALID_INPUT";
      case METRIC_CALCULATION_ERROR:  return "CALCULATION_ERROR";
      default:                        return "UNKNOWN";
   }
}

bool IsFinite(double value)
{
   if(value != value)
      return false;
   if(value > DBL_MAX || value < -DBL_MAX)
      return false;
   return true;
}

STrendVolConfig GetTrendVolConfigForTimeframe(ENUM_TIMEFRAMES tf)
{
   STrendVolConfig cfg;
   ZeroMemory(cfg);

   if(tf == PERIOD_D1)
   {
      cfg.trend_1m_bars = 21;
      cfg.trend_3m_bars = 63;
      cfg.trend_6m_bars = 126;
      cfg.trend_12m_bars = 252;
      cfg.ema_fast_bars = 63;
      cfg.ema_slow_bars = 252;
      cfg.atr_short_bars = 63;
      cfg.atr_long_bars = 252;
      cfg.breakout_bars = 63;
      cfg.volatility_rank_bars = 1260;
      cfg.volume_bars = 63;
   }
   else if(tf == PERIOD_W1)
   {
      cfg.trend_1m_bars = 4;
      cfg.trend_3m_bars = 13;
      cfg.trend_6m_bars = 26;
      cfg.trend_12m_bars = 52;
      cfg.ema_fast_bars = 13;
      cfg.ema_slow_bars = 52;
      cfg.atr_short_bars = 13;
      cfg.atr_long_bars = 52;
      cfg.breakout_bars = 13;
      cfg.volatility_rank_bars = 260;
      cfg.volume_bars = 13;
   }
   else if(tf == PERIOD_MN1)
   {
      cfg.trend_1m_bars = 1;
      cfg.trend_3m_bars = 3;
      cfg.trend_6m_bars = 6;
      cfg.trend_12m_bars = 12;
      cfg.ema_fast_bars = 3;
      cfg.ema_slow_bars = 12;
      cfg.atr_short_bars = 3;
      cfg.atr_long_bars = 12;
      cfg.breakout_bars = 3;
      cfg.volatility_rank_bars = 60;
      cfg.volume_bars = 3;
   }
   return cfg;
}

int GetRequiredBarCount(const STrendVolConfig &cfg)
{
   int max_count = 0;
   max_count = MathMax(max_count, cfg.trend_12m_bars);
   max_count = MathMax(max_count, cfg.ema_slow_bars);
   max_count = MathMax(max_count, cfg.atr_long_bars);
   max_count = MathMax(max_count, cfg.breakout_bars);
   max_count = MathMax(max_count, cfg.volatility_rank_bars);
   max_count = MathMax(max_count, cfg.volume_bars);
   return max_count + 1;
}

double ComputeMean(const double &values[])
{
   int n = ArraySize(values);
   if(n <= 0)
      return 0.0;
   double sum = 0.0;
   for(int i = 0; i < n; i++)
      sum += values[i];
   return sum / (double)n;
}

double ComputeSampleStdDev(const double &values[])
{
   int n = ArraySize(values);
   if(n < 2)
      return 0.0;

   double mean = ComputeMean(values);
   double sum_sq = 0.0;
   for(int i = 0; i < n; i++)
   {
      double diff = values[i] - mean;
      sum_sq += diff * diff;
   }
   return MathSqrt(sum_sq / (double)(n - 1));
}

double ComputePercentileRank(double value, const double &history[])
{
   int n = ArraySize(history);
   if(n <= 0)
      return 0.0;

   int count_le = 0;
   for(int i = 0; i < n; i++)
   {
      if(history[i] <= value)
         count_le++;
   }
   return (double)count_le / (double)n;
}

double ComputeAverage(const double &values[])
{
   int n = ArraySize(values);
   if(n <= 0)
      return 0.0;
   double sum = 0.0;
   for(int i = 0; i < n; i++)
      sum += values[i];
   return sum / (double)n;
}

bool IsSeriesValid(const MqlRates &rates[], int expected_count)
{
   int n = ArraySize(rates);
   if(n < expected_count)
      return false;

   if(n <= 1)
      return false;

   for(int i = 0; i < n; i++)
   {
      if(!IsFinite(rates[i].open) || !IsFinite(rates[i].high) || !IsFinite(rates[i].low) || !IsFinite(rates[i].close))
         return false;
      if(rates[i].high < rates[i].low)
         return false;
      if(rates[i].close <= 0.0)
         return false;
      if(rates[i].time <= 0)
         return false;
   }

   for(int i = 1; i < n; i++)
   {
      if(rates[i].time <= rates[i-1].time)
         return false;
   }

   return true;
}

double ComputeTrueRangeAt(const MqlRates &rates[], int idx)
{
   if(idx <= 0 || idx >= ArraySize(rates))
      return 0.0;

   double high = rates[idx].high;
   double low = rates[idx].low;
   double prev_close = rates[idx - 1].close;

   double tr = high - low;
   double diff1 = MathAbs(high - prev_close);
   double diff2 = MathAbs(low - prev_close);

   if(diff1 > tr)
      tr = diff1;
   if(diff2 > tr)
      tr = diff2;

   return tr;
}

double ComputeATRValue(const MqlRates &rates[], int period, int end_index)
{
   if(period <= 0 || end_index < 0 || end_index >= ArraySize(rates))
      return 0.0;

   int start_index = end_index - period + 1;
   if(start_index < 0)
      return 0.0;

   double total = 0.0;
   int count = 0;
   for(int i = start_index; i <= end_index; i++)
   {
      total += ComputeTrueRangeAt(rates, i);
      count++;
   }
   if(count <= 0)
      return 0.0;
   return total / (double)count;
}

double ComputeLogReturn(double base, double prior)
{
   if(base <= 0.0 || prior <= 0.0)
      return 0.0;
   return MathLog(base / prior);
}

double ComputeRegressionSlopeAndStats(const MqlRates &rates[], int period, int end_index, double &slope, double &tstat, double &r2)
{
   if(period < 3 || end_index < 0 || end_index >= ArraySize(rates))
      return 0.0;

   int start_index = end_index - period + 1;
   if(start_index < 0)
      return 0.0;

   int n = period;
   double x[];
   double y[];
   ArrayResize(x, n);
   ArrayResize(y, n);

   for(int i = 0; i < n; i++)
   {
      int idx = start_index + i;
      x[i] = (double)i;
      y[i] = MathLog(rates[idx].close);
   }

   double x_mean = ComputeAverage(x);
   double y_mean = ComputeAverage(y);
   double num = 0.0;
   double den = 0.0;

   for(int i = 0; i < n; i++)
   {
      double dx = x[i] - x_mean;
      double dy = y[i] - y_mean;
      num += dx * dy;
      den += dx * dx;
   }

   if(den <= 0.0)
      return 0.0;

   slope = num / den;
   double intercept = y_mean - slope * x_mean;

   double sse = 0.0;
   double sst = 0.0;
   for(int i = 0; i < n; i++)
   {
      double y_hat = intercept + slope * x[i];
      double d1 = y[i] - y_hat;
      double d2 = y[i] - y_mean;
      sse += d1 * d1;
      sst += d2 * d2;
   }

   if(sst <= 0.0)
      return 0.0;

   r2 = 1.0 - (sse / sst);

   double se_beta = MathSqrt(sse / (((double)n - 2.0) * den));
   if(se_beta <= 0.0)
      return 0.0;

   tstat = slope / se_beta;
   return slope;
}

double ComputeEfficiencyRatio(const MqlRates &rates[], int period, int end_index)
{
   if(period <= 0 || end_index < 0 || end_index >= ArraySize(rates))
      return 0.0;

   int start_index = end_index - period + 1;
   if(start_index < 0)
      return 0.0;

   double denom = 0.0;
   for(int i = start_index + 1; i <= end_index; i++)
   {
      double prev = rates[i-1].close;
      double cur = rates[i].close;
      if(prev <= 0.0 || cur <= 0.0)
         return 0.0;
      denom += MathAbs(MathLog(cur / prev));
   }

   if(denom <= 0.0)
      return 0.0;

   double num = MathAbs(MathLog(rates[end_index].close / rates[start_index].close));
   return num / denom;
}

double ComputeEMA(const MqlRates &rates[], int period, int end_index)
{
   if(period <= 0 || end_index < 0 || end_index >= ArraySize(rates))
      return 0.0;

   int n = ArraySize(rates);
   if(n < period)
      return 0.0;

   double ema = 0.0;
   double sum = 0.0;
   int init_count = MathMin(period, n);
   for(int i = 0; i < init_count; i++)
      sum += rates[i].close;
   ema = sum / (double)init_count;

   double alpha = 2.0 / ((double)period + 1.0);
   for(int i = init_count; i <= end_index; i++)
   {
      ema = alpha * rates[i].close + (1.0 - alpha) * ema;
   }

   return ema;
}

double ComputeRealizedVolValue(const MqlRates &rates[], int period, int end_index)
{
   if(period < 2 || end_index < 0 || end_index >= ArraySize(rates))
      return 0.0;

   int start_index = end_index - period + 1;
   if(start_index <= 0)
      return 0.0;

   double returns[];
   ArrayResize(returns, period);
   int pos = 0;
   for(int i = start_index; i <= end_index; i++)
   {
      double prev_close = rates[i - 1].close;
      double cur_close = rates[i].close;
      if(prev_close <= 0.0 || cur_close <= 0.0)
         return 0.0;
      returns[pos] = MathLog(cur_close / prev_close);
      pos++;
   }

   return ComputeSampleStdDev(returns);
}

double ComputeDonchianHigh(const MqlRates &rates[], int period, int end_index)
{
   if(period <= 0 || end_index < 0 || end_index >= ArraySize(rates))
      return 0.0;

   int start_index = end_index - period + 1;
   if(start_index < 0)
      return 0.0;

   double high_max = -DBL_MAX;
   for(int i = start_index; i <= end_index; i++)
   {
      if(rates[i].high > high_max)
         high_max = rates[i].high;
   }
   return high_max;
}

double ComputeDonchianLow(const MqlRates &rates[], int period, int end_index)
{
   if(period <= 0 || end_index < 0 || end_index >= ArraySize(rates))
      return 0.0;

   int start_index = end_index - period + 1;
   if(start_index < 0)
      return 0.0;

   double low_min = DBL_MAX;
   for(int i = start_index; i <= end_index; i++)
   {
      if(rates[i].low < low_min)
         low_min = rates[i].low;
   }
   return low_min;
}

double ComputeTrailingVolumeRatio(const MqlRates &rates[], int window_bars, int end_index, bool use_tick_volume)
{
   if(window_bars <= 0 || end_index <= 0 || end_index >= ArraySize(rates))
      return 0.0;

   int start_index = end_index - window_bars;
   if(start_index < 0)
      return 0.0;

   double values[];
   ArrayResize(values, window_bars);
   int pos = 0;
   for(int i = start_index; i < end_index; i++)
   {
      values[pos] = use_tick_volume ? (double)rates[i].tick_volume : (double)rates[i].real_volume;
      pos++;
   }

   double avg = ComputeAverage(values);
   if(avg <= 0.0)
      return 0.0;

   double current_value = use_tick_volume ? (double)rates[end_index].tick_volume : (double)rates[end_index].real_volume;
   return current_value / avg;
}

bool BuildMetricStatusValue(EMetricStatus status, double &value, bool valid)
{
   value = valid ? value : 0.0;
   return valid;
}

void SetResultDefaults(STrendVolL1Result &res)
{
   res.series_synchronized = false;
   res.calculation_valid = false;
   res.overall_status = METRIC_INVALID_INPUT;
   res.source_shift = 1;
   res.methodology_id = "TVE-L1";
   res.engine_version = "1.0";
   res.breakout_side = 0;
   res.real_volume_status = METRIC_UNAVAILABLE;
}

string BuildMarkdownReport(const STrendVolL1Result &res)
{
   string s = "";
   s += "# Strategy 2 — Trend + Volatility Expansion\n";
   s += "## Layer 1\n\n";
   s += "### Identity\n";
   s += "- Symbol: " + res.symbol + "\n";
   s += "- Timeframe: " + TimeframeToString(res.timeframe) + "\n";
   s += "- Closed bar: " + TimeToString(res.closed_bar_time, TIME_DATE | TIME_MINUTES) + "\n";
   s += "- Source shift: " + IntegerToString(res.source_shift) + "\n";
   s += "- Source bars copied: " + IntegerToString(res.source_bar_count) + "\n";
   s += "- Calculation boundary: closed " + TimeframeToString(res.timeframe) + " bar\n";
   s += "- Methodology: " + res.methodology_id + "\n";
   s += "- Engine version: " + res.engine_version + "\n\n";

   s += "### Data Status\n";
   s += "- Series synchronized: " + (res.series_synchronized ? "YES" : "NO") + "\n";
   s += "- Calculation status: " + StatusToText(res.overall_status) + "\n";
   s += "- History sufficiency: " + (res.calculation_valid ? "VALID" : "INSUFFICIENT") + "\n\n";

   s += "### Trend\n";
   s += "- Log return — 1M: " + DoubleToString(res.log_return_1m, 8) + "\n";
   s += "- Log return — 3M: " + DoubleToString(res.log_return_3m, 8) + "\n";
   s += "- Log return — 6M: " + DoubleToString(res.log_return_6m, 8) + "\n";
   s += "- Log return — 12M: " + DoubleToString(res.log_return_12m, 8) + "\n\n";

   s += "- Regression slope — 3M: " + DoubleToString(res.trend_slope_3m, 8) + "\n";
   s += "- Regression slope — 6M: " + DoubleToString(res.trend_slope_6m, 8) + "\n";
   s += "- Regression slope — 12M: " + DoubleToString(res.trend_slope_12m, 8) + "\n\n";

   s += "- Regression t-statistic — 3M: " + DoubleToString(res.trend_tstat_3m, 8) + "\n";
   s += "- Regression t-statistic — 6M: " + DoubleToString(res.trend_tstat_6m, 8) + "\n";
   s += "- Regression t-statistic — 12M: " + DoubleToString(res.trend_tstat_12m, 8) + "\n\n";

   s += "- Regression R² — 3M: " + DoubleToString(res.trend_r2_3m, 8) + "\n";
   s += "- Regression R² — 6M: " + DoubleToString(res.trend_r2_6m, 8) + "\n";
   s += "- Regression R² — 12M: " + DoubleToString(res.trend_r2_12m, 8) + "\n\n";

   s += "- Efficiency ratio — 3M: " + DoubleToString(res.efficiency_ratio_3m, 8) + "\n";
   s += "- Efficiency ratio — 6M: " + DoubleToString(res.efficiency_ratio_6m, 8) + "\n";
   s += "- Efficiency ratio — 12M: " + DoubleToString(res.efficiency_ratio_12m, 8) + "\n\n";

   s += "- EMA fast: " + DoubleToString(res.ema_fast, 8) + "\n";
   s += "- EMA slow: " + DoubleToString(res.ema_slow, 8) + "\n";
   s += "- EMA spread: " + DoubleToString(res.ema_spread_pct, 8) + "\n\n";

   s += "### Volatility\n";
   s += "- True Range: " + DoubleToString(res.true_range, 8) + "\n";
   s += "- ATR — 3M: " + DoubleToString(res.atr_short, 8) + "\n";
   s += "- ATR — 12M: " + DoubleToString(res.atr_long, 8) + "\n";
   s += "- ATR / price — 3M: " + DoubleToString(res.atr_short_pct_price, 8) + "\n";
   s += "- ATR / price — 12M: " + DoubleToString(res.atr_long_pct_price, 8) + "\n";
   s += "- ATR expansion ratio: " + DoubleToString(res.atr_expansion_ratio, 8) + "\n";
   s += "- True Range / ATR: " + DoubleToString(res.tr_to_atr_ratio, 8) + "\n\n";

   s += "- Realized volatility — 3M: " + DoubleToString(res.realized_vol_3m, 8) + "\n";
   s += "- Realized volatility — 12M: " + DoubleToString(res.realized_vol_12m, 8) + "\n";
   s += "- Realized volatility ratio: " + DoubleToString(res.realized_vol_ratio, 8) + "\n\n";

   s += "- ATR percentile rank: " + DoubleToString(res.atr_percentile_rank, 8) + "\n";
   s += "- Realized volatility percentile rank: " + DoubleToString(res.realized_vol_percentile_rank, 8) + "\n\n";

   s += "### Breakout / Range\n";
   s += "- Donchian high: " + DoubleToString(res.donchian_high, 8) + "\n";
   s += "- Donchian low: " + DoubleToString(res.donchian_low, 8) + "\n";
   s += "- Donchian width: " + DoubleToString(res.donchian_width, 8) + "\n";
   s += "- Donchian width / price: " + DoubleToString(res.donchian_width_pct_price, 8) + "\n";
   s += "- Donchian width / ATR: " + DoubleToString(res.donchian_width_atr, 8) + "\n\n";

   s += "- Breakout distance above channel / ATR: " + DoubleToString(res.breakout_distance_up_atr, 8) + "\n";
   s += "- Breakout distance below channel / ATR: " + DoubleToString(res.breakout_distance_down_atr, 8) + "\n";
   s += "- Breakout side: " + IntegerToString(res.breakout_side) + "\n\n";

   s += "- Close-location value: " + DoubleToString(res.close_location_value, 8) + "\n";
   s += "- Candle body fraction: " + DoubleToString(res.body_fraction, 8) + "\n\n";

   s += "### Participation\n";
   s += "- Tick volume: " + IntegerToString(res.tick_volume) + "\n";
   s += "- Tick volume ratio: " + DoubleToString(res.tick_volume_ratio, 8) + "\n";
   s += "- Real volume: " + IntegerToString(res.real_volume) + "\n";
   if(res.real_volume_status == METRIC_VALID)
      s += "- Real volume ratio: " + DoubleToString(res.real_volume_ratio, 8) + "\n";
   else
      s += "- Real volume ratio: unavailable\n";
   s += "- Real-volume status: " + (res.real_volume_status == METRIC_VALID ? "VALID" : "unavailable from MT5 source") + "\n\n";

   s += "### Methodology\n";
   s += "- Trend return definition: log(Ct / Ct-N)\n";
   s += "- Trend regression: OLS on log(close) versus bar index\n";
   s += "- ATR definition: arithmetic mean of True Range over stated lookback\n";
   s += "- Realized volatility: sample standard deviation of log returns\n";
   s += "- Donchian reference: prior closed bars only\n";
   s += "- Percentile rank: empirical rank against prior observations only\n\n";

   s += "### Provenance\n";
   s += "- Symbol: " + res.symbol + "\n";
   s += "- Timeframe: " + TimeframeToString(res.timeframe) + "\n";
   s += "- Source bar count: " + IntegerToString(res.source_bar_count) + "\n";
   s += "- Calculation boundary: closed " + TimeframeToString(res.timeframe) + " bar\n";
   s += "- Engine: Strategy 2 / Trend + Volatility Expansion / Layer 1\n";
   s += "- Version: " + res.engine_version + "\n";
   return s;
}

bool CalculateTrendVolL1(string symbol, ENUM_TIMEFRAMES timeframe, STrendVolL1Result &result)
{
   SetResultDefaults(result);
   result.symbol = symbol;
   result.timeframe = timeframe;
   result.source_shift = 1;

   STrendVolConfig cfg = GetTrendVolConfigForTimeframe(timeframe);
   int required_bars = GetRequiredBarCount(cfg);

   MqlRates rates[];
   int copied = CopyRates(symbol, timeframe, 1, required_bars, rates); // source starts with the most recent closed bar
   if(copied <= 0)
   {
      result.overall_status = METRIC_INSUFFICIENT_HISTORY;
      result.required_bar_count = required_bars;
      return false;
   }

   result.required_bar_count = required_bars;
   result.source_bar_count = copied;
   result.closed_bar_time = rates[copied - 1].time;
   result.series_synchronized = (SeriesInfoInteger(symbol, timeframe, SERIES_SYNCHRONIZED) == 1);

   if(!IsSeriesValid(rates, copied))
   {
      result.overall_status = METRIC_INVALID_INPUT;
      result.calculation_valid = false;
      return false;
   }

   if(copied < required_bars)
   {
      result.overall_status = METRIC_INSUFFICIENT_HISTORY;
      result.calculation_valid = false;
      return false;
   }

   int last = copied - 1;
   double close_t = rates[last].close;
   double open_t = rates[last].open;
   double high_t = rates[last].high;
   double low_t = rates[last].low;

   if(close_t <= 0.0 || high_t < low_t)
   {
      result.overall_status = METRIC_INVALID_INPUT;
      result.calculation_valid = false;
      return false;
   }

   result.log_return_1m = ComputeLogReturn(close_t, rates[MathMax(0, last - cfg.trend_1m_bars)].close);
   result.log_return_3m = ComputeLogReturn(close_t, rates[MathMax(0, last - cfg.trend_3m_bars)].close);
   result.log_return_6m = ComputeLogReturn(close_t, rates[MathMax(0, last - cfg.trend_6m_bars)].close);
   result.log_return_12m = ComputeLogReturn(close_t, rates[MathMax(0, last - cfg.trend_12m_bars)].close);

   double slope3 = 0.0, t3 = 0.0, r23 = 0.0;
   double slope6 = 0.0, t6 = 0.0, r26 = 0.0;
   double slope12 = 0.0, t12 = 0.0, r212 = 0.0;

   if(cfg.trend_3m_bars >= 3)
      ComputeRegressionSlopeAndStats(rates, cfg.trend_3m_bars, last, slope3, t3, r23);
   if(cfg.trend_6m_bars >= 3)
      ComputeRegressionSlopeAndStats(rates, cfg.trend_6m_bars, last, slope6, t6, r26);
   if(cfg.trend_12m_bars >= 3)
      ComputeRegressionSlopeAndStats(rates, cfg.trend_12m_bars, last, slope12, t12, r212);

   result.trend_slope_3m = slope3;
   result.trend_slope_6m = slope6;
   result.trend_slope_12m = slope12;
   result.trend_tstat_3m = t3;
   result.trend_tstat_6m = t6;
   result.trend_tstat_12m = t12;
   result.trend_r2_3m = r23;
   result.trend_r2_6m = r26;
   result.trend_r2_12m = r212;

   result.efficiency_ratio_3m = ComputeEfficiencyRatio(rates, cfg.trend_3m_bars, last);
   result.efficiency_ratio_6m = ComputeEfficiencyRatio(rates, cfg.trend_6m_bars, last);
   result.efficiency_ratio_12m = ComputeEfficiencyRatio(rates, cfg.trend_12m_bars, last);

   if(cfg.ema_fast_bars > 0)
      result.ema_fast = ComputeEMA(rates, cfg.ema_fast_bars, last);
   if(cfg.ema_slow_bars > 0)
      result.ema_slow = ComputeEMA(rates, cfg.ema_slow_bars, last);
   if(MathAbs(result.ema_slow) > 0.0)
      result.ema_spread_pct = (result.ema_fast - result.ema_slow) / result.ema_slow;
   else
      result.ema_spread_pct = 0.0;

   result.true_range = ComputeTrueRangeAt(rates, last);
   result.atr_short = ComputeATRValue(rates, cfg.atr_short_bars, last);
   result.atr_long = ComputeATRValue(rates, cfg.atr_long_bars, last);
   if(close_t > 0.0)
   {
      result.atr_short_pct_price = result.atr_short / close_t;
      result.atr_long_pct_price = result.atr_long / close_t;
   }
   if(result.atr_long > 0.0)
      result.atr_expansion_ratio = result.atr_short / result.atr_long;
   else
      result.atr_expansion_ratio = 0.0;
   if(result.atr_short > 0.0)
      result.tr_to_atr_ratio = result.true_range / result.atr_short;
   else
      result.tr_to_atr_ratio = 0.0;

   result.realized_vol_3m = ComputeRealizedVolValue(rates, cfg.trend_3m_bars, last);
   result.realized_vol_12m = ComputeRealizedVolValue(rates, cfg.trend_12m_bars, last);
   if(result.realized_vol_12m > 0.0)
      result.realized_vol_ratio = result.realized_vol_3m / result.realized_vol_12m;
   else
      result.realized_vol_ratio = 0.0;

   int reference_count = MathMin(cfg.volatility_rank_bars, MathMax(0, copied - 2));
   if(reference_count > 0)
   {
      double atr_hist[];
      double rv_hist[];
      ArrayResize(atr_hist, reference_count);
      ArrayResize(rv_hist, reference_count);

      int hist_pos = 0;
      for(int i = 1; i <= reference_count; i++)
      {
         int idx = last - i;
         if(idx > 0)
         {
            atr_hist[hist_pos] = ComputeATRValue(rates, cfg.atr_short_bars, idx);
            rv_hist[hist_pos] = ComputeRealizedVolValue(rates, cfg.trend_3m_bars, idx);
            hist_pos++;
         }
      }

      if(hist_pos > 0)
      {
         if(ArraySize(atr_hist) > 0)
            result.atr_percentile_rank = ComputePercentileRank(result.atr_short, atr_hist);
         if(ArraySize(rv_hist) > 0)
            result.realized_vol_percentile_rank = ComputePercentileRank(result.realized_vol_3m, rv_hist);
      }
   }

   int donchian_period = cfg.breakout_bars;
   int donchian_start = last - donchian_period;
   int donchian_end = last - 1;
   if(donchian_start >= 0 && donchian_end >= donchian_start)
   {
      result.donchian_high = ComputeDonchianHigh(rates, donchian_period, donchian_end);
      result.donchian_low = ComputeDonchianLow(rates, donchian_period, donchian_end);
      result.donchian_width = result.donchian_high - result.donchian_low;
      if(close_t > 0.0)
         result.donchian_width_pct_price = result.donchian_width / close_t;
      if(result.atr_short > 0.0)
         result.donchian_width_atr = result.donchian_width / result.atr_short;
      if(result.atr_short > 0.0)
      {
         result.breakout_distance_up_atr = (close_t - result.donchian_high) / result.atr_short;
         result.breakout_distance_down_atr = (result.donchian_low - close_t) / result.atr_short;
      }
   }

   if(result.donchian_high > 0.0 && result.donchian_low > 0.0)
   {
      if(close_t > result.donchian_high)
         result.breakout_side = 1;
      else if(close_t < result.donchian_low)
         result.breakout_side = -1;
      else
         result.breakout_side = 0;
   }
   else
   {
      result.breakout_side = 0;
   }

   double range_t = high_t - low_t;
   if(range_t > 0.0)
   {
      result.close_location_value = (2.0 * close_t - high_t - low_t) / range_t;
      result.body_fraction = MathAbs(open_t - close_t) / range_t;
   }
   else
   {
      result.close_location_value = 0.0;
      result.body_fraction = 0.0;
   }

   result.tick_volume = rates[last].tick_volume;
   result.real_volume = rates[last].real_volume;

   int volume_window = cfg.volume_bars;
   double tick_ratio = ComputeTrailingVolumeRatio(rates, volume_window, last, true);
   if(tick_ratio > 0.0)
      result.tick_volume_ratio = tick_ratio;
   else
      result.tick_volume_ratio = 0.0;

   if(result.real_volume > 0)
   {
      double real_ratio = ComputeTrailingVolumeRatio(rates, volume_window, last, false);
      result.real_volume_status = METRIC_VALID;
      result.real_volume_ratio = real_ratio > 0.0 ? real_ratio : 0.0;
   }
   else
   {
      result.real_volume_status = METRIC_UNAVAILABLE;
      result.real_volume_ratio = 0.0;
   }

   result.calculation_valid = true;
   result.overall_status = METRIC_VALID;
   return true;
}

int OnStart()
{
   string symbol = InUseChartSymbol ? _Symbol : InSymbol;
   if(symbol == "")
      symbol = _Symbol;

   if(InProcessAllTimeframes)
   {
      string report = "";
      report += "# Strategy 2 — Trend + Volatility Expansion\n";
      report += "## Layer 1\n\n";

      STrendVolL1Result d1_result;
      bool ok_d1 = CalculateTrendVolL1(symbol, PERIOD_D1, d1_result);
      report += "### D1\n";
      report += BuildMarkdownReport(d1_result);
      report += "\n\n";

      STrendVolL1Result w1_result;
      bool ok_w1 = CalculateTrendVolL1(symbol, PERIOD_W1, w1_result);
      report += "### W1\n";
      report += BuildMarkdownReport(w1_result);
      report += "\n\n";

      STrendVolL1Result mn1_result;
      bool ok_mn1 = CalculateTrendVolL1(symbol, PERIOD_MN1, mn1_result);
      report += "### MN1\n";
      report += BuildMarkdownReport(mn1_result);
      report += "\n\n";

      if(!ok_d1 && !ok_w1 && !ok_mn1)
         Print("Calculation failed for all requested timeframes.");
      Print(report);
      return 0;
   }

   STrendVolL1Result result;
   bool ok = CalculateTrendVolL1(symbol, InTimeframe, result);
   if(!ok)
   {
      Print("# Strategy 2 — Trend + Volatility Expansion\n## Layer 1\n\n### Data Status\n- Calculation status: " + StatusToText(result.overall_status) + "\n");
      return 0;
   }

   Print(BuildMarkdownReport(result));
   return 0;
}
