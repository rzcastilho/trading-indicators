defmodule TradingIndicators.Streaming do
  @moduledoc """
  Enhanced streaming capabilities for real-time trading indicator calculations.

  This module provides advanced streaming functionality including:
  - Batch processing for multiple data points
  - Stream composition for chaining indicators
  - State persistence and recovery
  - Performance optimizations for high-frequency data

  ## Features

  - **Batch Processing**: Process multiple data points efficiently
  - **Stream Composition**: Chain multiple indicators with dependency resolution
  - **State Persistence**: Serialize and deserialize streaming states
  - **Performance Monitoring**: Track processing metrics and throughput
  - **Memory Management**: Optimized buffer handling for long-running streams

  ## Example Usage

      # Initialize streaming for multiple indicators
      config = %{
        indicator: TradingIndicators.Trend.SMA,
        params: [period: 14],
        buffer_size: 1000
      }
      
      {:ok, state} = TradingIndicators.Streaming.init_stream(config)
      
      # Process batch of data points
      data_batch = [data1, data2, data3]
      {:ok, results, new_state} = TradingIndicators.Streaming.process_batch(state, data_batch)
      
      # Compose multiple indicators
      composition = %{
        primary_stream: sma_config,
        dependent_streams: [rsi_config, macd_config],
        aggregation_function: &aggregate_signals/1
      }
      
      {:ok, composed_state} = TradingIndicators.Streaming.compose_streams(composition)

  ## Performance Considerations

  - Use appropriate buffer sizes based on memory constraints
  - Batch processing is more efficient than individual updates
  - Stream composition reduces redundant calculations
  - State serialization enables fault tolerance
  """

  alias TradingIndicators.{Types, Errors}
  require Logger

  @type streaming_state :: %{
          config: Types.streaming_config(),
          indicator_state: term(),
          buffer: list(),
          metrics: streaming_metrics(),
          last_update: DateTime.t()
        }

  @type streaming_metrics :: %{
          total_processed: non_neg_integer(),
          processing_time: non_neg_integer(),
          throughput: float(),
          error_count: non_neg_integer(),
          buffer_utilization: float()
        }

  @type composition_state :: %{
          primary_stream: streaming_state(),
          dependent_streams: [streaming_state()],
          composition_config: Types.stream_composition(),
          dependency_graph: map(),
          execution_order: [String.t()]
        }

  @doc """
  Initializes a streaming state for an indicator.

  ## Parameters

  - `config` - Streaming configuration including indicator and parameters

  ## Returns

  - `{:ok, streaming_state}` - Initialized streaming state
  - `{:error, reason}` - Error during initialization

  ## Examples

      iex> config = %{indicator: TradingIndicators.Trend.SMA, params: [period: 14], buffer_size: 100, state: nil}
      iex> {:ok, state} = TradingIndicators.Streaming.init_stream(config)
      iex> state.config.indicator
      TradingIndicators.Trend.SMA
  """
  @spec init_stream(Types.streaming_config()) :: {:ok, streaming_state()} | {:error, term()}
  def init_stream(%{indicator: indicator, params: params} = config) do
    try do
      # Validate that the indicator supports streaming by attempting to call the function
      # function_exported?/3 may give false negatives for @optional_callbacks in test env
      try do
        _test_state = indicator.init_state(params)
      rescue
        UndefinedFunctionError ->
          raise ArgumentError, "Indicator #{inspect(indicator)} does not support streaming"
      end

      # Validate parameters
      case indicator.validate_params(params) do
        :ok -> :ok
        {:error, reason} -> raise ArgumentError, "Invalid parameters: #{inspect(reason)}"
      end

      # Initialize indicator state
      indicator_state = indicator.init_state(params)

      streaming_state = %{
        config: Map.put_new(config, :buffer_size, 1000),
        indicator_state: indicator_state,
        buffer: [],
        metrics: init_metrics(),
        last_update: DateTime.utc_now()
      }

      {:ok, streaming_state}
    rescue
      error -> {:error, error}
    end
  end

  @doc """
  Processes a batch of data points through the streaming indicator.

  This function is optimized for processing multiple data points at once,
  reducing function call overhead and improving throughput.

  ## Parameters

  - `state` - Current streaming state
  - `data_batch` - List of data points to process

  ## Returns

  - `{:ok, batch_result, new_state}` - Processing results and updated state
  - `{:error, reason}` - Error during batch processing

  ## Examples

      iex> config = %{indicator: TradingIndicators.Trend.SMA, params: [period: 2], buffer_size: 100, state: nil}
      iex> {:ok, state} = TradingIndicators.Streaming.init_stream(config)
      iex> data_batch = [
      ...>   %{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{open: Decimal.new("103"), high: Decimal.new("107"), low: Decimal.new("102"), close: Decimal.new("106"), volume: 1200, timestamp: ~U[2024-01-01 09:31:00Z]}
      ...> ]
      iex> {:ok, batch_result, _new_state} = TradingIndicators.Streaming.process_batch(state, data_batch)
      iex> length(batch_result.values)
      1
  """
  @spec process_batch(streaming_state(), [Types.ohlcv()]) ::
          {:ok, Types.batch_result(), streaming_state()} | {:error, term()}
  def process_batch(%{config: %{indicator: _indicator}} = state, data_batch)
      when is_list(data_batch) do
    start_time = :os.system_time(:microsecond)

    try do
      {results, final_state} =
        Enum.reduce(data_batch, {[], state}, fn data_point, {acc_results, acc_state} ->
          case update_stream_state(acc_state, data_point) do
            {:ok, new_state, result} when not is_nil(result) ->
              {[result | acc_results], new_state}

            {:ok, new_state, nil} ->
              {acc_results, new_state}

            {:error, reason} ->
              throw({:error, reason})
          end
        end)

      processing_time = :os.system_time(:microsecond) - start_time

      batch_result = %{
        values: Enum.reverse(results),
        updated_state: final_state.indicator_state,
        processing_time: processing_time
      }

      updated_metrics =
        update_batch_metrics(final_state.metrics, length(data_batch), processing_time)

      updated_state = %{final_state | metrics: updated_metrics, last_update: DateTime.utc_now()}

      {:ok, batch_result, updated_state}
    rescue
      error -> {:error, error}
    catch
      {:error, reason} -> {:error, reason}
    end
  end

  def process_batch(_state, _data_batch) do
    {:error,
     %Errors.InvalidDataFormat{
       message: "Data batch must be a list",
       expected: "list",
       received: "invalid"
     }}
  end

  @doc """
  Composes multiple streaming indicators for coordinated processing.

  Creates a dependency graph and execution order for multiple indicators,
  allowing efficient processing of interdependent calculations.

  ## Parameters

  - `composition_config` - Configuration for stream composition

  ## Returns

  - `{:ok, composition_state}` - Initialized composition state
  - `{:error, reason}` - Error during composition setup

  ## Examples

      iex> primary_config = %{indicator: TradingIndicators.Trend.SMA, params: [period: 14], buffer_size: 100, state: nil}
      iex> composition = %{
      ...>   primary_stream: primary_config,
      ...>   dependent_streams: [],
      ...>   aggregation_function: fn results -> List.first(results) end,
      ...>   buffer_management: :sliding_window
      ...> }
      iex> {:ok, state} = TradingIndicators.Streaming.compose_streams(composition)
      iex> state.primary_stream.config.indicator
      TradingIndicators.Trend.SMA
  """
  @spec compose_streams(Types.stream_composition()) :: {:ok, composition_state()} | {:error, term()}
  def compose_streams(%{primary_stream: primary_config} = composition_config) do
    try do
      # Initialize primary stream
      {:ok, primary_state} = init_stream(primary_config)

      # Initialize dependent streams
      dependent_states =
        composition_config
        |> Map.get(:dependent_streams, [])
        |> Enum.map(fn config ->
          case init_stream(config) do
            {:ok, state} -> state
            {:error, reason} -> throw({:error, reason})
          end
        end)

      # Build dependency graph (simplified for now)
      dependency_graph =
        build_dependency_graph(primary_config, Map.get(composition_config, :dependent_streams, []))

      execution_order = topological_sort(dependency_graph)

      composition_state = %{
        primary_stream: primary_state,
        dependent_streams: dependent_states,
        composition_config: composition_config,
        dependency_graph: dependency_graph,
        execution_order: execution_order
      }

      {:ok, composition_state}
    rescue
      error -> {:error, error}
    catch
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Serializes a streaming state for persistence.

  Converts the streaming state to a binary format that can be stored
  and later deserialized to restore streaming operations.

  ## Parameters

  - `state` - Streaming state to serialize

  ## Returns

  - `{:ok, binary}` - Serialized state
  - `{:error, reason}` - Serialization error

  ## Examples

      iex> config = %{indicator: TradingIndicators.Trend.SMA, params: [period: 14], buffer_size: 100, state: nil}
      iex> {:ok, state} = TradingIndicators.Streaming.init_stream(config)
      iex> {:ok, serialized} = TradingIndicators.Streaming.serialize_state(state)
      iex> is_binary(serialized)
      true
  """
  @spec serialize_state(streaming_state() | composition_state()) ::
          {:ok, binary()} | {:error, term()}
  def serialize_state(state) do
    try do
      serialized = :erlang.term_to_binary(state, [:compressed])
      {:ok, serialized}
    rescue
      error -> {:error, error}
    end
  end

  @doc """
  Deserializes a streaming state from persistence.

  Converts a binary serialized state back to a streaming state structure
  that can be used to continue streaming operations.

  ## Parameters

  - `serialized_state` - Binary serialized state

  ## Returns

  - `{:ok, state}` - Deserialized streaming state
  - `{:error, reason}` - Deserialization error

  ## Examples

      iex> config = %{indicator: TradingIndicators.Trend.SMA, params: [period: 14], buffer_size: 100, state: nil}
      iex> {:ok, original_state} = TradingIndicators.Streaming.init_stream(config)
      iex> {:ok, serialized} = TradingIndicators.Streaming.serialize_state(original_state)
      iex> {:ok, deserialized_state} = TradingIndicators.Streaming.deserialize_state(serialized)
      iex> deserialized_state.config.indicator
      TradingIndicators.Trend.SMA
  """
  @spec deserialize_state(binary()) ::
          {:ok, streaming_state() | composition_state()} | {:error, term()}
  def deserialize_state(serialized_state) when is_binary(serialized_state) do
    try do
      state = :erlang.binary_to_term(serialized_state, [:safe])
      {:ok, state}
    rescue
      error -> {:error, error}
    end
  end

  def deserialize_state(_serialized_state) do
    {:error,
     %Errors.InvalidDataFormat{
       message: "Serialized state must be binary",
       expected: "binary",
       received: "invalid"
     }}
  end

  @doc """
  Retrieves streaming metrics for performance monitoring.

  ## Parameters

  - `state` - Streaming state or composition state

  ## Returns

  - Streaming metrics map

  ## Examples

      iex> config = %{indicator: TradingIndicators.Trend.SMA, params: [period: 14], buffer_size: 100, state: nil}
      iex> {:ok, state} = TradingIndicators.Streaming.init_stream(config)
      iex> metrics = TradingIndicators.Streaming.stream_metrics(state)
      iex> metrics.total_processed
      0
  """
  @spec stream_metrics(streaming_state() | composition_state()) :: streaming_metrics() | map()
  def stream_metrics(%{metrics: metrics}), do: metrics

  def stream_metrics(%{
        primary_stream: %{metrics: primary_metrics},
        dependent_streams: dependent_streams
      }) do
    dependent_metrics = Enum.map(dependent_streams, fn %{metrics: metrics} -> metrics end)

    %{
      primary: primary_metrics,
      dependents: dependent_metrics,
      total_throughput: calculate_total_throughput([primary_metrics | dependent_metrics])
    }
  end

  @doc """
  Updates streaming state with a single data point.

  Internal function used by batch processing and individual updates.

  ## Parameters

  - `state` - Current streaming state
  - `data_point` - New data point to process

  ## Returns

  - `{:ok, new_state, result}` - Updated state and optional result
  - `{:error, reason}` - Processing error
  """
  @spec update_stream_state(streaming_state(), Types.ohlcv()) ::
          {:ok, streaming_state(), Types.indicator_result() | nil} | {:error, term()}
  def update_stream_state(
        %{config: %{indicator: indicator}, indicator_state: current_state} = state,
        data_point
      ) do
    case indicator.update_state(current_state, data_point) do
      {:ok, new_indicator_state, result} ->
        updated_state = %{state | indicator_state: new_indicator_state}
        {:ok, updated_state, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp init_metrics do
    %{
      total_processed: 0,
      processing_time: 0,
      throughput: 0.0,
      error_count: 0,
      buffer_utilization: 0.0
    }
  end

  defp update_batch_metrics(metrics, batch_size, processing_time) do
    total_processed = metrics.total_processed + batch_size
    total_time = metrics.processing_time + processing_time

    throughput =
      if total_time > 0 do
        # points per second
        total_processed * 1_000_000 / total_time
      else
        0.0
      end

    %{
      metrics
      | total_processed: total_processed,
        processing_time: total_time,
        throughput: throughput
    }
  end

  defp build_dependency_graph(primary_config, dependent_configs) do
    # Simplified dependency graph - in a full implementation, this would
    # analyze the actual dependencies between indicators
    primary_id = indicator_id(primary_config.indicator)
    dependent_ids = Enum.map(dependent_configs, fn config -> indicator_id(config.indicator) end)

    Map.put(%{}, primary_id, dependent_ids)
  end

  defp topological_sort(dependency_graph) do
    # Simplified topological sort - returns primary indicator first, then dependents
    case Map.keys(dependency_graph) do
      [] -> []
      [primary | _] -> [primary | Map.get(dependency_graph, primary, [])]
    end
  end

  defp indicator_id(indicator_module) do
    indicator_module
    |> Module.split()
    |> List.last()
    |> String.downcase()
  end

  defp calculate_total_throughput(metrics_list) do
    metrics_list
    |> Enum.map(fn %{throughput: throughput} -> throughput end)
    |> Enum.sum()
  end
end
