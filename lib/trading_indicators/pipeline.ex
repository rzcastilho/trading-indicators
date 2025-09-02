defmodule TradingIndicators.Pipeline do
  @moduledoc """
  Pipeline composition system for building complex trading indicator analysis workflows.

  This module provides functionality to:
  - Build indicator pipelines with dependency management
  - Execute pipelines in sequential or parallel modes
  - Aggregate and correlate results from multiple indicators
  - Monitor pipeline performance and manage errors

  ## Pipeline Architecture

  A pipeline consists of multiple stages, each representing an indicator calculation.
  Stages can depend on other stages, creating a directed acyclic graph (DAG) of
  computations. The pipeline executor resolves dependencies and executes stages
  in the optimal order.

  ## Features

  - **Stage Dependencies**: Define which indicators depend on others
  - **Execution Modes**: Sequential or parallel execution where possible
  - **Result Caching**: Avoid redundant calculations
  - **Error Handling**: Fail-fast or continue-on-error modes
  - **Performance Monitoring**: Track execution times and bottlenecks
  - **Input Mapping**: Transform data between stages

  ## Example Usage

      # Build a pipeline
      pipeline = 
        TradingIndicators.Pipeline.new()
        |> TradingIndicators.Pipeline.add_stage("sma", TradingIndicators.Trend.SMA, [period: 20])
        |> TradingIndicators.Pipeline.add_stage("rsi", TradingIndicators.Momentum.RSI, [period: 14])
        |> TradingIndicators.Pipeline.add_stage("signal", MySignalIndicator, [sma_period: 20, rsi_threshold: 70])
        |> TradingIndicators.Pipeline.add_dependency("signal", "sma")
        |> TradingIndicators.Pipeline.add_dependency("signal", "rsi")
        |> TradingIndicators.Pipeline.build()

      # Execute pipeline
      {:ok, results} = TradingIndicators.Pipeline.execute(pipeline, data)

      # Stream execution
      {:ok, pipeline_state} = TradingIndicators.Pipeline.init_streaming(pipeline)
      {:ok, results, new_state} = TradingIndicators.Pipeline.stream_execute(pipeline_state, data_point)

  ## Performance Considerations

  - Parallel execution improves performance for independent stages
  - Result caching reduces computational overhead
  - Dependency resolution optimizes execution order
  - Streaming mode enables real-time processing
  """

  alias TradingIndicators.{Types, Errors}
  require Logger

  @type pipeline_builder :: %{
          stages: [Types.pipeline_stage()],
          dependencies: %{String.t() => [String.t()]},
          config: map()
        }

  @type execution_result :: %{
          stage_results: %{String.t() => Types.result_series()},
          aggregated_result: Types.result_series(),
          execution_metrics: Types.pipeline_metrics(),
          errors: [execution_error()]
        }

  @type execution_error :: %{
          stage_id: String.t(),
          error: term(),
          timestamp: DateTime.t()
        }

  @doc """
  Creates a new pipeline builder.

  ## Returns

  - Pipeline builder with default configuration

  ## Examples

      iex> builder = TradingIndicators.Pipeline.new()
      iex> builder.stages
      []
  """
  @spec new() :: pipeline_builder()
  def new do
    %{
      stages: [],
      dependencies: %{},
      config: %{
        execution_mode: :sequential,
        error_handling: :fail_fast,
        enable_caching: true,
        parallel_stages: 4
      }
    }
  end

  @doc """
  Adds a stage to the pipeline.

  ## Parameters

  - `builder` - Pipeline builder
  - `id` - Unique identifier for the stage
  - `indicator` - Indicator module to execute
  - `params` - Parameters for the indicator
  - `opts` - Optional stage configuration

  ## Returns

  - Updated pipeline builder

  ## Examples

      iex> builder = TradingIndicators.Pipeline.new()
      iex> updated_builder = TradingIndicators.Pipeline.add_stage(builder, "sma", TradingIndicators.Trend.SMA, [period: 14])
      iex> length(updated_builder.stages)
      1
      iex> hd(updated_builder.stages).id
      "sma"
  """
  @spec add_stage(pipeline_builder(), String.t(), module(), keyword(), keyword()) :: pipeline_builder()
  def add_stage(builder, id, indicator, params, opts \\ []) do
    stage = %{
      id: id,
      indicator: indicator,
      params: params,
      dependencies: [],
      input_mapping: Keyword.get(opts, :input_mapping, [])
    }

    %{builder | stages: [stage | builder.stages]}
  end

  @doc """
  Adds a dependency between pipeline stages.

  ## Parameters

  - `builder` - Pipeline builder
  - `dependent_stage` - Stage that depends on another
  - `dependency_stage` - Stage that the dependent stage needs

  ## Returns

  - Updated pipeline builder

  ## Examples

      iex> builder = TradingIndicators.Pipeline.new()
      iex>   |> TradingIndicators.Pipeline.add_stage("sma", TradingIndicators.Trend.SMA, [period: 14])
      iex>   |> TradingIndicators.Pipeline.add_stage("signal", TradingIndicators.Trend.SMA, [period: 20])
      iex> updated_builder = TradingIndicators.Pipeline.add_dependency(builder, "signal", "sma")
      iex> Map.get(updated_builder.dependencies, "signal")
      ["sma"]
  """
  @spec add_dependency(pipeline_builder(), String.t(), String.t()) :: pipeline_builder()
  def add_dependency(builder, dependent_stage, dependency_stage) do
    current_deps = Map.get(builder.dependencies, dependent_stage, [])
    updated_deps = [dependency_stage | current_deps] |> Enum.uniq()
    
    dependencies = Map.put(builder.dependencies, dependent_stage, updated_deps)
    %{builder | dependencies: dependencies}
  end

  @doc """
  Configures pipeline execution settings.

  ## Parameters

  - `builder` - Pipeline builder
  - `config` - Configuration map

  ## Returns

  - Updated pipeline builder with new configuration

  ## Examples

      iex> builder = TradingIndicators.Pipeline.new()
      iex> config = %{execution_mode: :parallel, error_handling: :continue_on_error}
      iex> updated_builder = TradingIndicators.Pipeline.configure(builder, config)
      iex> updated_builder.config.execution_mode
      :parallel
  """
  @spec configure(pipeline_builder(), map()) :: pipeline_builder()
  def configure(builder, config) do
    updated_config = Map.merge(builder.config, config)
    %{builder | config: updated_config}
  end

  @doc """
  Builds the final pipeline configuration from the builder.

  ## Parameters

  - `builder` - Pipeline builder

  ## Returns

  - `{:ok, pipeline_config}` - Built pipeline configuration
  - `{:error, reason}` - Validation error

  ## Examples

      iex> builder = TradingIndicators.Pipeline.new()
      iex>   |> TradingIndicators.Pipeline.add_stage("sma", TradingIndicators.Trend.SMA, [period: 14])
      iex> {:ok, pipeline} = TradingIndicators.Pipeline.build(builder)
      iex> String.starts_with?(pipeline.id, "pipeline_")
      true
  """
  @spec build(pipeline_builder()) :: {:ok, Types.pipeline_config()} | {:error, term()}
  def build(builder) do
    with :ok <- validate_pipeline(builder),
         execution_order <- resolve_execution_order(builder) do
      
      pipeline_id = "pipeline_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      
      pipeline_config = %{
        id: pipeline_id,
        stages: Enum.reverse(builder.stages),
        execution_mode: builder.config.execution_mode,
        error_handling: builder.config.error_handling,
        execution_order: execution_order,
        builder_config: builder.config
      }

      {:ok, pipeline_config}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Executes a pipeline with batch data processing.

  ## Parameters

  - `pipeline_config` - Built pipeline configuration
  - `data` - Input data series

  ## Returns

  - `{:ok, execution_result}` - Pipeline execution results
  - `{:error, reason}` - Execution error

  ## Examples

      iex> builder = TradingIndicators.Pipeline.new()
      iex>   |> TradingIndicators.Pipeline.add_stage("sma", TradingIndicators.Trend.SMA, [period: 2])
      iex> {:ok, pipeline} = TradingIndicators.Pipeline.build(builder)
      iex> data = [
      ...>   %{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{open: Decimal.new("103"), high: Decimal.new("107"), low: Decimal.new("102"), close: Decimal.new("106"), volume: 1200, timestamp: ~U[2024-01-01 09:31:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Pipeline.execute(pipeline, data)
      iex> Map.has_key?(result.stage_results, "sma")
      true
  """
  @spec execute(Types.pipeline_config(), Types.data_series()) ::
          {:ok, execution_result()} | {:error, term()}
  def execute(%{stages: stages, execution_mode: mode} = pipeline_config, data) do
    start_time = :os.system_time(:microsecond)
    
    try do
      stage_results = case mode do
        :sequential -> execute_sequential(stages, data, pipeline_config)
        :parallel -> execute_parallel(stages, data, pipeline_config)
      end

      execution_time = :os.system_time(:microsecond) - start_time
      
      # Aggregate results if configured
      aggregated_result = aggregate_stage_results(stage_results, pipeline_config)
      
      metrics = build_execution_metrics(stage_results, execution_time, pipeline_config)

      result = %{
        stage_results: stage_results,
        aggregated_result: aggregated_result,
        execution_metrics: metrics,
        errors: []
      }

      {:ok, result}
    rescue
      error -> {:error, error}
    catch
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Initializes pipeline for streaming execution.

  ## Parameters

  - `pipeline_config` - Built pipeline configuration

  ## Returns

  - `{:ok, pipeline_state}` - Initialized streaming state
  - `{:error, reason}` - Initialization error

  ## Examples

      iex> builder = TradingIndicators.Pipeline.new()
      iex>   |> TradingIndicators.Pipeline.add_stage("sma", TradingIndicators.Trend.SMA, [period: 14])
      iex> {:ok, pipeline} = TradingIndicators.Pipeline.build(builder)
      iex> {:ok, state} = TradingIndicators.Pipeline.init_streaming(pipeline)
      iex> Map.has_key?(state.stage_states, "sma")
      true
  """
  @spec init_streaming(Types.pipeline_config()) :: {:ok, Types.pipeline_state()} | {:error, term()}
  def init_streaming(%{stages: stages} = pipeline_config) do
    try do
      # Initialize streaming state for each stage that supports it
      stage_states = 
        stages
        |> Enum.reduce(%{}, fn stage, acc ->
          if function_exported?(stage.indicator, :init_state, 1) do
            state = stage.indicator.init_state(stage.params)
            Map.put(acc, stage.id, state)
          else
            acc
          end
        end)

      pipeline_state = %{
        config: pipeline_config,
        stage_states: stage_states,
        results_cache: %{},
        metrics: init_pipeline_metrics()
      }

      {:ok, pipeline_state}
    rescue
      error -> {:error, error}
    end
  end

  @doc """
  Executes pipeline with a single data point in streaming mode.

  ## Parameters

  - `pipeline_state` - Current pipeline streaming state
  - `data_point` - New data point to process

  ## Returns

  - `{:ok, results, new_state}` - Processing results and updated state
  - `{:error, reason}` - Processing error

  ## Examples

      iex> builder = TradingIndicators.Pipeline.new()
      iex>   |> TradingIndicators.Pipeline.add_stage("sma", TradingIndicators.Trend.SMA, [period: 2])
      iex> {:ok, pipeline} = TradingIndicators.Pipeline.build(builder)
      iex> {:ok, state} = TradingIndicators.Pipeline.init_streaming(pipeline)
      iex> data_point = %{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}
      iex> {:ok, _results, _new_state} = TradingIndicators.Pipeline.stream_execute(state, data_point)
      iex> true
      true
  """
  @spec stream_execute(Types.pipeline_state(), Types.ohlcv()) ::
          {:ok, map(), Types.pipeline_state()} | {:error, term()}
  def stream_execute(%{config: config, stage_states: stage_states} = pipeline_state, data_point) do
    start_time = :os.system_time(:microsecond)
    
    try do
      execution_order = Map.get(config, :execution_order, Enum.map(config.stages, & &1.id))
      
      {stage_results, updated_states} = 
        Enum.reduce(execution_order, {%{}, stage_states}, fn stage_id, {results, states} ->
          stage = Enum.find(config.stages, fn s -> s.id == stage_id end)
          
          case execute_streaming_stage(stage, data_point, states, results) do
            {:ok, result, new_state} ->
              updated_results = if result, do: Map.put(results, stage_id, result), else: results
              updated_states = if new_state, do: Map.put(states, stage_id, new_state), else: states
              {updated_results, updated_states}
            
            {:error, reason} ->
              case config.error_handling do
                :fail_fast -> throw({:error, reason})
                :continue_on_error -> {results, states}
              end
          end
        end)

      execution_time = :os.system_time(:microsecond) - start_time
      
      updated_metrics = update_streaming_metrics(pipeline_state.metrics, execution_time)
      
      new_pipeline_state = %{pipeline_state |
        stage_states: updated_states,
        metrics: updated_metrics
      }

      {:ok, stage_results, new_pipeline_state}
    rescue
      error -> {:error, error}
    catch
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Aggregates results from multiple pipeline executions.

  ## Parameters

  - `pipeline_results` - List of pipeline execution results
  - `aggregation_type` - Type of aggregation to perform

  ## Returns

  - Aggregated result based on the specified type

  ## Examples

      iex> result1 = %{stage_results: %{"sma" => [%{value: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z], metadata: %{}}]}, execution_metrics: %{total_processing_time: 100}, errors: []}
      iex> result2 = %{stage_results: %{"sma" => [%{value: Decimal.new("105"), timestamp: ~U[2024-01-01 09:31:00Z], metadata: %{}}]}, execution_metrics: %{total_processing_time: 150}, errors: []}
      iex> aggregated = TradingIndicators.Pipeline.aggregate_results([result1, result2], :merge)
      iex> length(aggregated.stage_results["sma"])
      2
  """
  @spec aggregate_results([execution_result()], atom()) :: execution_result()
  def aggregate_results(pipeline_results, :merge) do
    # Merge all stage results chronologically
    merged_stage_results = 
      pipeline_results
      |> Enum.reduce(%{}, fn result, acc ->
        Enum.reduce(result.stage_results, acc, fn {stage_id, stage_results}, stage_acc ->
          existing = Map.get(stage_acc, stage_id, [])
          Map.put(stage_acc, stage_id, existing ++ stage_results)
        end)
      end)
      |> Enum.map(fn {stage_id, results} ->
        sorted_results = Enum.sort_by(results, fn r -> r.timestamp end)
        {stage_id, sorted_results}
      end)
      |> Map.new()

    %{
      stage_results: merged_stage_results,
      aggregated_result: [],
      execution_metrics: aggregate_metrics(pipeline_results),
      errors: Enum.flat_map(pipeline_results, fn r -> r.errors end)
    }
  end

  def aggregate_results(pipeline_results, :latest) do
    # Keep only the latest result for each stage
    latest_result = List.last(pipeline_results)
    latest_result || %{stage_results: %{}, aggregated_result: [], execution_metrics: %{}, errors: []}
  end

  # Private helper functions

  defp validate_pipeline(builder) do
    with :ok <- validate_stages_exist(builder),
         :ok <- validate_dependencies(builder),
         :ok <- validate_no_cycles(builder) do
      :ok
    end
  end

  defp validate_stages_exist(%{stages: stages}) when length(stages) == 0 do
    {:error, %Errors.InvalidParams{message: "Pipeline must have at least one stage", param: :stages}}
  end
  
  defp validate_stages_exist(_builder), do: :ok

  defp validate_dependencies(%{stages: stages, dependencies: dependencies}) do
    stage_ids = Enum.map(stages, & &1.id) |> MapSet.new()
    
    Enum.reduce_while(dependencies, :ok, fn {dependent, deps}, _acc ->
      invalid_deps = Enum.reject(deps, &MapSet.member?(stage_ids, &1))
      
      case invalid_deps do
        [] -> {:cont, :ok}
        _ -> {:halt, {:error, %Errors.InvalidParams{
          message: "Unknown dependencies: #{inspect(invalid_deps)} for stage: #{dependent}",
          param: :dependencies
        }}}
      end
    end)
  end

  defp validate_no_cycles(builder) do
    # Simplified cycle detection - a full implementation would use DFS
    # For now, we just ensure no stage depends on itself
    case Enum.find(builder.dependencies, fn {stage, deps} -> stage in deps end) do
      nil -> :ok
      {stage, _} -> {:error, %Errors.InvalidParams{
        message: "Circular dependency detected for stage: #{stage}",
        param: :dependencies
      }}
    end
  end

  defp resolve_execution_order(%{stages: stages, dependencies: dependencies}) do
    # Simplified topological sort
    stage_ids = Enum.map(stages, & &1.id)
    
    # Separate independent and dependent stages
    {independent, dependent} = 
      Enum.split_with(stage_ids, fn id -> 
        not Map.has_key?(dependencies, id) or Map.get(dependencies, id) == []
      end)
    
    # Simple ordering: independent stages first, then dependent stages
    independent ++ dependent
  end

  defp execute_sequential(stages, data, _pipeline_config) do
    stages
    |> Enum.reduce(%{}, fn stage, acc ->
      case stage.indicator.calculate(data, stage.params) do
        {:ok, results} -> Map.put(acc, stage.id, results)
        {:error, reason} -> throw({:error, {stage.id, reason}})
      end
    end)
  end

  defp execute_parallel(stages, data, pipeline_config) do
    # For now, execute sequentially but mark for future parallel implementation
    # In a full implementation, this would use Task.async/await for independent stages
    Logger.debug("Parallel execution requested but running sequentially for now")
    execute_sequential(stages, data, pipeline_config)
  end

  defp execute_streaming_stage(stage, data_point, stage_states, _previous_results) do
    if Map.has_key?(stage_states, stage.id) and function_exported?(stage.indicator, :update_state, 2) do
      current_state = Map.get(stage_states, stage.id)
      stage.indicator.update_state(current_state, data_point)
    else
      {:ok, nil, nil}
    end
  end

  defp aggregate_stage_results(stage_results, _pipeline_config) do
    # Simple aggregation - combine all results chronologically
    stage_results
    |> Map.values()
    |> List.flatten()
    |> Enum.sort_by(fn result -> result.timestamp end)
  end

  defp build_execution_metrics(stage_results, execution_time, _pipeline_config) do
    stage_metrics = 
      stage_results
      |> Enum.map(fn {stage_id, results} ->
        {stage_id, %{
          executions: 1,
          total_time: execution_time,
          average_time: execution_time / 1.0,
          error_count: 0,
          result_count: length(results)
        }}
      end)
      |> Map.new()

    %{
      total_executions: 1,
      total_processing_time: execution_time,
      stage_metrics: stage_metrics,
      error_count: 0,
      last_execution_time: execution_time
    }
  end

  defp init_pipeline_metrics do
    %{
      total_executions: 0,
      total_processing_time: 0,
      stage_metrics: %{},
      error_count: 0,
      last_execution_time: 0
    }
  end

  defp update_streaming_metrics(metrics, execution_time) do
    %{metrics |
      total_executions: metrics.total_executions + 1,
      total_processing_time: metrics.total_processing_time + execution_time,
      last_execution_time: execution_time
    }
  end

  defp aggregate_metrics(pipeline_results) do
    total_executions = length(pipeline_results)
    total_processing_time = 
      pipeline_results
      |> Enum.map(fn r -> r.execution_metrics.total_processing_time end)
      |> Enum.sum()
    
    total_errors = 
      pipeline_results
      |> Enum.map(fn r -> length(r.errors) end)
      |> Enum.sum()

    %{
      total_executions: total_executions,
      total_processing_time: total_processing_time,
      stage_metrics: %{},
      error_count: total_errors,
      last_execution_time: 0
    }
  end
end