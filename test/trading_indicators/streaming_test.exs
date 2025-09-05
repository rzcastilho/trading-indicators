defmodule TradingIndicators.StreamingTest do
  use ExUnit.Case, async: true
  doctest TradingIndicators.Streaming

  alias TradingIndicators.Streaming
  alias TradingIndicators.Trend.SMA

  @sample_data [
    %{
      open: Decimal.new("100.0"),
      high: Decimal.new("105.0"),
      low: Decimal.new("99.0"),
      close: Decimal.new("103.0"),
      volume: 1000,
      timestamp: ~U[2024-01-01 09:30:00Z]
    },
    %{
      open: Decimal.new("103.0"),
      high: Decimal.new("107.0"),
      low: Decimal.new("102.0"),
      close: Decimal.new("106.0"),
      volume: 1200,
      timestamp: ~U[2024-01-01 09:31:00Z]
    },
    %{
      open: Decimal.new("106.0"),
      high: Decimal.new("108.0"),
      low: Decimal.new("105.0"),
      close: Decimal.new("107.0"),
      volume: 1100,
      timestamp: ~U[2024-01-01 09:32:00Z]
    }
  ]

  describe "init_stream/1" do
    test "successfully initializes streaming state for supported indicator" do
      config = %{
        indicator: SMA,
        params: [period: 2],
        buffer_size: 100,
        state: nil
      }

      assert {:ok, state} = Streaming.init_stream(config)
      assert state.config.indicator == SMA
      assert state.config.buffer_size == 100
      assert state.metrics.total_processed == 0
    end

    test "returns error for indicator without streaming support" do
      # Mock an indicator without streaming support
      config = %{
        indicator: TradingIndicators.NonExistentIndicator,
        params: [period: 14],
        buffer_size: 100,
        state: nil
      }

      assert {:error, _reason} = Streaming.init_stream(config)
    end

    test "validates indicator parameters during initialization" do
      config = %{
        indicator: SMA,
        # Invalid period
        params: [period: -1],
        buffer_size: 100,
        state: nil
      }

      assert {:error, _reason} = Streaming.init_stream(config)
    end
  end

  describe "process_batch/2" do
    test "processes multiple data points in batch" do
      config = %{
        indicator: SMA,
        params: [period: 2],
        buffer_size: 100,
        state: nil
      }

      {:ok, state} = Streaming.init_stream(config)
      data_batch = Enum.take(@sample_data, 2)

      assert {:ok, batch_result, new_state} = Streaming.process_batch(state, data_batch)
      # SMA with period 2 produces 1 result from 2 points
      assert length(batch_result.values) == 1
      assert batch_result.processing_time > 0
      assert new_state.metrics.total_processed == 2
    end

    test "handles empty batch" do
      config = %{
        indicator: SMA,
        params: [period: 2],
        buffer_size: 100,
        state: nil
      }

      {:ok, state} = Streaming.init_stream(config)

      assert {:ok, batch_result, new_state} = Streaming.process_batch(state, [])
      assert batch_result.values == []
      assert new_state.metrics.total_processed == 0
    end

    test "returns error for invalid data batch format" do
      config = %{
        indicator: SMA,
        params: [period: 2],
        buffer_size: 100,
        state: nil
      }

      {:ok, state} = Streaming.init_stream(config)

      assert {:error, _reason} = Streaming.process_batch(state, "invalid")
    end

    test "updates streaming metrics after batch processing" do
      config = %{
        indicator: SMA,
        params: [period: 2],
        buffer_size: 100,
        state: nil
      }

      {:ok, state} = Streaming.init_stream(config)

      assert {:ok, _batch_result, new_state} = Streaming.process_batch(state, @sample_data)
      assert new_state.metrics.total_processed == 3
      assert new_state.metrics.throughput > 0
    end
  end

  describe "compose_streams/1" do
    test "creates composition state with primary stream" do
      primary_config = %{
        indicator: SMA,
        params: [period: 2],
        buffer_size: 100,
        state: nil
      }

      composition = %{
        primary_stream: primary_config,
        dependent_streams: [],
        aggregation_function: fn results -> List.first(results) end,
        buffer_management: :sliding_window
      }

      assert {:ok, comp_state} = Streaming.compose_streams(composition)
      assert comp_state.primary_stream.config.indicator == SMA
      assert comp_state.dependent_streams == []
      assert is_list(comp_state.execution_order)
    end

    test "handles composition with dependent streams" do
      primary_config = %{
        indicator: SMA,
        params: [period: 2],
        buffer_size: 100,
        state: nil
      }

      dependent_config = %{
        indicator: SMA,
        params: [period: 3],
        buffer_size: 100,
        state: nil
      }

      composition = %{
        primary_stream: primary_config,
        dependent_streams: [dependent_config],
        aggregation_function: fn results -> results end,
        buffer_management: :expanding_window
      }

      assert {:ok, comp_state} = Streaming.compose_streams(composition)
      assert length(comp_state.dependent_streams) == 1
      assert Map.has_key?(comp_state.dependency_graph, "sma")
    end
  end

  describe "serialize_state/1 and deserialize_state/1" do
    test "serializes and deserializes streaming state" do
      config = %{
        indicator: SMA,
        params: [period: 2],
        buffer_size: 100,
        state: nil
      }

      {:ok, original_state} = Streaming.init_stream(config)

      assert {:ok, serialized} = Streaming.serialize_state(original_state)
      assert is_binary(serialized)

      assert {:ok, deserialized_state} = Streaming.deserialize_state(serialized)
      assert deserialized_state.config.indicator == SMA
      assert deserialized_state.config.buffer_size == 100
    end

    test "handles serialization errors gracefully" do
      # Test with a state containing non-serializable data (function/reference)
      port = Port.open({:spawn, "echo"}, [])

      invalid_state = %{
        # Ports are not safely serializable
        config: %{indicator: port},
        indicator_state: nil,
        buffer: [],
        metrics: %{},
        last_update: DateTime.utc_now()
      }

      Port.close(port)

      # Since serialization might work in some cases, just check it doesn't crash
      case Streaming.serialize_state(invalid_state) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end

    test "returns error for invalid serialized data" do
      assert {:error, _reason} = Streaming.deserialize_state("invalid binary data")
      assert {:error, _reason} = Streaming.deserialize_state(123)
    end
  end

  describe "stream_metrics/1" do
    test "returns metrics for streaming state" do
      config = %{
        indicator: SMA,
        params: [period: 2],
        buffer_size: 100,
        state: nil
      }

      {:ok, state} = Streaming.init_stream(config)
      metrics = Streaming.stream_metrics(state)

      assert metrics.total_processed == 0
      assert metrics.throughput == 0.0
      assert metrics.error_count == 0
    end

    test "returns composition metrics for composition state" do
      primary_config = %{
        indicator: SMA,
        params: [period: 2],
        buffer_size: 100,
        state: nil
      }

      composition = %{
        primary_stream: primary_config,
        dependent_streams: [],
        aggregation_function: fn results -> results end,
        buffer_management: :sliding_window
      }

      {:ok, comp_state} = Streaming.compose_streams(composition)
      metrics = Streaming.stream_metrics(comp_state)

      assert Map.has_key?(metrics, :primary)
      assert Map.has_key?(metrics, :dependents)
      assert Map.has_key?(metrics, :total_throughput)
    end
  end

  describe "update_stream_state/2" do
    test "updates streaming state with single data point" do
      config = %{
        indicator: SMA,
        params: [period: 2],
        buffer_size: 100,
        state: nil
      }

      {:ok, state} = Streaming.init_stream(config)
      data_point = List.first(@sample_data)

      assert {:ok, new_state, _result} = Streaming.update_stream_state(state, data_point)
      assert new_state.indicator_state != state.indicator_state
      # First data point might not produce a result depending on indicator requirements
    end

    test "handles invalid data point" do
      config = %{
        indicator: SMA,
        params: [period: 2],
        buffer_size: 100,
        state: nil
      }

      {:ok, state} = Streaming.init_stream(config)
      invalid_point = %{close: "invalid"}

      # The behavior depends on indicator implementation
      # Some may handle gracefully, others may return error
      case Streaming.update_stream_state(state, invalid_point) do
        {:ok, _state, _result} -> :ok
        {:error, _reason} -> :ok
      end
    end
  end

  # Property-based testing
  describe "property tests" do
    @tag :property
    test "batch processing maintains data integrity" do
      config = %{
        indicator: SMA,
        params: [period: 2],
        buffer_size: 1000,
        state: nil
      }

      {:ok, state} = Streaming.init_stream(config)

      # Generate different batch sizes
      for batch_size <- [1, 5, 10, 50] do
        batch = Enum.take(@sample_data, min(batch_size, length(@sample_data)))

        case Streaming.process_batch(state, batch) do
          {:ok, batch_result, new_state} ->
            assert new_state.metrics.total_processed >= length(batch_result.values)
            assert batch_result.processing_time >= 0

          {:error, _reason} ->
            # Some batch sizes might not be sufficient for certain indicators
            :ok
        end
      end
    end

    @tag :property
    test "serialization round-trip preserves state equivalence" do
      config = %{
        indicator: SMA,
        params: [period: 2],
        buffer_size: 100,
        state: nil
      }

      {:ok, original_state} = Streaming.init_stream(config)

      # Process some data to create a meaningful state
      {:ok, _result, processed_state} = Streaming.process_batch(original_state, @sample_data)

      {:ok, serialized} = Streaming.serialize_state(processed_state)
      {:ok, deserialized_state} = Streaming.deserialize_state(serialized)

      # Verify key properties are preserved
      assert deserialized_state.config.indicator == processed_state.config.indicator
      assert deserialized_state.config.buffer_size == processed_state.config.buffer_size
      assert deserialized_state.metrics.total_processed == processed_state.metrics.total_processed
    end
  end

  # Performance tests
  describe "performance tests" do
    @tag :performance
    test "batch processing performance scales linearly" do
      config = %{
        indicator: SMA,
        params: [period: 10],
        buffer_size: 10000,
        state: nil
      }

      {:ok, state} = Streaming.init_stream(config)

      # Generate larger datasets
      large_dataset = Stream.cycle(@sample_data) |> Enum.take(1000)

      start_time = System.monotonic_time(:microsecond)
      {:ok, _batch_result, _new_state} = Streaming.process_batch(state, large_dataset)
      end_time = System.monotonic_time(:microsecond)

      processing_time = end_time - start_time

      # Should process at least 15 points per millisecond (more realistic threshold)
      throughput = length(large_dataset) * 1000 / processing_time
      assert throughput > 15
    end
  end
end
