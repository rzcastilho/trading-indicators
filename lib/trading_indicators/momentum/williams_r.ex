defmodule TradingIndicators.Momentum.WilliamsR do
  @moduledoc """
  Williams %R momentum oscillator implementation.

  Williams %R, also known as Williams Percent Range, is a momentum indicator that
  moves between 0 and -100 and measures overbought and oversold levels. It is
  similar to the Stochastic Oscillator but is inverted and uses a different scale.

  ## Formula

  %R = -100 * ((Highest High - Current Close) / (Highest High - Lowest Low))

  Where:
  - Highest High = Highest price over the last n periods
  - Lowest Low = Lowest price over the last n periods
  - Current Close = Current closing price
  - n = lookback period (typically 14)

  ## Scale and Interpretation

  Williams %R oscillates between 0 and -100:
  - **0 to -20**: Generally considered overbought (potential sell signal)
  - **-80 to -100**: Generally considered oversold (potential buy signal)
  - **-20 to -80**: Normal trading range

  ## Examples

      iex> data = [
      ...>   %{high: Decimal.new("105"), low: Decimal.new("95"), close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{high: Decimal.new("107"), low: Decimal.new("97"), close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{high: Decimal.new("106"), low: Decimal.new("96"), close: Decimal.new("101"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Momentum.WilliamsR.calculate(data, period: 3)
      iex> length(result)
      1

  ## Parameters

  - `:period` - Number of periods for calculation (default: 14)
  - `:overbought` - Overbought threshold level (default: -20)
  - `:oversold` - Oversold threshold level (default: -80)

  ## Comparison with Stochastic

  Williams %R is essentially the inverse of the Fast Stochastic:
  - Stochastic %K ranges from 0 to 100
  - Williams %R ranges from 0 to -100
  - Williams %R = Stochastic %K - 100

  ## Trading Signals

  - **%R crosses above -80**: Potential bullish signal (exit oversold)
  - **%R crosses below -20**: Potential bearish signal (exit overbought)
  - **Divergences**: When %R and price move in opposite directions
  - **Failure swings**: %R fails to exceed -20 (bearish) or -80 (bullish)

  ## Notes

  - Requires at least `period` data points for calculation
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates
  - Requires OHLCV data with high, low, and close fields
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  require Decimal

  @default_period 14
  @default_overbought -20
  @default_oversold -80

  @doc """
  Calculates Williams %R for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points (requires high, low, close)
  - `opts` - Calculation options (keyword list)

  ## Options

  - `:period` - Number of periods (default: #{@default_period})
  - `:overbought` - Overbought level (default: #{@default_overbought})
  - `:oversold` - Oversold level (default: #{@default_oversold})

  ## Returns

  - `{:ok, results}` - List of Williams %R calculations  
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [
        %{high: Decimal.new("105"), low: Decimal.new("95"), close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{high: Decimal.new("107"), low: Decimal.new("97"), close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]}
      ]
      {:ok, result} = WilliamsR.calculate(data, period: 14)
  """
  @impl true
  @spec calculate(Types.data_series(), keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         period <- Keyword.get(opts, :period, @default_period),
         overbought <- Keyword.get(opts, :overbought, @default_overbought),
         oversold <- Keyword.get(opts, :oversold, @default_oversold),
         :ok <- validate_data_format(data),
         :ok <- Utils.validate_data_length(data, period) do
      calculate_williams_r_values(data, period, overbought, oversold)
    end
  end

  @doc """
  Validates parameters for Williams %R calculation.

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
    overbought = Keyword.get(opts, :overbought, @default_overbought)
    oversold = Keyword.get(opts, :oversold, @default_oversold)

    with :ok <- validate_period(period),
         :ok <- validate_level(overbought, :overbought),
         :ok <- validate_level(oversold, :oversold),
         :ok <- validate_level_relationship(oversold, overbought) do
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
  Returns the minimum number of periods required for Williams %R calculation.

  ## Returns

  - Default period if no options provided
  - Configured period from options

  ## Example

      iex> TradingIndicators.Momentum.WilliamsR.required_periods()
      14
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

      iex> TradingIndicators.Momentum.WilliamsR.required_periods(period: 10)
      10
  """
  @spec required_periods(keyword()) :: pos_integer()
  def required_periods(opts) do
    Keyword.get(opts, :period, @default_period)
  end

  @doc """
  Returns metadata describing all parameters accepted by the Williams %R indicator.

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
        name: :overbought,
        type: :integer,
        default: @default_overbought,
        required: false,
        min: -100,
        max: 0,
        options: nil,
        description: "Overbought threshold level"
      },
      %Types.ParamMetadata{
        name: :oversold,
        type: :integer,
        default: @default_oversold,
        required: false,
        min: -100,
        max: 0,
        options: nil,
        description: "Oversold threshold level"
      }
    ]
  end

  @doc """
  Returns metadata describing the output fields for Williams %R.

  ## Returns

  - Output field metadata struct

  ## Example

      iex> metadata = TradingIndicators.Momentum.WilliamsR.output_fields_metadata()
      iex> metadata.type
      :single_value
  """
  @impl true
  @spec output_fields_metadata() :: Types.output_field_metadata()
  def output_fields_metadata do
    %Types.OutputFieldMetadata{
      type: :single_value,
      description: "Williams %R - momentum indicator measuring overbought/oversold levels",
      example: "williams_r_14 < -80 or williams_r_14 > -20"
    }
  end

  @doc """
  Initializes streaming state for real-time Williams %R calculation.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = WilliamsR.init_state(period: 14)
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    overbought = Keyword.get(opts, :overbought, @default_overbought)
    oversold = Keyword.get(opts, :oversold, @default_oversold)

    %{
      period: period,
      overbought: overbought,
      oversold: oversold,
      recent_highs: [],
      recent_lows: [],
      count: 0
    }
  end

  @doc """
  Updates streaming state with new data point.

  ## Parameters

  - `state` - Current streaming state
  - `data_point` - New OHLCV data point

  ## Returns

  - `{:ok, new_state, williams_r_value}` - Updated state with result
  - `{:ok, new_state, nil}` - Updated state, insufficient data
  - `{:error, reason}` - Error occurred

  ## Example

      state = WilliamsR.init_state(period: 14)
      data_point = %{high: Decimal.new("105"), low: Decimal.new("95"), close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = WilliamsR.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_state(
        %{
          period: period,
          overbought: overbought,
          oversold: oversold,
          recent_highs: highs,
          recent_lows: lows,
          count: count
        } = _state,
        %{high: high, low: low, close: close} = data_point
      ) do
    try do
      new_count = count + 1

      # Update buffers
      new_highs = update_buffer(highs, high, period)
      new_lows = update_buffer(lows, low, period)

      new_state = %{
        period: period,
        overbought: overbought,
        oversold: oversold,
        recent_highs: new_highs,
        recent_lows: new_lows,
        count: new_count
      }

      # Calculate Williams %R if we have enough data
      if new_count >= period do
        williams_r_value = calculate_williams_r_value(new_highs, new_lows, close)
        timestamp = Map.get(data_point, :timestamp, DateTime.utc_now())

        result = %{
          value: williams_r_value,
          timestamp: timestamp,
          metadata: %{
            indicator: "Williams %R",
            period: period,
            overbought: overbought,
            oversold: oversold,
            signal: determine_signal(williams_r_value, overbought, oversold)
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
       message: "Invalid state format for Williams %R streaming",
       operation: :update_state,
       reason: "malformed state or missing required OHLC fields"
     }}
  end

  # Private functions

  defp validate_period(period) when is_integer(period) and period >= 1, do: :ok

  defp validate_period(period) do
    {:error, Errors.invalid_period(period)}
  end

  defp validate_level(level, _name) when is_number(level) and level >= -100 and level <= 0, do: :ok

  defp validate_level(level, name) do
    {:error,
     %Errors.InvalidParams{
       message: "Invalid #{name} level: #{inspect(level)}",
       param: name,
       value: level,
       expected: "number between -100 and 0"
     }}
  end

  defp validate_level_relationship(oversold, overbought) when oversold < overbought, do: :ok

  defp validate_level_relationship(oversold, overbought) do
    {:error,
     %Errors.InvalidParams{
       message: "Oversold level (#{oversold}) must be less than overbought level (#{overbought})",
       param: :levels,
       value: {oversold, overbought},
       expected: "oversold < overbought"
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
           message: "Williams %R requires OHLCV data with high, low, and close fields",
           expected: "OHLCV data with :high, :low, :close fields",
           received: "data without required fields"
         }}
    end
  end

  defp calculate_williams_r_values(data, period, overbought, oversold) do
    # Extract price series
    highs = Utils.extract_highs(data)
    lows = Utils.extract_lows(data)
    closes = Utils.extract_closes(data)

    # Calculate Williams %R values using sliding windows
    high_windows = Utils.sliding_window(highs, period)
    low_windows = Utils.sliding_window(lows, period)
    close_slice = Enum.drop(closes, period - 1)

    williams_r_values =
      Enum.zip([high_windows, low_windows, close_slice])
      |> Enum.map(fn {high_window, low_window, close} ->
        calculate_williams_r_value(high_window, low_window, close)
      end)

    # Build results
    results = build_williams_r_results(williams_r_values, period, overbought, oversold, data)

    {:ok, results}
  end

  defp calculate_williams_r_value(highs, lows, close) do
    highest_high = Enum.max_by(highs, &Decimal.to_float/1)
    lowest_low = Enum.min_by(lows, &Decimal.to_float/1)

    numerator = Decimal.sub(highest_high, close)
    denominator = Decimal.sub(highest_high, lowest_low)

    case Decimal.equal?(denominator, Decimal.new("0")) do
      # Neutral when no price range
      true ->
        Decimal.new("-50.0")

      false ->
        ratio = Decimal.div(numerator, denominator)
        Decimal.mult(ratio, Decimal.new("-100"))
    end
  end

  defp build_williams_r_results(williams_r_values, period, overbought, oversold, original_data) do
    williams_r_values
    |> Enum.with_index(period - 1)
    |> Enum.map(fn {williams_r_value, index} ->
      timestamp = get_data_timestamp(original_data, index)

      %{
        value: williams_r_value,
        timestamp: timestamp,
        metadata: %{
          indicator: "Williams %R",
          period: period,
          overbought: overbought,
          oversold: oversold,
          signal: determine_signal(williams_r_value, overbought, oversold)
        }
      }
    end)
  end

  defp determine_signal(williams_r_value, overbought, oversold) do
    overbought_decimal = Decimal.new(overbought)
    oversold_decimal = Decimal.new(oversold)

    cond do
      Decimal.gt?(williams_r_value, overbought_decimal) -> :overbought
      Decimal.lt?(williams_r_value, oversold_decimal) -> :oversold
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
