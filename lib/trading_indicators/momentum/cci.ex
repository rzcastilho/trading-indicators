defmodule TradingIndicators.Momentum.CCI do
  @moduledoc """
  Commodity Channel Index (CCI) momentum oscillator implementation.

  The Commodity Channel Index is a versatile indicator that can be used to identify 
  a new trend or warn of extreme conditions. It measures the variation of a security's 
  price from its statistical mean. High values show that prices are unusually high 
  compared to average prices, whereas low values indicate that prices are unusually 
  low compared to average prices.

  ## Formula

  CCI = (Typical Price - Moving Average of Typical Price) / (0.015 * Mean Deviation)

  Where:
  - **Typical Price** = (High + Low + Close) / 3
  - **Moving Average** = SMA of Typical Price over n periods
  - **Mean Deviation** = Average of absolute deviations from the moving average
  - **Constant (0.015)** = Used to normalize the index to approximately ±100

  ## Scale and Interpretation

  CCI is an unbounded oscillator, meaning it can range from -∞ to +∞:
  - **CCI > +100**: Generally considered overbought (potential sell signal)
  - **CCI < -100**: Generally considered oversold (potential buy signal)
  - **CCI between ±100**: Normal trading range (about 70-80% of values)

  ## Examples

      iex> data = [
      ...>   %{high: Decimal.new("105"), low: Decimal.new("95"), close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{high: Decimal.new("107"), low: Decimal.new("97"), close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{high: Decimal.new("106"), low: Decimal.new("96"), close: Decimal.new("101"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Momentum.CCI.calculate(data, period: 3)
      iex> length(result)
      1

  ## Parameters

  - `:period` - Number of periods for calculation (default: 20)
  - `:constant` - Lambert constant for normalization (default: 0.015)

  ## Trading Applications

  1. **Overbought/Oversold**: Values above +100 or below -100
  2. **Trend Identification**: Direction of CCI indicates trend direction
  3. **Divergences**: When CCI and price move in opposite directions
  4. **Zero Line Crossovers**: CCI crossing above/below zero line

  ## Lambert's Constant

  The 0.015 constant was chosen by Donald Lambert to ensure that approximately
  70-80% of CCI values fall between -100 and +100. This can be adjusted:
  - Smaller constant (0.010): More sensitive, more signals
  - Larger constant (0.020): Less sensitive, fewer signals

  ## Notes

  - Requires at least `period` data points for calculation
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates
  - Requires OHLCV data with high, low, and close fields
  - Unbounded oscillator (no fixed upper/lower limits)
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  require Decimal

  @default_period 20
  @default_constant "0.015"

  @doc """
  Calculates Commodity Channel Index for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points (requires high, low, close)
  - `opts` - Calculation options (keyword list)

  ## Options

  - `:period` - Number of periods (default: #{@default_period})
  - `:constant` - Lambert constant for normalization (default: #{@default_constant})

  ## Returns

  - `{:ok, results}` - List of CCI calculations  
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [
        %{high: Decimal.new("105"), low: Decimal.new("95"), close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{high: Decimal.new("107"), low: Decimal.new("97"), close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]}
      ]
      {:ok, result} = CCI.calculate(data, period: 20)
  """
  @impl true
  @spec calculate(Types.data_series(), keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         period <- Keyword.get(opts, :period, @default_period),
         constant <- Keyword.get(opts, :constant, @default_constant) |> Decimal.new(),
         :ok <- validate_data_format(data),
         :ok <- Utils.validate_data_length(data, period) do
      calculate_cci_values(data, period, constant)
    end
  end

  @doc """
  Validates parameters for CCI calculation.

  ## Parameters

  - `opts` - Options keyword list

  ## Returns

  - `:ok` if parameters are valid
  - `{:error, exception}` if parameters are invalid
  """
  @impl true
  @spec validate_params(keyword()) :: :ok | {:error, Exception.t()}
  def validate_params(opts) when is_list(opts) do
    period = Keyword.get(opts, :period, @default_period)
    constant = Keyword.get(opts, :constant, @default_constant)

    with :ok <- validate_period(period),
         :ok <- validate_constant(constant) do
      :ok
    end
  end

  def validate_params(_opts) do
    {:error,
     %Errors.InvalidParams{
       message: "Options must be a keyword list",
       param: :opts,
       value: "non-keyword-list",
       expected: "keyword list"
     }}
  end

  @doc """
  Returns the minimum number of periods required for CCI calculation.

  ## Returns

  - Default period if no options provided
  - Configured period from options

  ## Example

      iex> TradingIndicators.Momentum.CCI.required_periods()
      20
  """
  @impl true
  @spec required_periods() :: pos_integer()
  def required_periods, do: @default_period

  @doc """
  Returns required periods for specific configuration.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Required number of periods

  ## Example

      iex> TradingIndicators.Momentum.CCI.required_periods(period: 10)
      10
  """
  @spec required_periods(keyword()) :: pos_integer()
  def required_periods(opts) do
    Keyword.get(opts, :period, @default_period)
  end

  @doc """
  Returns metadata describing all parameters accepted by the CCI indicator.

  ## Returns

  - List of parameter metadata maps
  """
  @impl true
  @spec parameter_metadata() :: [Types.param_metadata()]
  def parameter_metadata do
    [
      %Types.ParamMetadata{
        name: :period,
        type: :integer,
        default: @default_period,
        required: false,
        min: 1,
        max: nil,
        options: nil,
        description: "Number of periods for calculation"
      },
      %Types.ParamMetadata{
        name: :constant,
        type: :float,
        default: 0.015,
        required: false,
        min: 0.0,
        max: nil,
        options: nil,
        description: "Lambert constant for normalization"
      }
    ]
  end

  @doc """
  Returns metadata describing the output fields for CCI.

  ## Returns

  - Output field metadata struct

  ## Example

      iex> metadata = TradingIndicators.Momentum.CCI.output_fields_metadata()
      iex> metadata.type
      :single_value
  """
  @impl true
  @spec output_fields_metadata() :: Types.output_field_metadata()
  def output_fields_metadata do
    %Types.OutputFieldMetadata{
      type: :single_value,
      description: "Commodity Channel Index - momentum oscillator identifying cyclical trends",
      example: "cci_20 > 100 or cci_20 < -100",
      unit: "%"
    }
  end

  @doc """
  Initializes streaming state for real-time CCI calculation.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = CCI.init_state(period: 20)
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    constant = Keyword.get(opts, :constant, @default_constant) |> Decimal.new()

    %{
      period: period,
      constant: constant,
      typical_prices: [],
      count: 0
    }
  end

  @doc """
  Updates streaming state with new data point.

  ## Parameters

  - `state` - Current streaming state
  - `data_point` - New OHLCV data point

  ## Returns

  - `{:ok, new_state, cci_value}` - Updated state with result
  - `{:ok, new_state, nil}` - Updated state, insufficient data
  - `{:error, reason}` - Error occurred

  ## Example

      state = CCI.init_state(period: 20)
      data_point = %{high: Decimal.new("105"), low: Decimal.new("95"), close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = CCI.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_state(
        %{period: period, constant: constant, typical_prices: typical_prices, count: count} =
          _state,
        %{high: high, low: low, close: close} = data_point
      ) do
    try do
      new_count = count + 1

      # Calculate typical price for current data point
      typical_price = calculate_typical_price(high, low, close)

      # Update typical prices buffer
      new_typical_prices = update_buffer(typical_prices, typical_price, period)

      new_state = %{
        period: period,
        constant: constant,
        typical_prices: new_typical_prices,
        count: new_count
      }

      # Calculate CCI if we have enough data
      if new_count >= period do
        cci_value = calculate_cci_value(new_typical_prices, period, constant)
        timestamp = Map.get(data_point, :timestamp, DateTime.utc_now())

        result = %{
          value: cci_value,
          timestamp: timestamp,
          metadata: %{
            indicator: "CCI",
            period: period,
            constant: Decimal.to_string(constant),
            signal: determine_signal(cci_value)
          }
        }

        {:ok, new_state, result}
      else
        {:ok, new_state, nil}
      end
    rescue
      error -> {:error, error}
    end
  end

  def update_state(_state, _data_point) do
    {:error,
     %Errors.StreamStateError{
       message: "Invalid state format for CCI streaming",
       operation: :update_state,
       reason: "malformed state or missing required OHLC fields"
     }}
  end

  # Private functions

  defp validate_period(period) when is_integer(period) and period >= 1, do: :ok

  defp validate_period(period) do
    {:error, Errors.invalid_period(period)}
  end

  defp validate_constant(constant) when is_binary(constant) do
    try do
      decimal_constant = Decimal.new(constant)
      if Decimal.gt?(decimal_constant, Decimal.new("0")), do: :ok, else: raise("negative")
    rescue
      _ ->
        {:error,
         %Errors.InvalidParams{
           message: "Constant must be a positive number string, got #{inspect(constant)}",
           param: :constant,
           value: constant,
           expected: "positive number string"
         }}
    end
  end

  defp validate_constant(constant) when is_number(constant) and constant > 0, do: :ok

  defp validate_constant(constant) do
    {:error,
     %Errors.InvalidParams{
       message: "Constant must be a positive number, got #{inspect(constant)}",
       param: :constant,
       value: constant,
       expected: "positive number"
     }}
  end

  defp validate_data_format([]), do: :ok

  defp validate_data_format([first | _rest]) do
    case first do
      %{high: _, low: _, close: _} ->
        :ok

      _ ->
        {:error,
         %Errors.InvalidDataFormat{
           message: "CCI requires OHLCV data with high, low, and close fields",
           expected: "OHLCV data with :high, :low, :close fields",
           received: "data without required fields"
         }}
    end
  end

  defp calculate_cci_values(data, period, constant) do
    # Calculate typical prices for all data points
    typical_prices =
      Enum.map(data, fn %{high: h, low: l, close: c} ->
        calculate_typical_price(h, l, c)
      end)

    # Calculate CCI values using sliding windows
    typical_price_windows = Utils.sliding_window(typical_prices, period)

    cci_values =
      Enum.map(typical_price_windows, fn window ->
        calculate_cci_value(window, period, constant)
      end)

    # Build results
    results = build_cci_results(cci_values, period, constant, data)

    {:ok, results}
  end

  defp calculate_typical_price(high, low, close) do
    Utils.typical_price(%{high: high, low: low, close: close})
  end

  defp calculate_cci_value(typical_prices, _period, constant) do
    # Calculate simple moving average of typical prices
    sma_typical = Utils.mean(typical_prices)

    # Calculate mean deviation
    mean_deviation = calculate_mean_deviation(typical_prices, sma_typical)

    # Calculate CCI
    current_typical = List.last(typical_prices)
    numerator = Decimal.sub(current_typical, sma_typical)
    denominator = Decimal.mult(constant, mean_deviation)

    case Decimal.equal?(denominator, Decimal.new("0")) do
      # Avoid division by zero
      true ->
        Decimal.new("0")

      false ->
        Decimal.div(numerator, denominator)
    end
  end

  defp calculate_mean_deviation(values, mean_value) do
    # Mean deviation = average of absolute deviations from the mean
    deviations =
      Enum.map(values, fn value ->
        Decimal.abs(Decimal.sub(value, mean_value))
      end)

    Utils.mean(deviations)
  end

  defp build_cci_results(cci_values, period, constant, original_data) do
    cci_values
    |> Enum.with_index(period - 1)
    |> Enum.map(fn {cci_value, index} ->
      timestamp = get_data_timestamp(original_data, index)

      %{
        value: cci_value,
        timestamp: timestamp,
        metadata: %{
          indicator: "CCI",
          period: period,
          constant: Decimal.to_string(constant),
          signal: determine_signal(cci_value)
        }
      }
    end)
  end

  defp determine_signal(cci_value) do
    hundred = Decimal.new("100")
    minus_hundred = Decimal.new("-100")

    cond do
      Decimal.gt?(cci_value, hundred) -> :overbought
      Decimal.lt?(cci_value, minus_hundred) -> :oversold
      true -> :neutral
    end
  end

  defp get_data_timestamp(data, index) when is_list(data) do
    if index < length(data) do
      case Enum.at(data, index) do
        %{timestamp: timestamp} -> timestamp
        _ -> DateTime.utc_now()
      end
    else
      DateTime.utc_now()
    end
  end

  defp update_buffer(buffer, new_value, max_size) do
    updated_buffer = buffer ++ [new_value]

    if length(updated_buffer) > max_size do
      Enum.take(updated_buffer, -max_size)
    else
      updated_buffer
    end
  end
end
