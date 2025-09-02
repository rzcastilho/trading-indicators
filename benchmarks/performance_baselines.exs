# Performance baselines and regression detection for TradingIndicators

alias TradingIndicators.TestSupport.{DataGenerator, BenchmarkHelpers}

# Generate test data
small_data = DataGenerator.sample_prices(100)
medium_data = DataGenerator.sample_prices(1_000)
large_data = DataGenerator.sample_prices(10_000)
ohlcv_small = DataGenerator.sample_ohlcv_data(100)
ohlcv_medium = DataGenerator.sample_ohlcv_data(1_000)

IO.puts("Establishing Performance Baselines for TradingIndicators")
IO.puts("=" <> String.duplicate("=", 55))
IO.puts("Timestamp: #{DateTime.utc_now() |> DateTime.to_string()}")
IO.puts("")

# Performance baselines (in microseconds)
# These represent acceptable performance targets
baselines = %{
  # Trend Indicators (100/1K/10K data points)
  sma: %{100 => 100_000, 1_000 => 800_000, 10_000 => 8_000_000},
  ema: %{100 => 150_000, 1_000 => 1_200_000, 10_000 => 12_000_000},
  wma: %{100 => 200_000, 1_000 => 1_600_000, 10_000 => 16_000_000},
  hma: %{100 => 300_000, 1_000 => 2_400_000, 10_000 => 24_000_000},
  kama: %{100 => 400_000, 1_000 => 3_200_000, 10_000 => 32_000_000},
  macd: %{100 => 600_000, 1_000 => 4_800_000, 10_000 => 48_000_000},
  
  # Momentum Indicators
  rsi: %{100 => 300_000, 1_000 => 2_400_000, 10_000 => 24_000_000},
  roc: %{100 => 150_000, 1_000 => 1_200_000, 10_000 => 12_000_000},
  stochastic: %{100 => 400_000, 1_000 => 3_200_000, 10_000 => 32_000_000},
  cci: %{100 => 350_000, 1_000 => 2_800_000, 10_000 => 28_000_000},
  williams_r: %{100 => 250_000, 1_000 => 2_000_000, 10_000 => 20_000_000},
  
  # Volatility Indicators
  atr: %{100 => 300_000, 1_000 => 2_400_000, 10_000 => 24_000_000},
  bollinger: %{100 => 400_000, 1_000 => 3_200_000, 10_000 => 32_000_000},
  std_dev: %{100 => 250_000, 1_000 => 2_000_000, 10_000 => 20_000_000},
  volatility_index: %{100 => 350_000, 1_000 => 2_800_000, 10_000 => 28_000_000},
  
  # Volume Indicators
  obv: %{100 => 150_000, 1_000 => 1_200_000, 10_000 => 12_000_000},
  vwap: %{100 => 200_000, 1_000 => 1_600_000, 10_000 => 16_000_000},
  ad: %{100 => 250_000, 1_000 => 2_000_000, 10_000 => 20_000_000},
  cmf: %{100 => 300_000, 1_000 => 2_400_000, 10_000 => 24_000_000}
}

# Memory usage baselines (in bytes)
memory_baselines = %{
  100 => 50_000,    # 50KB for 100 data points
  1_000 => 500_000,  # 500KB for 1K data points
  10_000 => 5_000_000 # 5MB for 10K data points
}

IO.puts("Running performance regression tests...")
IO.puts("")

# Define test functions for each indicator
test_functions = %{
  sma: fn data, _ohlcv -> TradingIndicators.Trend.SMA.calculate(data, 14) end,
  ema: fn data, _ohlcv -> TradingIndicators.Trend.EMA.calculate(data, 14) end,
  wma: fn data, _ohlcv -> TradingIndicators.Trend.WMA.calculate(data, 14) end,
  hma: fn data, _ohlcv -> TradingIndicators.Trend.HMA.calculate(data, 14) end,
  kama: fn data, _ohlcv -> TradingIndicators.Trend.KAMA.calculate(data, 10, 2, 30) end,
  macd: fn data, _ohlcv -> TradingIndicators.Trend.MACD.calculate(data, 12, 26, 9) end,
  
  rsi: fn data, _ohlcv -> TradingIndicators.Momentum.RSI.calculate(data, 14) end,
  roc: fn data, _ohlcv -> TradingIndicators.Momentum.ROC.calculate(data, 10) end,
  stochastic: fn _data, ohlcv -> TradingIndicators.Momentum.Stochastic.calculate(ohlcv, 14, 3) end,
  cci: fn _data, ohlcv -> TradingIndicators.Momentum.CCI.calculate(ohlcv, 20) end,
  williams_r: fn _data, ohlcv -> TradingIndicators.Momentum.WilliamsR.calculate(ohlcv, 14) end,
  
  atr: fn _data, ohlcv -> TradingIndicators.Volatility.ATR.calculate(ohlcv, 14) end,
  bollinger: fn data, _ohlcv -> TradingIndicators.Volatility.BollingerBands.calculate(data, 20, Decimal.new("2.0")) end,
  std_dev: fn data, _ohlcv -> TradingIndicators.Volatility.StandardDeviation.calculate(data, 20) end,
  volatility_index: fn data, _ohlcv -> TradingIndicators.Volatility.VolatilityIndex.calculate(data, 20) end,
  
  obv: fn _data, ohlcv -> TradingIndicators.Volume.OBV.calculate(ohlcv) end,
  vwap: fn _data, ohlcv -> TradingIndicators.Volume.VWAP.calculate(ohlcv) end,
  ad: fn _data, ohlcv -> TradingIndicators.Volume.AccumulationDistribution.calculate(ohlcv) end,
  cmf: fn _data, ohlcv -> TradingIndicators.Volume.ChaikinMoneyFlow.calculate(ohlcv, 20) end
}

# Test data sets
test_datasets = %{
  100 => {small_data, ohlcv_small},
  1_000 => {medium_data, ohlcv_medium},
  10_000 => {large_data, ohlcv_medium} # Note: using medium OHLCV for memory reasons
}

# Run regression tests for each indicator
regression_results = %{}

Enum.each(test_functions, fn {indicator_name, test_func} ->
  IO.puts("Testing #{indicator_name}...")
  
  indicator_results = Enum.reduce(test_datasets, %{}, fn {size, {data, ohlcv}}, acc ->
    try do
      # Run test multiple times for accuracy
      times = for _i <- 1..5 do
        {time, _result} = :timer.tc(test_func, [data, ohlcv])
        time
      end
      
      # Calculate statistics
      avg_time = Enum.sum(times) / length(times)
      median_time = times |> Enum.sort() |> Enum.at(div(length(times), 2))
      
      # Check against baseline
      baseline_time = get_in(baselines, [indicator_name, size])
      
      status = if baseline_time do
        regression_factor = avg_time / baseline_time
        cond do
          regression_factor <= 1.0 -> :improved
          regression_factor <= 1.2 -> :acceptable # Within 20% tolerance
          regression_factor <= 1.5 -> :degraded
          true -> :failed
        end
      else
        :no_baseline
      end
      
      result = %{
        average_time: round(avg_time),
        median_time: round(median_time),
        baseline_time: baseline_time,
        regression_factor: if(baseline_time, do: avg_time / baseline_time, else: nil),
        status: status
      }
      
      Map.put(acc, size, result)
      
    rescue
      error ->
        Map.put(acc, size, %{error: Exception.message(error), status: :error})
    end
  end)
  
  regression_results = Map.put(regression_results, indicator_name, indicator_results)
end)

# Display results
IO.puts("")
IO.puts("PERFORMANCE REGRESSION TEST RESULTS")
IO.puts("=" <> String.duplicate("=", 40))
IO.puts("")

# Summary statistics
total_tests = 0
passed_tests = 0
degraded_tests = 0
failed_tests = 0

Enum.each(regression_results, fn {indicator_name, results} ->
  IO.puts("#{String.upcase(Atom.to_string(indicator_name))}")
  IO.puts(String.duplicate("-", String.length(Atom.to_string(indicator_name))))
  
  Enum.each([100, 1_000, 10_000], fn size ->
    case Map.get(results, size) do
      %{status: :error, error: error} ->
        IO.puts("  #{size} points: ERROR - #{error}")
        
      %{status: status, average_time: avg_time, baseline_time: baseline, regression_factor: factor} ->
        total_tests = total_tests + 1
        
        status_symbol = case status do
          :improved -> "✅"
          :acceptable -> "✅" 
          :degraded -> "⚠️ "
          :failed -> "❌"
          :no_baseline -> "ℹ️ "
        end
        
        time_str = "#{Float.round(avg_time / 1000, 1)}ms"
        baseline_str = if baseline, do: "#{Float.round(baseline / 1000, 1)}ms", else: "N/A"
        factor_str = if factor, do: "#{Float.round(factor, 2)}x", else: "N/A"
        
        IO.puts("  #{size} points: #{status_symbol} #{time_str} (baseline: #{baseline_str}, factor: #{factor_str})")
        
        case status do
          s when s in [:improved, :acceptable] -> passed_tests = passed_tests + 1
          :degraded -> degraded_tests = degraded_tests + 1
          :failed -> failed_tests = failed_tests + 1
          _ -> nil
        end
        
      nil ->
        IO.puts("  #{size} points: No data")
    end
  end)
  
  IO.puts("")
end)

# Memory usage analysis
IO.puts("MEMORY USAGE ANALYSIS")
IO.puts("=" <> String.duplicate("=", 25))
IO.puts("")

memory_results = BenchmarkHelpers.memory_benchmark(fn data ->
  TradingIndicators.Trend.SMA.calculate(data, 14)
end, [100, 1_000, 10_000])

Enum.each(memory_results, fn result ->
  baseline = Map.get(memory_baselines, result.size)
  memory_mb = Float.round(result.memory_used / (1024 * 1024), 2)
  baseline_mb = if baseline, do: Float.round(baseline / (1024 * 1024), 2), else: nil
  
  status = if baseline do
    ratio = result.memory_used / baseline
    cond do
      ratio <= 1.0 -> "✅"
      ratio <= 1.2 -> "✅"
      ratio <= 1.5 -> "⚠️"
      true -> "❌"
    end
  else
    "ℹ️"
  end
  
  baseline_str = if baseline_mb, do: "#{baseline_mb}MB", else: "N/A"
  
  IO.puts("#{result.size} points: #{status} #{memory_mb}MB (baseline: #{baseline_str})")
  IO.puts("  Efficiency: #{Float.round(result.memory_efficiency, 3)}")
  IO.puts("")
end)

# Performance recommendations
IO.puts("PERFORMANCE RECOMMENDATIONS")
IO.puts("=" <> String.duplicate("=", 30))
IO.puts("")

recommendations = []

# Analyze failed/degraded tests
critical_issues = regression_results
|> Enum.filter(fn {_indicator, results} ->
  Enum.any?(results, fn {_size, result} -> 
    Map.get(result, :status) in [:failed, :degraded]
  end)
end)

if not Enum.empty?(critical_issues) do
  recommendations = [
    "🔧 Performance Issues Detected:",
    "   • Consider optimizing algorithms for degraded indicators",
    "   • Profile memory usage for large datasets",
    "   • Review recent changes for performance regressions"
    | recommendations
  ]
end

# Check for memory issues
high_memory = Enum.any?(memory_results, fn result ->
  result.memory_efficiency > 2.0
end)

if high_memory do
  recommendations = [
    "💾 Memory Optimization Needed:",
    "   • Consider streaming processing for large datasets",
    "   • Implement data chunking strategies",
    "   • Review buffer management in calculations"
    | recommendations
  ]
end

# General recommendations
recommendations = [
  "📊 General Performance Tips:",
  "   • Use appropriate data sizes for your use case",
  "   • Consider parallel processing for multiple indicators",
  "   • Cache frequently computed results",
  "   • Monitor production performance metrics",
  ""
  | recommendations
]

Enum.each(Enum.reverse(recommendations), &IO.puts/1)

# Summary
IO.puts("TEST SUMMARY")
IO.puts("=" <> String.duplicate("=", 15))
IO.puts("Total tests: #{total_tests}")
IO.puts("Passed: #{passed_tests} (#{Float.round(passed_tests / total_tests * 100, 1)}%)")
IO.puts("Degraded: #{degraded_tests} (#{Float.round(degraded_tests / total_tests * 100, 1)}%)")
IO.puts("Failed: #{failed_tests} (#{Float.round(failed_tests / total_tests * 100, 1)}%)")
IO.puts("")

# Save results to file
results_file = "benchmarks/results/performance_baseline_#{DateTime.utc_now() |> DateTime.to_date() |> Date.to_string()}.json"

baseline_data = %{
  timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
  elixir_version: System.version(),
  otp_version: System.otp_release(),
  system_info: %{
    schedulers: System.schedulers_online(),
    memory: :erlang.memory(:total)
  },
  baselines: baselines,
  memory_baselines: memory_baselines,
  results: regression_results,
  memory_results: memory_results,
  summary: %{
    total_tests: total_tests,
    passed_tests: passed_tests,
    degraded_tests: degraded_tests,
    failed_tests: failed_tests
  }
}

File.write!(results_file, Jason.encode!(baseline_data, pretty: true))

IO.puts("Results saved to: #{results_file}")
IO.puts("")

# Exit with appropriate code
exit_code = cond do
  failed_tests > 0 -> 2
  degraded_tests > 0 -> 1
  true -> 0
end

IO.puts("Performance baseline analysis completed!")
if exit_code > 0 do
  IO.puts("⚠️  Some performance issues detected (exit code: #{exit_code})")
else
  IO.puts("✅ All performance tests passed!")
end

System.halt(exit_code)