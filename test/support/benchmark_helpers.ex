defmodule TradingIndicators.TestSupport.BenchmarkHelpers do
  @moduledoc """
  Performance testing utilities and benchmark helpers.
  """

  alias TradingIndicators.TestSupport.DataGenerator

  @doc """
  Benchmarks an indicator with different dataset sizes.
  """
  def benchmark_scaling(indicator_fun, sizes \\ [100, 500, 1_000, 5_000, 10_000]) do
    benchmarks = %{}
    
    Enum.reduce(sizes, benchmarks, fn size, acc ->
      data = DataGenerator.sample_prices(size)
      
      benchmark_result = Benchee.run(%{
        "size_#{size}" => fn -> indicator_fun.(data) end
      }, 
      memory_time: 2,
      time: 5,
      print: [fast_warning: false],
      formatters: []
      )
      
      Map.put(acc, size, extract_benchmark_stats(benchmark_result))
    end)
  end

  @doc """
  Measures memory usage for different dataset sizes.
  """
  def memory_benchmark(indicator_fun, sizes \\ [100, 500, 1_000, 5_000]) do
    Enum.map(sizes, fn size ->
      data = DataGenerator.sample_prices(size)
      
      # Measure memory before
      :erlang.garbage_collect()
      memory_before = :erlang.process_info(self(), :memory) |> elem(1)
      
      # Run indicator
      result = indicator_fun.(data)
      
      # Measure memory after
      :erlang.garbage_collect()
      memory_after = :erlang.process_info(self(), :memory) |> elem(1)
      
      # Calculate additional memory metrics
      result_size = :erlang.external_size(result)
      input_size = :erlang.external_size(data)
      
      %{
        size: size,
        memory_used: memory_after - memory_before,
        result_size: result_size,
        input_size: input_size,
        memory_efficiency: result_size / input_size
      }
    end)
  end

  @doc """
  Performance regression testing - compares current performance with baseline.
  """
  def regression_test(indicator_fun, baseline_times, tolerance \\ 1.2) do
    current_results = benchmark_scaling(indicator_fun)
    
    Enum.map(baseline_times, fn {size, baseline_time} ->
      current_time = get_in(current_results, [size, :median_time])
      
      if current_time do
        regression_factor = current_time / baseline_time
        
        %{
          size: size,
          baseline_time: baseline_time,
          current_time: current_time,
          regression_factor: regression_factor,
          within_tolerance: regression_factor <= tolerance,
          status: if(regression_factor <= tolerance, do: :pass, else: :fail)
        }
      else
        %{
          size: size,
          status: :missing_data
        }
      end
    end)
  end

  @doc """
  Benchmarks all indicators for comparison analysis.
  """
  def comparative_benchmark do
    data_sizes = [100, 500, 1_000]
    
    indicators = %{
      "SMA" => fn data -> TradingIndicators.Trend.SMA.calculate(data, period: 14) end,
      "EMA" => fn data -> TradingIndicators.Trend.EMA.calculate(data, period: 14) end,
      "RSI" => fn data -> TradingIndicators.Momentum.RSI.calculate(data, period: 14) end,
      "Bollinger Bands" => fn data -> 
        TradingIndicators.Volatility.BollingerBands.calculate(data, period: 20, multiplier: Decimal.new("2.0"))
      end,
      "MACD" => fn data -> 
        TradingIndicators.Trend.MACD.calculate(data, fast_period: 12, slow_period: 26, signal_period: 9)
      end
    }
    
    Enum.reduce(data_sizes, %{}, fn size, acc ->
      data = DataGenerator.sample_prices(size)
      
      size_results = Enum.reduce(indicators, %{}, fn {name, fun}, size_acc ->
        try do
          {result, time} = :timer.tc(fun, [data])
          
          Map.put(size_acc, name, %{
            time_microseconds: time,
            memory_used: :erlang.process_info(self(), :memory) |> elem(1),
            result_length: length(result),
            success: true
          })
        rescue
          error ->
            Map.put(size_acc, name, %{
              error: error,
              success: false
            })
        end
      end)
      
      Map.put(acc, size, size_results)
    end)
  end

  @doc """
  Stress test with increasingly complex scenarios.
  """
  def stress_test(indicator_fun, scenarios \\ nil) do
    scenarios = scenarios || default_stress_scenarios()
    
    Enum.map(scenarios, fn scenario ->
      try do
        {result, time} = :timer.tc(fn -> 
          indicator_fun.(scenario.data) 
        end)
        
        %{
          scenario: scenario.name,
          data_size: length(scenario.data),
          execution_time: time,
          memory_used: measure_memory_usage(fn -> indicator_fun.(scenario.data) end),
          result_length: length(result),
          success: true
        }
      rescue
        error ->
          %{
            scenario: scenario.name,
            data_size: length(scenario.data),
            error: error,
            success: false
          }
      end
    end)
  end

  @doc """
  Measures computation complexity (Big O analysis).
  """
  def complexity_analysis(indicator_fun, sizes \\ [10, 50, 100, 500, 1_000]) do
    results = Enum.map(sizes, fn size ->
      data = DataGenerator.sample_prices(size)
      {_result, time} = :timer.tc(indicator_fun, [data])
      {size, time}
    end)
    
    # Simple linear regression to estimate complexity
    n_values = Enum.map(results, &elem(&1, 0))
    time_values = Enum.map(results, &elem(&1, 1))
    
    # Calculate correlation with different complexity functions
    linear_correlation = correlation(n_values, time_values)
    quadratic_correlation = correlation(Enum.map(n_values, &(&1 * &1)), time_values)
    log_correlation = correlation(Enum.map(n_values, &(:math.log(&1))), time_values)
    nlogn_correlation = correlation(Enum.map(n_values, &(&1 * :math.log(&1))), time_values)
    
    best_fit = Enum.max_by([
      {:linear, linear_correlation},
      {:quadratic, quadratic_correlation},
      {:logarithmic, log_correlation},
      {:nlogn, nlogn_correlation}
    ], &elem(&1, 1))
    
    %{
      measurements: results,
      complexity_analysis: %{
        linear: linear_correlation,
        quadratic: quadratic_correlation,
        logarithmic: log_correlation,
        nlogn: nlogn_correlation,
        best_fit: best_fit
      }
    }
  end

  @doc """
  Creates a performance report with recommendations.
  """
  def performance_report(indicator_fun, indicator_name) do
    scaling_results = benchmark_scaling(indicator_fun)
    memory_results = memory_benchmark(indicator_fun)
    complexity_results = complexity_analysis(indicator_fun)
    
    # Performance thresholds
    acceptable_time_1k = 1_000_000 # 1 second for 1k data points
    acceptable_memory_mb = 100 # 100MB
    
    # Analyze results
    performance_1k = get_in(scaling_results, [1_000, :median_time]) || 0
    memory_1k = Enum.find(memory_results, &(&1.size == 1_000))
    
    recommendations = []
    
    recommendations = if performance_1k > acceptable_time_1k do
      ["Performance optimization recommended - exceeding 1s for 1k data points" | recommendations]
    else
      recommendations
    end
    
    recommendations = if memory_1k && memory_1k.memory_used > (acceptable_memory_mb * 1_024 * 1_024) do
      ["Memory optimization recommended - exceeding 100MB for 1k data points" | recommendations]
    else
      recommendations
    end
    
    %{
      indicator: indicator_name,
      scaling_performance: scaling_results,
      memory_usage: memory_results,
      complexity: complexity_results,
      recommendations: recommendations,
      overall_rating: calculate_performance_rating(performance_1k, memory_1k)
    }
  end

  # Private helper functions
  
  defp extract_benchmark_stats(benchmark_result) do
    case benchmark_result do
      %{scenarios: scenarios} ->
        scenario = scenarios |> Map.values() |> hd()
        %{
          median_time: scenario.run_time_data.statistics.median,
          mean_time: scenario.run_time_data.statistics.average,
          std_dev: scenario.run_time_data.statistics.std_dev,
          memory: Map.get(scenario, :memory_usage_data, %{})
        }
      _ ->
        %{error: "Unable to extract benchmark statistics"}
    end
  end

  defp measure_memory_usage(fun) do
    :erlang.garbage_collect()
    memory_before = :erlang.process_info(self(), :memory) |> elem(1)
    
    _result = fun.()
    
    :erlang.garbage_collect()
    memory_after = :erlang.process_info(self(), :memory) |> elem(1)
    
    memory_after - memory_before
  end

  defp default_stress_scenarios do
    [
      %{
        name: "large_dataset",
        data: DataGenerator.sample_prices(10_000)
      },
      %{
        name: "extreme_volatility",
        data: generate_extreme_volatility_data(1_000)
      },
      %{
        name: "constant_values",
        data: List.duplicate(Decimal.new("100.0"), 1_000)
      },
      %{
        name: "alternating_extremes",
        data: Stream.cycle([Decimal.new("1.0"), Decimal.new("1000.0")]) 
              |> Enum.take(1_000)
      }
    ]
  end

  defp generate_extreme_volatility_data(size) do
    base_price = 100.0
    
    1..size
    |> Enum.map(fn _i ->
      # Extreme volatility
      variation = (:rand.uniform() - 0.5) * 0.5 # +/- 25% variation
      price = base_price * (1 + variation)
      Decimal.from_float(Float.round(max(price, 0.01), 2))
    end)
  end

  defp correlation(x_values, y_values) do
    n = length(x_values)
    
    if n < 2 do
      0.0
    else
      x_mean = Enum.sum(x_values) / n
      y_mean = Enum.sum(y_values) / n
      
      numerator = Enum.zip(x_values, y_values)
                  |> Enum.map(fn {x, y} -> (x - x_mean) * (y - y_mean) end)
                  |> Enum.sum()
      
      x_variance = Enum.map(x_values, fn x -> :math.pow(x - x_mean, 2) end) |> Enum.sum()
      y_variance = Enum.map(y_values, fn y -> :math.pow(y - y_mean, 2) end) |> Enum.sum()
      
      denominator = :math.sqrt(x_variance * y_variance)
      
      if denominator == 0, do: 0.0, else: numerator / denominator
    end
  end

  defp calculate_performance_rating(performance_time, memory_result) do
    # Simple rating system (1-5 stars)
    time_rating = cond do
      performance_time < 100_000 -> 5  # < 100ms
      performance_time < 500_000 -> 4  # < 500ms  
      performance_time < 1_000_000 -> 3 # < 1s
      performance_time < 5_000_000 -> 2 # < 5s
      true -> 1
    end
    
    memory_rating = if memory_result do
      cond do
        memory_result.memory_used < 1_048_576 -> 5    # < 1MB
        memory_result.memory_used < 10_485_760 -> 4   # < 10MB
        memory_result.memory_used < 104_857_600 -> 3  # < 100MB
        memory_result.memory_used < 1_073_741_824 -> 2 # < 1GB
        true -> 1
      end
    else
      3 # Default if no memory data
    end
    
    # Average the ratings
    Float.round((time_rating + memory_rating) / 2, 1)
  end
end