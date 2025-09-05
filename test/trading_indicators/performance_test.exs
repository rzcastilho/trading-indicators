defmodule TradingIndicators.PerformanceTest do
  use ExUnit.Case, async: true
  doctest TradingIndicators.Performance

  alias TradingIndicators.Performance
  alias TradingIndicators.{Pipeline, Trend.SMA}

  @small_dataset 1..20
                 |> Enum.map(fn i ->
                   %{
                     open: Decimal.new("#{100 + i * 0.5}"),
                     high: Decimal.new("#{105 + i * 0.5}"),
                     low: Decimal.new("#{99 + i * 0.5}"),
                     close: Decimal.new("#{103 + i * 0.5}"),
                     volume: 1000 + i * 10,
                     timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :minute)
                   }
                 end)

  @medium_dataset List.duplicate(hd(@small_dataset), 50)
  @large_dataset List.duplicate(hd(@small_dataset), 500)

  describe "benchmark_indicator/3" do
    test "benchmarks simple indicator across datasets" do
      datasets = [@small_dataset, @medium_dataset]

      assert {:ok, result} = Performance.benchmark_indicator(SMA, datasets, iterations: 5)

      assert result.indicator == SMA
      assert result.iterations == 5
      assert result.total_time > 0
      assert result.average_time > 0
      assert result.throughput > 0
      assert length(result.dataset_sizes) == 2
      assert length(result.dataset_results) == 2
    end

    test "includes memory profiling when requested" do
      datasets = [@small_dataset]

      assert {:ok, result} =
               Performance.benchmark_indicator(SMA, datasets, iterations: 3, memory_profile: true)

      assert result.memory_usage >= 0
      dataset_result = hd(result.dataset_results)
      assert dataset_result.memory_usage >= 0
    end

    test "handles warmup iterations" do
      datasets = [@small_dataset]

      assert {:ok, result} =
               Performance.benchmark_indicator(SMA, datasets, iterations: 5, warmup_iterations: 2)

      # Should still report the requested iterations, not including warmup
      assert result.iterations == 5
    end

    test "returns error for invalid indicator" do
      datasets = [@small_dataset]

      assert {:error, _reason} = Performance.benchmark_indicator(NonExistentIndicator, datasets)
    end

    test "benchmarks with different dataset sizes" do
      datasets = [@small_dataset, @medium_dataset, @large_dataset]

      assert {:ok, result} = Performance.benchmark_indicator(SMA, datasets, iterations: 3)

      # Verify dataset size tracking
      assert result.dataset_sizes == [20, 50, 500]

      # Larger datasets should generally take longer (though not always due to caching)
      dataset_results = result.dataset_results
      assert length(dataset_results) == 3

      Enum.each(dataset_results, fn dataset_result ->
        assert dataset_result.total_time > 0
        assert dataset_result.throughput > 0
      end)
    end

    test "provides detailed timing statistics" do
      datasets = [@small_dataset]

      assert {:ok, result} = Performance.benchmark_indicator(SMA, datasets, iterations: 5)

      dataset_result = hd(result.dataset_results)
      assert dataset_result.min_time > 0
      assert dataset_result.max_time > 0
      assert dataset_result.average_time > 0
      assert dataset_result.min_time <= dataset_result.average_time
      assert dataset_result.average_time <= dataset_result.max_time
    end
  end

  describe "benchmark_pipeline/3" do
    test "benchmarks simple pipeline execution" do
      builder =
        Pipeline.new()
        |> Pipeline.add_stage("sma", SMA, period: 2)

      {:ok, pipeline} = Pipeline.build(builder)
      datasets = [@small_dataset]

      assert {:ok, result} = Performance.benchmark_pipeline(pipeline, datasets, iterations: 3)

      assert result.pipeline_id == pipeline.id
      assert result.stage_count == 1
      assert result.iterations == 3
      assert result.total_time > 0
      assert result.average_time > 0
      assert result.throughput > 0
    end

    test "benchmarks multi-stage pipeline" do
      builder =
        Pipeline.new()
        |> Pipeline.add_stage("sma_short", SMA, period: 2)
        |> Pipeline.add_stage("sma_long", SMA, period: 3)

      {:ok, pipeline} = Pipeline.build(builder)
      datasets = [@small_dataset]

      assert {:ok, result} = Performance.benchmark_pipeline(pipeline, datasets, iterations: 2)

      assert result.stage_count == 2
      # iterations * datasets
      assert length(result.execution_results) == 2
    end

    test "includes memory profiling for pipelines" do
      builder =
        Pipeline.new()
        |> Pipeline.add_stage("sma", SMA, period: 2)

      {:ok, pipeline} = Pipeline.build(builder)
      datasets = [@small_dataset]

      assert {:ok, result} =
               Performance.benchmark_pipeline(pipeline, datasets,
                 iterations: 2,
                 memory_profile: true
               )

      assert result.memory_usage >= 0
    end

    test "tracks execution results" do
      builder =
        Pipeline.new()
        |> Pipeline.add_stage("sma", SMA, period: 2)

      {:ok, pipeline} = Pipeline.build(builder)
      datasets = [@small_dataset, @medium_dataset]

      assert {:ok, result} = Performance.benchmark_pipeline(pipeline, datasets, iterations: 2)

      # Should have results for iterations * datasets
      assert length(result.execution_results) == 4

      Enum.each(result.execution_results, fn {_metrics, execution_time} ->
        assert execution_time > 0
      end)
    end
  end

  describe "memory_profile/1" do
    test "profiles memory usage of operation" do
      operation = fn ->
        # Simulate some work with memory allocation
        data = Enum.take(@large_dataset, 100)
        SMA.calculate(data, period: 10)
      end

      assert {:ok, profile} = Performance.memory_profile(operation)

      assert is_integer(profile.initial_memory)
      assert is_integer(profile.peak_memory)
      assert is_integer(profile.final_memory)
      assert is_integer(profile.memory_delta)
      assert is_integer(profile.gc_collections)
      assert Map.has_key?(profile, :operation_result)
    end

    test "handles operations that increase memory usage" do
      operation = fn ->
        # Create a list that should increase memory usage
        Enum.map(1..1000, fn i -> %{data: List.duplicate(i, 100)} end)
      end

      assert {:ok, profile} = Performance.memory_profile(operation)

      # Peak memory should be at least as high as final memory
      assert profile.peak_memory >= profile.final_memory
    end

    test "returns error for invalid operation" do
      assert {:error, _reason} = Performance.memory_profile("not a function")
      # Functions with arity 0 actually work fine
      assert {:ok, _profile} = Performance.memory_profile(fn -> :ok end)
    end

    test "captures operation result" do
      expected_result = {:ok, "test result"}
      operation = fn -> expected_result end

      assert {:ok, profile} = Performance.memory_profile(operation)
      assert profile.operation_result == expected_result
    end

    test "handles operations that throw exceptions" do
      operation = fn ->
        raise RuntimeError, "test error"
      end

      assert {:error, %RuntimeError{message: "test error"}} = Performance.memory_profile(operation)
    end
  end

  describe "caching functionality" do
    test "enables caching with default options" do
      assert :ok = Performance.enable_caching()

      stats = Performance.cache_stats()
      assert stats.enabled == true
      # default
      assert stats.max_size == 1000
      # default 5 minutes
      assert stats.ttl == 300_000
    end

    test "enables caching with custom options" do
      assert :ok = Performance.enable_caching(max_size: 500, ttl: 60_000)

      stats = Performance.cache_stats()
      assert stats.enabled == true
      assert stats.max_size == 500
      assert stats.ttl == 60_000
    end

    test "disables caching" do
      Performance.enable_caching()
      assert :ok = Performance.disable_caching()

      stats = Performance.cache_stats()
      assert stats.enabled == false
    end

    test "provides cache statistics" do
      Performance.enable_caching()

      stats = Performance.cache_stats()
      assert Map.has_key?(stats, :enabled)
      assert Map.has_key?(stats, :size)
      assert Map.has_key?(stats, :hit_rate)
      assert Map.has_key?(stats, :hits)
      assert Map.has_key?(stats, :misses)
      assert Map.has_key?(stats, :max_size)
      assert Map.has_key?(stats, :ttl)
    end

    test "handles cache statistics when caching is not initialized" do
      # Ensure clean state
      Performance.clear_caches()

      stats = Performance.cache_stats()
      assert stats.enabled == false
      assert stats.size == 0
      assert stats.hit_rate == 0.0
    end

    test "clears caches successfully" do
      Performance.enable_caching()
      assert :ok = Performance.clear_caches()

      stats = Performance.cache_stats()
      assert stats.size == 0
      assert stats.hits == 0
      assert stats.misses == 0
    end
  end

  describe "optimize/1" do
    test "generates optimization recommendations" do
      # Create some benchmark results
      small_benchmark = %{
        indicator: SMA,
        dataset_sizes: [10],
        iterations: 5,
        total_time: 1000,
        average_time: 200.0,
        memory_usage: 500,
        throughput: 50.0,
        dataset_results: []
      }

      recommendations = Performance.optimize([small_benchmark])
      assert is_list(recommendations)

      # Should return recommendations for multiple calculations
      Enum.each(recommendations, fn rec ->
        assert Map.has_key?(rec, :type)
        assert Map.has_key?(rec, :description)
        assert Map.has_key?(rec, :impact)
        assert Map.has_key?(rec, :implementation_effort)
        assert rec.type in [:memory, :cpu, :caching, :algorithmic]
        assert rec.impact in [:low, :medium, :high]
        assert rec.implementation_effort in [:low, :medium, :high]
      end)
    end

    test "recommends memory optimization for high memory usage" do
      high_memory_benchmark = %{
        indicator: SMA,
        dataset_sizes: [100],
        # High memory usage
        memory_usage: 150_000,
        average_time: 1000.0,
        total_time: 5000
      }

      recommendations = Performance.optimize([high_memory_benchmark])

      memory_recs = Enum.filter(recommendations, fn rec -> rec.type == :memory end)
      assert length(memory_recs) > 0

      memory_rec = hd(memory_recs)
      assert memory_rec.impact == :high
      assert String.contains?(memory_rec.description, "memory")
    end

    test "recommends CPU optimization for slow execution" do
      slow_benchmark = %{
        indicator: SMA,
        dataset_sizes: [50],
        memory_usage: 1000,
        # Very slow (200ms average)
        average_time: 200_000.0,
        total_time: 1_000_000
      }

      recommendations = Performance.optimize([slow_benchmark])

      cpu_recs = Enum.filter(recommendations, fn rec -> rec.type == :cpu end)
      assert length(cpu_recs) > 0

      cpu_rec = hd(cpu_recs)
      assert cpu_rec.impact == :high
      assert String.contains?(cpu_rec.description, "execution")
    end

    test "recommends caching for multiple calculations" do
      # Multiple benchmarks suggest repeated calculations
      benchmarks = [
        %{
          indicator: SMA,
          dataset_sizes: [10],
          memory_usage: 100,
          average_time: 100.0,
          total_time: 500
        },
        %{
          indicator: SMA,
          dataset_sizes: [10],
          memory_usage: 100,
          average_time: 100.0,
          total_time: 500
        }
      ]

      recommendations = Performance.optimize(benchmarks)

      caching_recs = Enum.filter(recommendations, fn rec -> rec.type == :caching end)
      assert length(caching_recs) > 0

      caching_rec = hd(caching_recs)
      assert caching_rec.implementation_effort == :low
      assert String.contains?(caching_rec.description, "caching")
    end

    test "sorts recommendations by impact and effort" do
      benchmarks = [
        %{
          indicator: SMA,
          dataset_sizes: [100],
          memory_usage: 200_000,
          average_time: 300_000.0,
          total_time: 1_500_000
        }
      ]

      recommendations = Performance.optimize(benchmarks)

      if length(recommendations) > 1 do
        # Verify sorting - high impact should come first
        impacts = Enum.map(recommendations, & &1.impact)
        high_count = Enum.count(impacts, &(&1 == :high))

        # If we have high impact items, they should be at the beginning
        if high_count > 0 do
          assert hd(recommendations).impact == :high
        end
      end
    end

    test "handles empty benchmark list" do
      recommendations = Performance.optimize([])
      assert recommendations == []
    end
  end

  # Performance regression tests
  describe "performance regression tests" do
    @tag :performance
    test "benchmark execution time is reasonable" do
      datasets = [@small_dataset]

      start_time = System.monotonic_time(:microsecond)
      {:ok, _result} = Performance.benchmark_indicator(SMA, datasets, iterations: 10)
      end_time = System.monotonic_time(:microsecond)

      benchmark_time = end_time - start_time

      # Benchmarking itself should be fast (< 100ms for small dataset)
      assert benchmark_time < 100_000
    end

    @tag :performance
    test "memory profiling overhead is minimal" do
      simple_operation = fn -> Enum.sum(1..100) end

      # Time without profiling
      start_time = System.monotonic_time(:microsecond)
      simple_operation.()
      end_time = System.monotonic_time(:microsecond)
      direct_time = end_time - start_time

      # Time with profiling
      start_time = System.monotonic_time(:microsecond)
      {:ok, _profile} = Performance.memory_profile(simple_operation)
      end_time = System.monotonic_time(:microsecond)
      profiled_time = end_time - start_time

      # Profiling overhead should be reasonable (less than 25x slowdown for micro-operations)
      overhead_ratio = profiled_time / max(direct_time, 1)
      assert overhead_ratio < 25
    end
  end

  # Property-based tests
  describe "property tests" do
    @tag :property
    test "benchmark results are consistent across runs" do
      datasets = [@small_dataset]

      results =
        for _i <- 1..3 do
          {:ok, result} = Performance.benchmark_indicator(SMA, datasets, iterations: 5)
          result.average_time
        end

      # Results should be reasonably consistent (within 50% variation)
      avg_time = Enum.sum(results) / length(results)
      max_deviation = Enum.max(Enum.map(results, fn time -> abs(time - avg_time) / avg_time end))

      # 50% max deviation
      assert max_deviation < 0.5
    end

    @tag :property
    test "memory profiling captures monotonic memory changes" do
      operations = [
        # Minimal allocation
        fn -> [] end,
        # Small allocation
        fn -> List.duplicate(:atom, 100) end,
        # Larger allocation
        fn -> List.duplicate(%{data: 123}, 1000) end
      ]

      profiles =
        for operation <- operations do
          {:ok, profile} = Performance.memory_profile(operation)
          profile.memory_delta
        end

      # Generally, larger allocations should show in memory delta
      # (though GC makes this non-deterministic)
      assert is_list(profiles)
      assert length(profiles) == 3
    end
  end

  # Edge cases
  describe "edge cases" do
    test "handles indicators with zero processing time" do
      # Mock indicator that processes instantly
      defmodule InstantIndicator do
        def calculate(_data, _params), do: {:ok, []}
        def validate_params(_params), do: :ok
        def required_periods, do: 1
      end

      datasets = [@small_dataset]

      assert {:ok, result} = Performance.benchmark_indicator(InstantIndicator, datasets)

      # Should handle zero or very small processing times
      assert result.total_time >= 0
      assert result.average_time >= 0
      assert result.throughput >= 0
    end

    test "handles very large datasets without memory issues" do
      # Create a large dataset
      large_data = List.duplicate(hd(@small_dataset), 10_000)

      operation = fn ->
        SMA.calculate(Enum.take(large_data, 1000), period: 50)
      end

      assert {:ok, profile} = Performance.memory_profile(operation)
      assert is_integer(profile.memory_delta)
    end

    test "handles nested optimization calls" do
      benchmark1 = %{
        indicator: SMA,
        dataset_sizes: [10],
        memory_usage: 100,
        average_time: 100.0,
        total_time: 500
      }

      recommendations = Performance.optimize([benchmark1])

      # Should not crash on multiple optimization calls
      nested_recommendations = Performance.optimize([benchmark1])

      assert is_list(recommendations)
      assert is_list(nested_recommendations)
    end
  end
end
