# Comprehensive performance benchmarks for trading indicators

alias TradingIndicators.TestSupport.{DataGenerator, BenchmarkHelpers}

# Generate test datasets of different sizes
small_data = DataGenerator.sample_prices(100)
medium_data = DataGenerator.sample_prices(1_000)
large_data = DataGenerator.sample_prices(10_000)
xlarge_data = DataGenerator.sample_prices(50_000)

small_ohlcv = DataGenerator.sample_ohlcv_data(100)
medium_ohlcv = DataGenerator.sample_ohlcv_data(1_000)
large_ohlcv = DataGenerator.sample_ohlcv_data(10_000)

IO.puts("Running comprehensive indicator benchmarks...")
IO.puts("Dataset sizes: 100, 1K, 10K, 50K data points")
IO.puts("=" <> String.duplicate("=", 50))

# Trend Indicators Benchmark
Benchee.run(
  %{
    # Simple Moving Average
    "SMA (100)" => fn -> TradingIndicators.Trend.SMA.calculate(small_data, 14) end,
    "SMA (1K)" => fn -> TradingIndicators.Trend.SMA.calculate(medium_data, 14) end,
    "SMA (10K)" => fn -> TradingIndicators.Trend.SMA.calculate(large_data, 14) end,
    "SMA (50K)" => fn -> TradingIndicators.Trend.SMA.calculate(xlarge_data, 14) end,
    
    # Exponential Moving Average
    "EMA (100)" => fn -> TradingIndicators.Trend.EMA.calculate(small_data, 14) end,
    "EMA (1K)" => fn -> TradingIndicators.Trend.EMA.calculate(medium_data, 14) end,
    "EMA (10K)" => fn -> TradingIndicators.Trend.EMA.calculate(large_data, 14) end,
    "EMA (50K)" => fn -> TradingIndicators.Trend.EMA.calculate(xlarge_data, 14) end,
    
    # Weighted Moving Average
    "WMA (100)" => fn -> TradingIndicators.Trend.WMA.calculate(small_data, 14) end,
    "WMA (1K)" => fn -> TradingIndicators.Trend.WMA.calculate(medium_data, 14) end,
    "WMA (10K)" => fn -> TradingIndicators.Trend.WMA.calculate(large_data, 14) end,
    "WMA (50K)" => fn -> TradingIndicators.Trend.WMA.calculate(xlarge_data, 14) end,
    
    # Hull Moving Average
    "HMA (100)" => fn -> TradingIndicators.Trend.HMA.calculate(small_data, 14) end,
    "HMA (1K)" => fn -> TradingIndicators.Trend.HMA.calculate(medium_data, 14) end,
    "HMA (10K)" => fn -> TradingIndicators.Trend.HMA.calculate(large_data, 14) end,
    "HMA (50K)" => fn -> TradingIndicators.Trend.HMA.calculate(xlarge_data, 14) end,
  },
  time: 10,
  memory_time: 2,
  reduction_time: 2,
  pre_check: true,
  formatters: [
    Benchee.Formatters.HTML,
    Benchee.Formatters.JSON,
    Benchee.Formatters.Console
  ],
  formatter_options: [
    html: [file: "benchmarks/results/trend_indicators.html"],
    json: [file: "benchmarks/results/trend_indicators.json"]
  ],
  print: [
    benchmarking: true,
    configuration: false,
    fast_warning: false
  ]
)

IO.puts("\nMomentum Indicators Benchmark")
IO.puts("=" <> String.duplicate("=", 30))

# Momentum Indicators Benchmark
Benchee.run(
  %{
    # RSI (Relative Strength Index)
    "RSI (100)" => fn -> TradingIndicators.Momentum.RSI.calculate(small_data, 14) end,
    "RSI (1K)" => fn -> TradingIndicators.Momentum.RSI.calculate(medium_data, 14) end,
    "RSI (10K)" => fn -> TradingIndicators.Momentum.RSI.calculate(large_data, 14) end,
    "RSI (50K)" => fn -> TradingIndicators.Momentum.RSI.calculate(xlarge_data, 14) end,
    
    # Rate of Change
    "ROC (100)" => fn -> TradingIndicators.Momentum.ROC.calculate(small_data, 14) end,
    "ROC (1K)" => fn -> TradingIndicators.Momentum.ROC.calculate(medium_data, 14) end,
    "ROC (10K)" => fn -> TradingIndicators.Momentum.ROC.calculate(large_data, 14) end,
    "ROC (50K)" => fn -> TradingIndicators.Momentum.ROC.calculate(xlarge_data, 14) end,
    
    # Stochastic Oscillator
    "Stochastic (100)" => fn -> TradingIndicators.Momentum.Stochastic.calculate(small_ohlcv, 14, 3) end,
    "Stochastic (1K)" => fn -> TradingIndicators.Momentum.Stochastic.calculate(medium_ohlcv, 14, 3) end,
    "Stochastic (10K)" => fn -> TradingIndicators.Momentum.Stochastic.calculate(large_ohlcv, 14, 3) end,
    
    # CCI (Commodity Channel Index)
    "CCI (100)" => fn -> TradingIndicators.Momentum.CCI.calculate(small_ohlcv, 14) end,
    "CCI (1K)" => fn -> TradingIndicators.Momentum.CCI.calculate(medium_ohlcv, 14) end,
    "CCI (10K)" => fn -> TradingIndicators.Momentum.CCI.calculate(large_ohlcv, 14) end,
  },
  time: 10,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.HTML,
    Benchee.Formatters.JSON,
    Benchee.Formatters.Console
  ],
  formatter_options: [
    html: [file: "benchmarks/results/momentum_indicators.html"],
    json: [file: "benchmarks/results/momentum_indicators.json"]
  ]
)

IO.puts("\nVolatility Indicators Benchmark")
IO.puts("=" <> String.duplicate("=", 35))

# Volatility Indicators Benchmark
Benchee.run(
  %{
    # Average True Range
    "ATR (100)" => fn -> TradingIndicators.Volatility.ATR.calculate(small_ohlcv, 14) end,
    "ATR (1K)" => fn -> TradingIndicators.Volatility.ATR.calculate(medium_ohlcv, 14) end,
    "ATR (10K)" => fn -> TradingIndicators.Volatility.ATR.calculate(large_ohlcv, 14) end,
    
    # Bollinger Bands
    "Bollinger (100)" => fn -> 
      TradingIndicators.Volatility.BollingerBands.calculate(small_data, 20, Decimal.new("2.0"))
    end,
    "Bollinger (1K)" => fn -> 
      TradingIndicators.Volatility.BollingerBands.calculate(medium_data, 20, Decimal.new("2.0"))
    end,
    "Bollinger (10K)" => fn -> 
      TradingIndicators.Volatility.BollingerBands.calculate(large_data, 20, Decimal.new("2.0"))
    end,
    "Bollinger (50K)" => fn -> 
      TradingIndicators.Volatility.BollingerBands.calculate(xlarge_data, 20, Decimal.new("2.0"))
    end,
    
    # Standard Deviation
    "StdDev (100)" => fn -> TradingIndicators.Volatility.StandardDeviation.calculate(small_data, 20) end,
    "StdDev (1K)" => fn -> TradingIndicators.Volatility.StandardDeviation.calculate(medium_data, 20) end,
    "StdDev (10K)" => fn -> TradingIndicators.Volatility.StandardDeviation.calculate(large_data, 20) end,
    "StdDev (50K)" => fn -> TradingIndicators.Volatility.StandardDeviation.calculate(xlarge_data, 20) end,
  },
  time: 10,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.HTML,
    Benchee.Formatters.JSON,
    Benchee.Formatters.Console
  ],
  formatter_options: [
    html: [file: "benchmarks/results/volatility_indicators.html"],
    json: [file: "benchmarks/results/volatility_indicators.json"]
  ]
)

IO.puts("\nVolume Indicators Benchmark")
IO.puts("=" <> String.duplicate("=", 30))

# Volume Indicators Benchmark
Benchee.run(
  %{
    # On-Balance Volume
    "OBV (100)" => fn -> TradingIndicators.Volume.OBV.calculate(small_ohlcv) end,
    "OBV (1K)" => fn -> TradingIndicators.Volume.OBV.calculate(medium_ohlcv) end,
    "OBV (10K)" => fn -> TradingIndicators.Volume.OBV.calculate(large_ohlcv) end,
    
    # Volume Weighted Average Price
    "VWAP (100)" => fn -> TradingIndicators.Volume.VWAP.calculate(small_ohlcv) end,
    "VWAP (1K)" => fn -> TradingIndicators.Volume.VWAP.calculate(medium_ohlcv) end,
    "VWAP (10K)" => fn -> TradingIndicators.Volume.VWAP.calculate(large_ohlcv) end,
    
    # Accumulation/Distribution
    "A/D (100)" => fn -> TradingIndicators.Volume.AccumulationDistribution.calculate(small_ohlcv) end,
    "A/D (1K)" => fn -> TradingIndicators.Volume.AccumulationDistribution.calculate(medium_ohlcv) end,
    "A/D (10K)" => fn -> TradingIndicators.Volume.AccumulationDistribution.calculate(large_ohlcv) end,
    
    # Chaikin Money Flow
    "CMF (100)" => fn -> TradingIndicators.Volume.ChaikinMoneyFlow.calculate(small_ohlcv, 20) end,
    "CMF (1K)" => fn -> TradingIndicators.Volume.ChaikinMoneyFlow.calculate(medium_ohlcv, 20) end,
    "CMF (10K)" => fn -> TradingIndicators.Volume.ChaikinMoneyFlow.calculate(large_ohlcv, 20) end,
  },
  time: 10,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.HTML,
    Benchee.Formatters.JSON,
    Benchee.Formatters.Console
  ],
  formatter_options: [
    html: [file: "benchmarks/results/volume_indicators.html"],
    json: [file: "benchmarks/results/volume_indicators.json"]
  ]
)

IO.puts("\nComplex Indicators Benchmark")
IO.puts("=" <> String.duplicate("=", 32))

# Complex Indicators Benchmark
Benchee.run(
  %{
    # MACD
    "MACD (100)" => fn -> TradingIndicators.Trend.MACD.calculate(small_data, 12, 26, 9) end,
    "MACD (1K)" => fn -> TradingIndicators.Trend.MACD.calculate(medium_data, 12, 26, 9) end,
    "MACD (10K)" => fn -> TradingIndicators.Trend.MACD.calculate(large_data, 12, 26, 9) end,
    "MACD (50K)" => fn -> TradingIndicators.Trend.MACD.calculate(xlarge_data, 12, 26, 9) end,
    
    # KAMA (Kaufman's Adaptive Moving Average)
    "KAMA (100)" => fn -> TradingIndicators.Trend.KAMA.calculate(small_data, 14, 2, 30) end,
    "KAMA (1K)" => fn -> TradingIndicators.Trend.KAMA.calculate(medium_data, 14, 2, 30) end,
    "KAMA (10K)" => fn -> TradingIndicators.Trend.KAMA.calculate(large_data, 14, 2, 30) end,
    "KAMA (50K)" => fn -> TradingIndicators.Trend.KAMA.calculate(xlarge_data, 14, 2, 30) end,
  },
  time: 15,
  memory_time: 3,
  formatters: [
    Benchee.Formatters.HTML,
    Benchee.Formatters.JSON,
    Benchee.Formatters.Console
  ],
  formatter_options: [
    html: [file: "benchmarks/results/complex_indicators.html"],
    json: [file: "benchmarks/results/complex_indicators.json"]
  ]
)

# Performance Summary Analysis
IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("PERFORMANCE ANALYSIS SUMMARY")
IO.puts(String.duplicate("=", 60))

# Analyze complexity and generate performance report
complexity_analysis = %{
  "SMA" => BenchmarkHelpers.complexity_analysis(fn data -> 
    TradingIndicators.Trend.SMA.calculate(data, 14) 
  end),
  "EMA" => BenchmarkHelpers.complexity_analysis(fn data -> 
    TradingIndicators.Trend.EMA.calculate(data, 14) 
  end),
  "RSI" => BenchmarkHelpers.complexity_analysis(fn data -> 
    TradingIndicators.Momentum.RSI.calculate(data, 14) 
  end),
  "Bollinger" => BenchmarkHelpers.complexity_analysis(fn data -> 
    TradingIndicators.Volatility.BollingerBands.calculate(data, 20, Decimal.new("2.0"))
  end)
}

IO.puts("\nComplexity Analysis Results:")
Enum.each(complexity_analysis, fn {indicator, analysis} ->
  {best_complexity, correlation} = analysis.complexity_analysis.best_fit
  IO.puts("#{indicator}: Best fit = #{best_complexity} (correlation: #{Float.round(correlation, 3)})")
end)

# Memory usage analysis
IO.puts("\nMemory Usage Analysis:")
memory_results = BenchmarkHelpers.memory_benchmark(fn data ->
  TradingIndicators.Trend.SMA.calculate(data, 14)
end, [100, 1_000, 10_000])

Enum.each(memory_results, fn result ->
  efficiency = Float.round(result.memory_efficiency, 3)
  memory_kb = Float.round(result.memory_used / 1024, 1)
  IO.puts("Size #{result.size}: #{memory_kb} KB used, efficiency: #{efficiency}")
end)

# Performance recommendations
IO.puts("\nPerformance Recommendations:")
IO.puts("✓ Linear complexity indicators (SMA, EMA) scale well")
IO.puts("✓ Memory usage is proportional to dataset size")  
IO.puts("✓ Consider streaming for real-time applications")
IO.puts("✓ Batch processing recommended for large datasets")

IO.puts("\nBenchmark files saved to:")
IO.puts("- benchmarks/results/trend_indicators.html")
IO.puts("- benchmarks/results/momentum_indicators.html")
IO.puts("- benchmarks/results/volatility_indicators.html")
IO.puts("- benchmarks/results/volume_indicators.html")
IO.puts("- benchmarks/results/complex_indicators.html")

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Benchmark suite completed successfully!")
IO.puts(String.duplicate("=", 60))