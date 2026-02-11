defmodule TradingIndicators.Types do
  require Decimal

  @moduledoc """
  Common data structures and type definitions for the TradingIndicators library.

  This module defines all the shared types used throughout the library,
  ensuring consistency in data handling and API design.

  ## Core Data Types

  - `ohlcv/0` - Open, High, Low, Close, Volume data point
  - `indicator_result/0` - Standardized indicator calculation result
  - `data_series/0` - Series of OHLCV data points
  - `result_series/0` - Series of indicator results

  ## Price Series Types

  - `price_series/0` - Generic price data series
  - `close_series/0` - Series of closing prices
  - `high_series/0` - Series of high prices
  - `low_series/0` - Series of low prices
  - `volume_series/0` - Series of volume data
  """

  @typedoc """
  OHLCV (Open, High, Low, Close, Volume) data point.

  Represents a single period of market data with all essential price and volume information.
  The timestamp field allows for proper time series ordering and validation.

  ## Fields

  - `:open` - Opening price for the period
  - `:high` - Highest price during the period
  - `:low` - Lowest price during the period
  - `:close` - Closing price for the period
  - `:volume` - Trading volume during the period
  - `:timestamp` - Time when this data point occurred

  ## Example

      %{
        open: Decimal.new("100.00"),
        high: Decimal.new("105.00"),
        low: Decimal.new("99.00"),
        close: Decimal.new("103.00"),
        volume: 1000,
        timestamp: ~U[2024-01-01 09:30:00Z]
      }
  """
  @type ohlcv :: %{
          open: Decimal.t(),
          high: Decimal.t(),
          low: Decimal.t(),
          close: Decimal.t(),
          volume: non_neg_integer(),
          timestamp: DateTime.t()
        }

  @typedoc """
  Standardized result structure for indicator calculations.

  Provides a consistent format for all indicator results, including the calculated
  value, timestamp, and optional metadata for additional information.

  ## Fields

  - `:value` - The calculated indicator value (can be number or complex structure)
  - `:timestamp` - Timestamp associated with this calculation
  - `:metadata` - Additional information about the calculation (optional)

  ## Example

      %{
        value: Decimal.new("14.5"),
        timestamp: ~U[2024-01-01 09:30:00Z],
        metadata: %{period: 14, source: :close}
      }
  """
  @type indicator_result :: %{
          value: Decimal.t() | integer() | map(),
          timestamp: DateTime.t(),
          metadata: map()
        }

  @typedoc """
  Series of OHLCV data points.

  Represents a time-ordered sequence of market data, typically used as input
  for indicator calculations.
  """
  @type data_series :: [ohlcv()]

  @typedoc """
  Series of indicator calculation results.

  Represents the output of indicator calculations, maintaining time ordering
  and providing standardized result format.
  """
  @type result_series :: [indicator_result()]

  @typedoc """
  Generic price series - list of numerical price values.

  Used for simplified calculations that only require a single price series
  (e.g., closing prices, high prices, etc.).
  """
  @type price_series :: [Decimal.t()]

  @typedoc """
  Series of closing prices extracted from OHLCV data.
  """
  @type close_series :: [Decimal.t()]

  @typedoc """
  Series of high prices extracted from OHLCV data.
  """
  @type high_series :: [Decimal.t()]

  @typedoc """
  Series of low prices extracted from OHLCV data.
  """
  @type low_series :: [Decimal.t()]

  @typedoc """
  Series of opening prices extracted from OHLCV data.
  """
  @type open_series :: [Decimal.t()]

  @typedoc """
  Series of volume data extracted from OHLCV data.
  """
  @type volume_series :: [non_neg_integer()]

  @typedoc """
  Combined high-low-close data used by some indicators.

  Some indicators require multiple price points from each period.
  This type represents the common HLC combination.
  """
  @type hlc_data :: %{
          high: Decimal.t(),
          low: Decimal.t(),
          close: Decimal.t(),
          timestamp: DateTime.t()
        }

  @typedoc """
  Series of HLC data points.
  """
  @type hlc_series :: [hlc_data()]

  @typedoc """
  Typical Price calculation result.

  The typical price is calculated as (high + low + close) / 3
  and is used by various indicators like CCI.
  """
  @type typical_price :: %{
          value: Decimal.t(),
          timestamp: DateTime.t()
        }

  @typedoc """
  Series of typical price calculations.
  """
  @type typical_price_series :: [typical_price()]

  @typedoc """
  True Range calculation result.

  True Range is the maximum of:
  - Current High - Current Low
  - Current High - Previous Close (absolute value)
  - Current Low - Previous Close (absolute value)
  """
  @type true_range :: %{
          value: Decimal.t(),
          timestamp: DateTime.t()
        }

  @typedoc """
  Series of True Range calculations.
  """
  @type true_range_series :: [true_range()]

  @typedoc """
  Bollinger Bands calculation result.

  Contains all three bands plus additional calculations:
  - Upper Band: SMA + (multiplier × standard deviation)
  - Middle Band: Simple Moving Average
  - Lower Band: SMA - (multiplier × standard deviation)  
  - %B: Position of price relative to bands ((Price - Lower) / (Upper - Lower) × 100)
  - Bandwidth: Distance between bands ((Upper - Lower) / Middle × 100)
  """
  @type bollinger_result :: %{
          upper_band: Decimal.t(),
          middle_band: Decimal.t(),
          lower_band: Decimal.t(),
          percent_b: Decimal.t(),
          bandwidth: Decimal.t(),
          timestamp: DateTime.t(),
          metadata: map()
        }

  @typedoc """
  Options for indicator calculations.

  Common options that can be passed to indicator functions:
  - `:period` - Number of periods to use in calculation
  - `:source` - Source price to use (:open, :high, :low, :close)
  - `:smoothing` - Smoothing factor for EMA-based calculations
  - `:multiplier` - Multiplier for standard deviation bands
  """
  @type indicator_opts :: keyword()

  @typedoc """
  Stream state for real-time indicator calculations.

  Generic type for maintaining state across streaming updates.
  Each indicator implementation defines its own specific state structure.
  """
  @type stream_state :: term()

  @typedoc """
  Validation result for input parameters or data.
  """
  @type validation_result :: :ok | {:error, term()}

  @typedoc """
  Time period specification for indicators.

  Can be specified as:
  - Positive integer (number of periods)
  - Atom shorthand (:short, :medium, :long for common periods)
  """
  @type period_spec :: pos_integer() | :short | :medium | :long

  @doc """
  Checks if a value is a valid OHLCV data point.

  ## Parameters

  - `data` - The value to check

  ## Returns

  - `true` if the value is a valid OHLCV map
  - `false` otherwise

  ## Example

      iex> TradingIndicators.Types.valid_ohlcv?(%{
      ...>   open: Decimal.new("100.0"), high: Decimal.new("105.0"), low: Decimal.new("99.0"), close: Decimal.new("103.0"),
      ...>   volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]
      ...> })
      true

      iex> TradingIndicators.Types.valid_ohlcv?(%{close: Decimal.new("100.0")})
      false
  """
  @spec valid_ohlcv?(term()) :: boolean()
  def valid_ohlcv?(%{} = data) do
    required_keys = [:open, :high, :low, :close, :volume, :timestamp]

    Enum.all?(required_keys, &Map.has_key?(data, &1)) and
      Decimal.is_decimal(data.open) and
      Decimal.is_decimal(data.high) and
      Decimal.is_decimal(data.low) and
      Decimal.is_decimal(data.close) and
      is_integer(data.volume) and
      data.volume >= 0 and
      is_struct(data.timestamp, DateTime)
  end

  def valid_ohlcv?(_), do: false

  @doc """
  Checks if a value is a valid indicator result.

  ## Parameters

  - `result` - The value to check

  ## Returns

  - `true` if the value is a valid indicator result map
  - `false` otherwise
  """
  @spec valid_indicator_result?(term()) :: boolean()
  def valid_indicator_result?(%{} = result) do
    Map.has_key?(result, :value) and
      Map.has_key?(result, :timestamp) and
      is_struct(result.timestamp, DateTime) and
      (Decimal.is_decimal(result.value) or is_integer(result.value) or is_map(result.value))
  end

  def valid_indicator_result?(_), do: false

  @typedoc """
  Streaming state configuration for indicators.

  Contains configuration and state information for streaming indicators
  including buffer management and composition settings.
  """
  @type streaming_config :: %{
          indicator: module(),
          params: keyword(),
          buffer_size: pos_integer(),
          state: term()
        }

  @typedoc """
  Batch processing result containing multiple indicator values.

  Used for efficient processing of multiple data points at once
  in streaming scenarios.
  """
  @type batch_result :: %{
          values: [indicator_result()],
          updated_state: term(),
          processing_time: non_neg_integer()
        }

  @typedoc """
  Pipeline configuration defining a sequence of indicators.

  Describes how indicators should be chained together, including
  dependencies and data flow between stages.
  """
  @type pipeline_config :: %{
          id: String.t(),
          stages: [pipeline_stage()],
          execution_mode: :sequential | :parallel,
          error_handling: :fail_fast | :continue_on_error
        }

  @typedoc """
  Individual pipeline stage configuration.
  """
  @type pipeline_stage :: %{
          id: String.t(),
          indicator: module(),
          params: keyword(),
          dependencies: [String.t()],
          input_mapping: keyword()
        }

  @typedoc """
  Pipeline execution state tracking all stages.
  """
  @type pipeline_state :: %{
          config: pipeline_config(),
          stage_states: %{String.t() => term()},
          results_cache: %{String.t() => [indicator_result()]},
          metrics: pipeline_metrics()
        }

  @typedoc """
  Pipeline execution metrics for performance monitoring.
  """
  @type pipeline_metrics :: %{
          total_executions: non_neg_integer(),
          total_processing_time: non_neg_integer(),
          stage_metrics: %{String.t() => stage_metrics()},
          error_count: non_neg_integer(),
          last_execution_time: non_neg_integer()
        }

  @typedoc """
  Individual stage execution metrics.
  """
  @type stage_metrics :: %{
          executions: non_neg_integer(),
          total_time: non_neg_integer(),
          average_time: float(),
          error_count: non_neg_integer()
        }

  @typedoc """
  Performance benchmark result for indicator analysis.
  """
  @type benchmark_result :: %{
          indicator: module(),
          dataset_size: pos_integer(),
          iterations: pos_integer(),
          total_time: non_neg_integer(),
          average_time: float(),
          memory_usage: non_neg_integer(),
          throughput: float()
        }

  @typedoc """
  Memory profiling information for performance analysis.
  """
  @type memory_profile :: %{
          initial_memory: non_neg_integer(),
          peak_memory: non_neg_integer(),
          final_memory: non_neg_integer(),
          memory_delta: integer(),
          gc_collections: non_neg_integer()
        }

  @typedoc """
  Data quality assessment result.

  Contains information about data integrity, completeness,
  and quality metrics for time series data.
  """
  @type quality_report :: %{
          total_points: non_neg_integer(),
          valid_points: non_neg_integer(),
          invalid_points: non_neg_integer(),
          missing_timestamps: non_neg_integer(),
          duplicate_timestamps: non_neg_integer(),
          chronological_errors: non_neg_integer(),
          outliers_detected: non_neg_integer(),
          quality_score: float(),
          issues: [quality_issue()]
        }

  @typedoc """
  Individual data quality issue.
  """
  @type quality_issue :: %{
          type: :missing_data | :invalid_data | :chronological_error | :duplicate | :outlier,
          index: non_neg_integer(),
          description: String.t(),
          severity: :low | :medium | :high | :critical
        }

  @typedoc """
  Data cleaning configuration options.
  """
  @type cleaning_config :: %{
          fill_gaps: :forward_fill | :backward_fill | :interpolate | :remove,
          outlier_detection: :iqr | :zscore | :modified_zscore | :isolation_forest,
          outlier_threshold: float(),
          normalization: :minmax | :zscore | :robust | :none
        }

  @typedoc """
  Stream composition configuration for chaining indicators.
  """
  @type stream_composition :: %{
          primary_stream: streaming_config(),
          dependent_streams: [streaming_config()],
          aggregation_function: (list() -> term()),
          buffer_management: :sliding_window | :expanding_window
        }

  @typedoc """
  Cache configuration for performance optimization.
  """
  @type cache_config :: %{
          enabled: boolean(),
          max_size: pos_integer(),
          ttl: non_neg_integer(),
          eviction_policy: :lru | :lfu | :fifo
        }

  @doc """
  Converts a period specification to an integer.

  ## Parameters

  - `period_spec` - Period specification (integer or atom)

  ## Returns

  - Integer representation of the period

  ## Example

      iex> TradingIndicators.Types.resolve_period(:short)
      14

      iex> TradingIndicators.Types.resolve_period(20)
      20
  """
  @spec resolve_period(period_spec()) :: pos_integer()
  def resolve_period(:short), do: 14
  def resolve_period(:medium), do: 21
  def resolve_period(:long), do: 50
  def resolve_period(period) when is_integer(period) and period > 0, do: period

  @typedoc """
  Parameter metadata struct for indicator parameters.

  Provides comprehensive metadata about each parameter that an indicator accepts,
  enabling automatic validation, documentation generation, and UI construction.

  ## Fields

  - `:name` - Parameter name as an atom (required)
  - `:type` - Parameter type (`:integer`, `:float`, `:string`, `:atom`) (required)
  - `:default` - Default value for the parameter (required)
  - `:required` - Whether the parameter is required (boolean) (required)
  - `:min` - Minimum allowed value (for numeric types, nil if no minimum)
  - `:max` - Maximum allowed value (for numeric types, nil if no maximum)
  - `:options` - List of valid options (for atom/string enums, nil if not applicable)
  - `:description` - Human-readable description of the parameter

  ## Examples

      # Integer parameter with range
      %TradingIndicators.Types.ParamMetadata{
        name: :period,
        type: :integer,
        default: 20,
        required: false,
        min: 1,
        max: nil,
        options: nil,
        description: "Number of periods to use in calculation"
      }

      # Atom parameter with valid options
      %TradingIndicators.Types.ParamMetadata{
        name: :source,
        type: :atom,
        default: :close,
        required: false,
        min: nil,
        max: nil,
        options: [:open, :high, :low, :close],
        description: "Source price field to use"
      }

      # Float parameter with minimum
      %TradingIndicators.Types.ParamMetadata{
        name: :multiplier,
        type: :float,
        default: 2.0,
        required: false,
        min: 0.0,
        max: nil,
        options: nil,
        description: "Standard deviation multiplier"
      }
  """
  defmodule ParamMetadata do
    @moduledoc """
    Struct representing parameter metadata for trading indicators.

    This struct ensures all parameter metadata has consistent structure
    and enforces the presence of required fields.
    """
    @enforce_keys [:name, :type, :default, :required]
    defstruct [
      :name,
      :type,
      :default,
      :required,
      :min,
      :max,
      :options,
      :description
    ]

    @type t :: %__MODULE__{
            name: atom(),
            type: :integer | :float | :string | :atom,
            default: term(),
            required: boolean(),
            min: number() | nil,
            max: number() | nil,
            options: [atom() | String.t()] | nil,
            description: String.t() | nil
          }
  end

  @type param_metadata :: ParamMetadata.t()

  defmodule OutputFieldMetadata do
    @moduledoc """
    Struct representing output field metadata for trading indicators.

    Describes the fields available in an indicator's output, enabling
    users to discover what values they can reference in strategy conditions.

    ## Examples

    Single-value indicators (SMA, RSI):
        %OutputFieldMetadata{
          type: :single_value,
          description: "Simple Moving Average value",
          unit: "price"
        }

        %OutputFieldMetadata{
          type: :single_value,
          description: "RSI value ranging from 0-100",
          unit: "%"
        }

    Multi-value indicators (Bollinger Bands, MACD):
        %OutputFieldMetadata{
          type: :multi_value,
          fields: [
            %{name: :upper_band, type: :decimal, description: "Upper band (SMA + 2×std)", unit: "price"},
            %{name: :middle_band, type: :decimal, description: "Middle band (SMA)", unit: "price"},
            %{name: :lower_band, type: :decimal, description: "Lower band (SMA - 2×std)", unit: "price"}
          ]
        }
    """
    @enforce_keys [:type]
    defstruct [
      :type,
      :fields,
      :description,
      :example,
      :unit
    ]

    @type field_info :: %{
            name: atom(),
            type: :decimal | :integer | :map,
            description: String.t() | nil,
            unit: String.t() | nil
          }

    @type t :: %__MODULE__{
            type: :single_value | :multi_value,
            fields: [field_info()] | nil,
            description: String.t() | nil,
            example: String.t() | nil,
            unit: String.t() | nil
          }
  end

  @type output_field_metadata :: OutputFieldMetadata.t()
end
