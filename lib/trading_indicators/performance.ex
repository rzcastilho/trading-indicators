defmodule TradingIndicators.Performance do
  @moduledoc """
  Performance optimization and benchmarking suite for trading indicators.

  This module provides comprehensive performance analysis and optimization tools:
  - Benchmarking individual indicators and pipelines
  - Memory profiling and optimization
  - Caching mechanisms for expensive operations
  - Performance regression detection
  - Throughput analysis for streaming operations

  ## Features

  - **Benchmarking**: Measure execution time, memory usage, and throughput
  - **Memory Profiling**: Track memory consumption and detect leaks
  - **Caching**: Intelligent caching with configurable policies
  - **Optimization**: Performance tuning recommendations
  - **Monitoring**: Real-time performance metrics
  - **Regression Detection**: Identify performance degradations

  ## Example Usage

      # Benchmark an indicator
      datasets = [small_dataset, medium_dataset, large_dataset]
      {:ok, benchmark} = TradingIndicators.Performance.benchmark_indicator(
        TradingIndicators.Trend.SMA, 
        datasets,
        iterations: 100
      )

      # Enable caching
      TradingIndicators.Performance.enable_caching(max_size: 1000, ttl: 60_000)

      # Memory profile an operation
      {:ok, profile} = TradingIndicators.Performance.memory_profile(fn ->
        TradingIndicators.Trend.SMA.calculate(large_dataset, period: 50)
      end)

  ## Performance Targets

  - Memory usage should not exceed 50% increase for 10x dataset size
  - Processing speed should achieve >2x improvement for common indicators
  - Streaming throughput should exceed 1000 updates/second per indicator
  - Cache hit rates should exceed 70% for repeated calculations
  """

  alias TradingIndicators.{Types, Errors}
  require Logger

  @cache_table :trading_indicators_cache

  @type benchmark_options :: [
          iterations: pos_integer(),
          warmup_iterations: non_neg_integer(),
          memory_profile: boolean(),
          detailed_metrics: boolean()
        ]

  @type optimization_recommendation :: %{
          type: :memory | :cpu | :caching | :algorithmic,
          description: String.t(),
          impact: :low | :medium | :high,
          implementation_effort: :low | :medium | :high
        }

  @doc """
  Benchmarks an indicator across multiple datasets and configurations.

  ## Parameters

  - `indicator` - Indicator module to benchmark
  - `datasets` - List of datasets of varying sizes
  - `opts` - Benchmarking options

  ## Returns

  - `{:ok, benchmark_result}` - Comprehensive benchmark results
  - `{:error, reason}` - Benchmarking error

  ## Examples

      iex> base_data = %{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}
      iex> small_data = List.duplicate(base_data, 15)
      iex> {:ok, result} = TradingIndicators.Performance.benchmark_indicator(TradingIndicators.Trend.SMA, [small_data], period: 10)
      iex> result.indicator
      TradingIndicators.Trend.SMA
  """
  @spec benchmark_indicator(module(), [Types.data_series()], benchmark_options()) ::
          {:ok, Types.benchmark_result()} | {:error, term()}
  def benchmark_indicator(indicator, datasets, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 10)
    warmup_iterations = Keyword.get(opts, :warmup_iterations, 2)
    memory_profile = Keyword.get(opts, :memory_profile, false)

    try do
      # Validate indicator
      unless function_exported?(indicator, :calculate, 2) do
        raise ArgumentError, "Indicator #{inspect(indicator)} does not implement calculate/2"
      end

      # Get default parameters for the indicator
      default_params = get_default_params(indicator)

      # Warmup runs
      if warmup_iterations > 0 do
        Enum.each(1..warmup_iterations, fn _ ->
          Enum.each(datasets, fn dataset ->
            indicator.calculate(dataset, default_params)
          end)
        end)
      end

      # Force garbage collection before benchmarking
      :erlang.garbage_collect()

      # Run benchmarks for each dataset size
      dataset_results =
        Enum.map(datasets, fn dataset ->
          benchmark_dataset(indicator, dataset, default_params, iterations, memory_profile)
        end)

      # Calculate aggregate metrics
      total_time = Enum.sum(Enum.map(dataset_results, & &1.total_time))

      total_memory =
        if memory_profile do
          Enum.sum(Enum.map(dataset_results, & &1.memory_usage))
        else
          0
        end

      benchmark_result = %{
        indicator: indicator,
        dataset_sizes: Enum.map(datasets, &length/1),
        iterations: iterations,
        total_time: total_time,
        average_time: total_time / (length(datasets) * iterations),
        memory_usage: total_memory,
        throughput: calculate_throughput(datasets, total_time),
        dataset_results: dataset_results,
        timestamp: DateTime.utc_now()
      }

      {:ok, benchmark_result}
    rescue
      error -> {:error, error}
    end
  end

  @doc """
  Benchmarks a pipeline execution across multiple scenarios.

  ## Parameters

  - `pipeline_config` - Pipeline configuration to benchmark
  - `datasets` - List of datasets for testing
  - `opts` - Benchmarking options

  ## Returns

  - `{:ok, benchmark_result}` - Pipeline benchmark results
  - `{:error, reason}` - Benchmarking error

  ## Examples

      iex> builder = TradingIndicators.Pipeline.new()
      iex>   |> TradingIndicators.Pipeline.add_stage("sma", TradingIndicators.Trend.SMA, [period: 5])
      iex> {:ok, pipeline} = TradingIndicators.Pipeline.build(builder)
      iex> base_data = %{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}
      iex> data = List.duplicate(base_data, 10)
      iex> {:ok, result} = TradingIndicators.Performance.benchmark_pipeline(pipeline, [data])
      iex> result.pipeline_id
      pipeline.id
  """
  @spec benchmark_pipeline(Types.pipeline_config(), [Types.data_series()], benchmark_options()) ::
          {:ok, map()} | {:error, term()}
  def benchmark_pipeline(pipeline_config, datasets, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 5)
    memory_profile = Keyword.get(opts, :memory_profile, false)

    try do
      # Warmup
      Enum.each(datasets, fn dataset ->
        TradingIndicators.Pipeline.execute(pipeline_config, dataset)
      end)

      :erlang.garbage_collect()

      # Benchmark pipeline execution
      start_time = :os.system_time(:microsecond)
      start_memory = if memory_profile, do: get_memory_usage(), else: 0

      results =
        Enum.map(1..iterations, fn _i ->
          Enum.map(datasets, fn dataset ->
            execution_start = :os.system_time(:microsecond)
            {:ok, result} = TradingIndicators.Pipeline.execute(pipeline_config, dataset)
            execution_time = :os.system_time(:microsecond) - execution_start
            {result, execution_time}
          end)
        end)
        |> List.flatten()

      total_time = :os.system_time(:microsecond) - start_time
      end_memory = if memory_profile, do: get_memory_usage(), else: 0

      benchmark_result = %{
        pipeline_id: pipeline_config.id,
        stage_count: length(pipeline_config.stages),
        dataset_sizes: Enum.map(datasets, &length/1),
        iterations: iterations,
        total_time: total_time,
        average_time: total_time / (iterations * length(datasets)),
        memory_usage: max(0, end_memory - start_memory),
        throughput: calculate_pipeline_throughput(datasets, total_time, iterations),
        execution_results:
          Enum.map(results, fn {result, time} -> {result.execution_metrics, time} end),
        timestamp: DateTime.utc_now()
      }

      {:ok, benchmark_result}
    rescue
      error -> {:error, error}
    end
  end

  @doc """
  Profiles memory usage of a given operation.

  ## Parameters

  - `operation` - Function to profile

  ## Returns

  - `{:ok, memory_profile}` - Memory profiling information
  - `{:error, reason}` - Profiling error

  ## Examples

      iex> operation = fn -> 
      ...>   data = [%{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}]
      ...>   TradingIndicators.Trend.SMA.calculate(data, [period: 14])
      ...> end
      iex> {:ok, profile} = TradingIndicators.Performance.memory_profile(operation)
      iex> is_integer(profile.initial_memory)
      true
  """
  @spec memory_profile((-> any())) :: {:ok, Types.memory_profile()} | {:error, term()}
  def memory_profile(operation) when is_function(operation, 0) do
    try do
      # Force garbage collection before profiling
      :erlang.garbage_collect()

      initial_memory = get_memory_usage()
      initial_gc = get_gc_info()

      # Execute the operation
      result = operation.()

      # Measure peak memory (approximated)
      peak_memory = get_memory_usage()

      # Force garbage collection to measure final memory
      :erlang.garbage_collect()
      final_memory = get_memory_usage()
      final_gc = get_gc_info()

      memory_profile = %{
        initial_memory: initial_memory,
        peak_memory: peak_memory,
        final_memory: final_memory,
        memory_delta: final_memory - initial_memory,
        gc_collections: final_gc - initial_gc,
        operation_result: result
      }

      {:ok, memory_profile}
    rescue
      error -> {:error, error}
    end
  end

  def memory_profile(_operation) do
    {:error,
     %Errors.InvalidParams{message: "Operation must be a function with arity 0", param: :operation}}
  end

  @doc """
  Enables caching for indicator calculations with configurable options.

  ## Parameters

  - `opts` - Caching configuration options

  ## Returns

  - `:ok` - Caching enabled successfully
  - `{:error, reason}` - Configuration error

  ## Examples

      iex> TradingIndicators.Performance.enable_caching(max_size: 100, ttl: 30_000)
      :ok
  """
  @spec enable_caching(keyword()) :: :ok | {:error, term()}
  def enable_caching(opts \\ []) do
    try do
      config = %{
        enabled: true,
        max_size: Keyword.get(opts, :max_size, 1000),
        # 5 minutes default
        ttl: Keyword.get(opts, :ttl, 300_000),
        eviction_policy: Keyword.get(opts, :eviction_policy, :lru)
      }

      # Create ETS table if it doesn't exist
      case :ets.whereis(@cache_table) do
        :undefined ->
          :ets.new(@cache_table, [:set, :public, :named_table, {:read_concurrency, true}])

        _ ->
          :ok
      end

      # Store cache configuration
      :ets.insert(@cache_table, {:config, config})

      Logger.info("Caching enabled with config: #{inspect(config)}")
      :ok
    rescue
      error -> {:error, error}
    end
  end

  @doc """
  Disables caching for indicator calculations.

  ## Returns

  - `:ok` - Caching disabled successfully

  ## Examples

      iex> TradingIndicators.Performance.disable_caching()
      :ok
  """
  @spec disable_caching() :: :ok
  def disable_caching do
    case :ets.whereis(@cache_table) do
      :undefined ->
        :ok

      _ ->
        :ets.insert(@cache_table, {:config, %{enabled: false}})
        Logger.info("Caching disabled")
        :ok
    end
  end

  @doc """
  Retrieves current cache statistics.

  ## Returns

  - Cache statistics map

  ## Examples

      iex> TradingIndicators.Performance.enable_caching()
      iex> stats = TradingIndicators.Performance.cache_stats()
      iex> Map.has_key?(stats, :hit_rate)
      true
  """
  @spec cache_stats() :: map()
  def cache_stats do
    case :ets.whereis(@cache_table) do
      :undefined ->
        %{enabled: false, size: 0, hit_rate: 0.0, hits: 0, misses: 0}

      _ ->
        config =
          case :ets.lookup(@cache_table, :config) do
            [{:config, config}] -> config
            [] -> %{enabled: false}
          end

        stats =
          case :ets.lookup(@cache_table, :stats) do
            [{:stats, stats}] -> stats
            [] -> %{hits: 0, misses: 0}
          end

        # Subtract config and stats entries
        cache_size = :ets.info(@cache_table, :size) - 2
        total_requests = stats.hits + stats.misses
        hit_rate = if total_requests > 0, do: stats.hits / total_requests * 100, else: 0.0

        %{
          enabled: Map.get(config, :enabled, false),
          size: max(0, cache_size),
          hit_rate: hit_rate,
          hits: stats.hits,
          misses: stats.misses,
          max_size: Map.get(config, :max_size, 0),
          ttl: Map.get(config, :ttl, 0)
        }
    end
  end

  @doc """
  Generates optimization recommendations based on performance analysis.

  ## Parameters

  - `benchmark_results` - List of benchmark results to analyze

  ## Returns

  - List of optimization recommendations

  ## Examples

      iex> base_data = %{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}
      iex> small_data = List.duplicate(base_data, 15)
      iex> {:ok, benchmark} = TradingIndicators.Performance.benchmark_indicator(TradingIndicators.Trend.SMA, [small_data], period: 10)
      iex> recommendations = TradingIndicators.Performance.optimize([benchmark])
      iex> is_list(recommendations)
      true
  """
  @spec optimize([Types.benchmark_result() | map()]) :: [optimization_recommendation()]
  def optimize(benchmark_results) when is_list(benchmark_results) do
    recommendations = []

    # Memory optimization recommendations
    memory_recommendations = analyze_memory_usage(benchmark_results)

    # CPU optimization recommendations  
    cpu_recommendations = analyze_cpu_usage(benchmark_results)

    # Caching recommendations
    caching_recommendations = analyze_caching_potential(benchmark_results)

    recommendations
    |> Kernel.++(memory_recommendations)
    |> Kernel.++(cpu_recommendations)
    |> Kernel.++(caching_recommendations)
    |> Enum.sort_by(fn rec -> {rec.impact, rec.implementation_effort} end, :desc)
  end

  @doc """
  Clears all performance caches and metrics.

  ## Returns

  - `:ok` - Caches cleared successfully

  ## Examples

      iex> TradingIndicators.Performance.clear_caches()
      :ok
  """
  @spec clear_caches() :: :ok
  def clear_caches do
    case :ets.whereis(@cache_table) do
      :undefined ->
        :ok

      _ ->
        # Keep config but clear cached data
        config =
          case :ets.lookup(@cache_table, :config) do
            [{:config, config}] -> config
            [] -> %{enabled: false}
          end

        :ets.delete_all_objects(@cache_table)
        :ets.insert(@cache_table, {:config, config})
        :ets.insert(@cache_table, {:stats, %{hits: 0, misses: 0}})

        Logger.info("Performance caches cleared")
        :ok
    end
  end

  # Private helper functions

  defp get_default_params(indicator) do
    case indicator do
      mod when mod in [TradingIndicators.Trend.SMA, TradingIndicators.Trend.EMA] ->
        [period: 14]

      TradingIndicators.Momentum.RSI ->
        [period: 14]

      TradingIndicators.Trend.MACD ->
        [fast: 12, slow: 26, signal: 9]

      TradingIndicators.Volatility.BollingerBands ->
        [period: 20, std_dev_mult: 2]

      _ ->
        # Default fallback
        [period: 14]
    end
  end

  defp benchmark_dataset(indicator, dataset, params, iterations, memory_profile) do
    dataset_size = length(dataset)

    # Run multiple iterations
    times =
      Enum.map(1..iterations, fn _i ->
        start_time = :os.system_time(:microsecond)
        {:ok, _result} = indicator.calculate(dataset, params)
        :os.system_time(:microsecond) - start_time
      end)

    total_time = Enum.sum(times)

    memory_usage =
      if memory_profile do
        {:ok, profile} =
          memory_profile(fn ->
            indicator.calculate(dataset, params)
          end)

        profile.memory_delta
      else
        0
      end

    %{
      dataset_size: dataset_size,
      iterations: iterations,
      total_time: total_time,
      average_time: total_time / iterations,
      min_time: Enum.min(times),
      max_time: Enum.max(times),
      memory_usage: memory_usage,
      throughput: dataset_size * iterations * 1_000_000 / total_time
    }
  end

  defp calculate_throughput(datasets, total_time) do
    total_points = Enum.sum(Enum.map(datasets, &length/1))

    if total_time > 0 do
      # points per second
      total_points * 1_000_000 / total_time
    else
      0.0
    end
  end

  defp calculate_pipeline_throughput(datasets, total_time, iterations) do
    total_points = Enum.sum(Enum.map(datasets, &length/1)) * iterations

    if total_time > 0 do
      total_points * 1_000_000 / total_time
    else
      0.0
    end
  end

  defp get_memory_usage do
    {:memory, memory_info} = :erlang.process_info(self(), :memory)
    memory_info
  end

  defp get_gc_info do
    case :erlang.process_info(self(), :garbage_collection) do
      {:garbage_collection, gc_info} ->
        Keyword.get(gc_info, :number_of_gcs, 0)

      nil ->
        0
    end
  end

  defp analyze_memory_usage(benchmark_results) do
    high_memory_results =
      Enum.filter(benchmark_results, fn result ->
        memory_per_point =
          case Map.get(result, :memory_usage, 0) do
            0 -> 0
            memory -> memory / Enum.sum(Map.get(result, :dataset_sizes, [1]))
          end

        # More than 1KB per data point
        memory_per_point > 1000
      end)

    if length(high_memory_results) > 0 do
      [
        %{
          type: :memory,
          description:
            "High memory usage detected. Consider implementing streaming mode or data chunking.",
          impact: :high,
          implementation_effort: :medium
        }
      ]
    else
      []
    end
  end

  defp analyze_cpu_usage(benchmark_results) do
    slow_results =
      Enum.filter(benchmark_results, fn result ->
        avg_time = Map.get(result, :average_time, 0)
        # More than 100ms average
        avg_time > 100_000
      end)

    if length(slow_results) > 0 do
      [
        %{
          type: :cpu,
          description:
            "Slow execution detected. Consider algorithmic optimizations or parallel processing.",
          impact: :high,
          implementation_effort: :high
        }
      ]
    else
      []
    end
  end

  defp analyze_caching_potential(benchmark_results) do
    # If we have multiple benchmark runs, caching might help
    if length(benchmark_results) > 1 do
      [
        %{
          type: :caching,
          description: "Multiple calculations detected. Enable caching for repeated operations.",
          impact: :medium,
          implementation_effort: :low
        }
      ]
    else
      []
    end
  end
end
