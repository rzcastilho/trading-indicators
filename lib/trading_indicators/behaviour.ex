defmodule TradingIndicators.Behaviour do
  @moduledoc """
  Core behaviour defining the contract that all trading indicator modules must implement.

  This behaviour ensures consistency across all indicator implementations and provides
  both batch processing and streaming capabilities for real-time data processing.

  ## Callback Functions

  - `calculate/2` - Main function for batch calculation of the indicator
  - `validate_params/1` - Validates input parameters before calculation
  - `required_periods/0` - Returns minimum number of data points needed
  - `init_state/1` - (Optional) Initializes streaming state
  - `update_state/2` - (Optional) Updates streaming state with new data point

  ## Example Implementation

      defmodule MyIndicator do
        @behaviour TradingIndicators.Behaviour

        @impl true
        def calculate(data, opts) do
          # Implementation here
          {:ok, results}
        end

        @impl true
        def validate_params(opts) do
          # Validation logic
          :ok
        end

        @impl true
        def required_periods, do: 10
      end
  """

  alias TradingIndicators.Types

  @doc """
  Calculates the indicator values for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points or extracted price series
  - `opts` - Keyword list of options specific to the indicator

  ## Returns

  - `{:ok, results}` - List of calculated indicator values
  - `{:error, reason}` - Error tuple with reason for failure
  """
  @callback calculate(data :: Types.data_series() | [number()], opts :: keyword()) ::
              {:ok, Types.result_series() | [number()]} | {:error, term()}

  @doc """
  Validates the provided parameters for the indicator.

  ## Parameters

  - `opts` - Keyword list of options to validate

  ## Returns

  - `:ok` - Parameters are valid
  - `{:error, reason}` - Parameters are invalid with reason
  """
  @callback validate_params(opts :: keyword()) :: :ok | {:error, term()}

  @doc """
  Returns the minimum number of data points required to calculate the indicator.

  This is used for data validation and to determine when sufficient data
  is available for calculation.

  ## Returns

  - `non_neg_integer()` - Minimum number of periods required
  """
  @callback required_periods() :: non_neg_integer()

  @doc """
  Returns metadata describing all parameters accepted by the indicator.

  This callback provides comprehensive information about each parameter,
  including its type, default value, validation constraints, and valid options.
  This metadata can be used for:

  - Automatic parameter validation
  - Documentation generation
  - UI construction (forms, parameter selectors)
  - API introspection

  ## Returns

  - `[Types.param_metadata()]` - List of parameter metadata structs

  ## Example

      def parameter_metadata do
        [
          %Types.ParamMetadata{
            name: :period,
            type: :integer,
            default: 20,
            required: false,
            min: 1,
            max: nil,
            options: nil,
            description: "Number of periods to use in calculation"
          },
          %Types.ParamMetadata{
            name: :source,
            type: :atom,
            default: :close,
            required: false,
            min: nil,
            max: nil,
            options: [:open, :high, :low, :close],
            description: "Source price field to use"
          }
        ]
      end
  """
  @callback parameter_metadata() :: [Types.param_metadata()]

  @doc """
  Initializes the streaming state for the indicator.

  This callback is optional and only needed for indicators that support
  streaming/real-time updates. The state should contain all necessary
  information to process incoming data points incrementally.

  ## Parameters

  - `opts` - Keyword list of options for state initialization

  ## Returns

  - Initial state term specific to the indicator implementation
  """
  @callback init_state(opts :: keyword()) :: term()

  @doc """
  Updates the streaming state with a new data point.

  This callback is optional and processes a single new data point,
  updating the internal state and optionally returning a new indicator value.

  ## Parameters

  - `state` - Current indicator state
  - `data_point` - New OHLCV data point to process

  ## Returns

  - `{:ok, new_state, result}` - Updated state and new indicator value
  - `{:ok, new_state, nil}` - Updated state, no new value yet (insufficient data)
  - `{:error, reason}` - Error occurred during processing
  """
  @callback update_state(state :: term(), data_point :: Types.ohlcv() | number()) ::
              {:ok, term(), Types.indicator_result() | number() | nil} | {:error, term()}

  @optional_callbacks [init_state: 1, update_state: 2]
end
