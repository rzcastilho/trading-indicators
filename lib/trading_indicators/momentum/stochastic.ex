defmodule TradingIndicators.Momentum.Stochastic do
  @moduledoc """
  Stochastic Oscillator momentum indicator implementation.

  The Stochastic Oscillator is a momentum indicator that uses support and resistance
  levels. It compares a particular closing price of a security to a range of its prices
  over a certain period of time. The oscillator's sensitivity to market movements is 
  reducible by adjusting that time period or by taking a moving average of the result.

  ## Formula

  **%K (Fast Stochastic):**
  %K = 100 * ((C - Ln) / (Hn - Ln))

  **%D (Slow Stochastic):**  
  %D = SMA of %K over d periods

  Where:
  - C = Current closing price
  - Ln = Lowest price over the last n periods
  - Hn = Highest price over the last n periods
  - n = %K period (typically 14)
  - d = %D period (typically 3)

  ## Variants

  - **Fast Stochastic**: Uses raw %K and %D calculations
  - **Slow Stochastic**: Applies additional smoothing to %K before calculating %D
  - **Full Stochastic**: Customizable smoothing for both %K and %D

  ## Examples

      iex> data = [
      ...>   %{high: Decimal.new("105"), low: Decimal.new("95"), close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{high: Decimal.new("107"), low: Decimal.new("97"), close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{high: Decimal.new("106"), low: Decimal.new("96"), close: Decimal.new("101"), timestamp: ~U[2024-01-01 09:32:00Z]},
      ...>   %{high: Decimal.new("108"), low: Decimal.new("98"), close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:33:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Momentum.Stochastic.calculate(data, k_period: 3, d_period: 2)
      iex> length(result)
      1

  ## Parameters

  - `:k_period` - Number of periods for %K calculation (default: 14)
  - `:d_period` - Number of periods for %D smoothing (default: 3)
  - `:k_smoothing` - Smoothing periods for %K (default: 1, no smoothing)
  - `:overbought` - Overbought threshold level (default: 80)
  - `:oversold` - Oversold threshold level (default: 20)

  ## Interpretation

  - **%K or %D > 80**: Generally considered overbought (potential sell signal)
  - **%K or %D < 20**: Generally considered oversold (potential buy signal)
  - **%K crossing above %D**: Potential bullish signal
  - **%K crossing below %D**: Potential bearish signal
  - **Divergences**: When oscillator and price move in opposite directions

  ## Notes

  - Requires at least `k_period` data points for %K calculation
  - %D requires additional `d_period` data points after %K calculation
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates
  - Returns both %K and %D values in result metadata
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  require Decimal

  @default_k_period 14
  @default_d_period 3
  @default_k_smoothing 1
  @default_overbought 80
  @default_oversold 20

  @doc """
  Calculates Stochastic Oscillator for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points (requires high, low, close)
  - `opts` - Calculation options (keyword list)

  ## Options

  - `:k_period` - Periods for %K calculation (default: #{@default_k_period})
  - `:d_period` - Periods for %D smoothing (default: #{@default_d_period})
  - `:k_smoothing` - Smoothing for %K (default: #{@default_k_smoothing})
  - `:overbought` - Overbought level (default: #{@default_overbought})
  - `:oversold` - Oversold level (default: #{@default_oversold})

  ## Returns

  - `{:ok, results}` - List of Stochastic calculations  
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [
        %{high: Decimal.new("105"), low: Decimal.new("95"), close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{high: Decimal.new("107"), low: Decimal.new("97"), close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]}
      ]
      {:ok, result} = Stochastic.calculate(data, k_period: 14, d_period: 3)
  """
  @impl true
  @spec calculate(Types.data_series(), keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         k_period <- Keyword.get(opts, :k_period, @default_k_period),
         d_period <- Keyword.get(opts, :d_period, @default_d_period),
         k_smoothing <- Keyword.get(opts, :k_smoothing, @default_k_smoothing),
         overbought <- Keyword.get(opts, :overbought, @default_overbought),
         oversold <- Keyword.get(opts, :oversold, @default_oversold),
         :ok <- validate_data_format(data),
         :ok <- Utils.validate_data_length(data, k_period + d_period - 1) do
      calculate_stochastic_values(data, k_period, d_period, k_smoothing, overbought, oversold)
    end
  end

  @doc """
  Validates parameters for Stochastic calculation.

  ## Parameters

  - `opts` - Options keyword list

  ## Returns

  - `:ok` if parameters are valid
  - `{:error, exception}` if parameters are invalid
  """
  @impl true
  @spec validate_params(keyword()) :: :ok | {:error, Exception.t()}
  def validate_params(opts) when is_list(opts) do
    k_period = Keyword.get(opts, :k_period, @default_k_period)
    d_period = Keyword.get(opts, :d_period, @default_d_period)
    k_smoothing = Keyword.get(opts, :k_smoothing, @default_k_smoothing)
    overbought = Keyword.get(opts, :overbought, @default_overbought)
    oversold = Keyword.get(opts, :oversold, @default_oversold)

    with :ok <- validate_period(k_period, :k_period),
         :ok <- validate_period(d_period, :d_period),
         :ok <- validate_period(k_smoothing, :k_smoothing),
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
  Returns the minimum number of periods required for Stochastic calculation.

  ## Returns

  - Default k_period + d_period - 1 if no options provided
  - Configured periods from options

  ## Example

      iex> TradingIndicators.Momentum.Stochastic.required_periods()
      16
  """
  @impl true
  @spec required_periods() :: pos_integer()
  def required_periods, do: @default_k_period + @default_d_period - 1

  @doc """
  Returns required periods for specific configuration.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Required number of periods

  ## Example

      iex> TradingIndicators.Momentum.Stochastic.required_periods(k_period: 10, d_period: 3)
      12
  """
  @spec required_periods(keyword()) :: pos_integer()
  def required_periods(opts) do
    k_period = Keyword.get(opts, :k_period, @default_k_period)
    d_period = Keyword.get(opts, :d_period, @default_d_period)
    k_period + d_period - 1
  end

  @doc """
  Returns metadata describing all parameters accepted by the Stochastic Oscillator indicator.

  ## Returns

  - List of parameter metadata maps
  """
  @impl true
  @spec parameter_metadata() :: [Types.param_metadata()]
  def parameter_metadata do
    [
      %Types.ParamMetadata{
        name: :k_period,
        type: :integer,
        default: @default_k_period,
        required: false,
        min: 1,
        max: nil,
        options: nil,
        description: "Number of periods for %K calculation"
      },
      %Types.ParamMetadata{
        name: :d_period,
        type: :integer,
        default: @default_d_period,
        required: false,
        min: 1,
        max: nil,
        options: nil,
        description: "Number of periods for %D smoothing"
      },
      %Types.ParamMetadata{
        name: :k_smoothing,
        type: :integer,
        default: @default_k_smoothing,
        required: false,
        min: 1,
        max: nil,
        options: nil,
        description: "Smoothing periods for %K"
      },
      %Types.ParamMetadata{
        name: :overbought,
        type: :integer,
        default: @default_overbought,
        required: false,
        min: 0,
        max: 100,
        options: nil,
        description: "Overbought threshold level"
      },
      %Types.ParamMetadata{
        name: :oversold,
        type: :integer,
        default: @default_oversold,
        required: false,
        min: 0,
        max: 100,
        options: nil,
        description: "Oversold threshold level"
      }
    ]
  end

  @doc """
  Initializes streaming state for real-time Stochastic calculation.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = Stochastic.init_state(k_period: 14, d_period: 3)
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    k_period = Keyword.get(opts, :k_period, @default_k_period)
    d_period = Keyword.get(opts, :d_period, @default_d_period)
    k_smoothing = Keyword.get(opts, :k_smoothing, @default_k_smoothing)
    overbought = Keyword.get(opts, :overbought, @default_overbought)
    oversold = Keyword.get(opts, :oversold, @default_oversold)

    %{
      k_period: k_period,
      d_period: d_period,
      k_smoothing: k_smoothing,
      overbought: overbought,
      oversold: oversold,
      highs: [],
      lows: [],
      closes: [],
      k_values: [],
      count: 0
    }
  end

  @doc """
  Updates streaming state with new data point.

  ## Parameters

  - `state` - Current streaming state
  - `data_point` - New OHLCV data point

  ## Returns

  - `{:ok, new_state, result}` - Updated state with result
  - `{:ok, new_state, nil}` - Updated state, insufficient data
  - `{:error, reason}` - Error occurred

  ## Example

      state = Stochastic.init_state(k_period: 14, d_period: 3)
      data_point = %{high: Decimal.new("105"), low: Decimal.new("95"), close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = Stochastic.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_state(
        %{
          k_period: k_period,
          d_period: d_period,
          k_smoothing: k_smoothing,
          overbought: overbought,
          oversold: oversold,
          highs: highs,
          lows: lows,
          closes: closes,
          k_values: k_values,
          count: count
        } = _state,
        %{high: high, low: low, close: close} = data_point
      ) do
    try do
      new_count = count + 1

      # Update price buffers
      new_highs = update_buffer(highs, high, k_period)
      new_lows = update_buffer(lows, low, k_period)
      new_closes = update_buffer(closes, close, k_period)

      # Calculate %K if we have enough data
      {new_k_values, result} =
        if new_count >= k_period do
          k_value = calculate_k_value(new_highs, new_lows, close)

          smoothed_k =
            if k_smoothing > 1 do
              # Apply smoothing to %K
              temp_k_values = update_buffer(k_values, k_value, k_smoothing)

              if length(temp_k_values) >= k_smoothing do
                Utils.mean(temp_k_values)
              else
                k_value
              end
            else
              k_value
            end

          updated_k_values = update_buffer(k_values, smoothed_k, d_period)

          # Calculate %D if we have enough %K values
          if length(updated_k_values) >= d_period do
            d_value = Utils.mean(updated_k_values)
            timestamp = Map.get(data_point, :timestamp, DateTime.utc_now())

            result = %{
              value: %{
                k: smoothed_k,
                d: d_value
              },
              timestamp: timestamp,
              metadata: %{
                indicator: "Stochastic",
                k_period: k_period,
                d_period: d_period,
                k_smoothing: k_smoothing,
                overbought: overbought,
                oversold: oversold,
                k_signal: determine_signal(smoothed_k, overbought, oversold),
                d_signal: determine_signal(d_value, overbought, oversold),
                crossover: determine_crossover(smoothed_k, d_value)
              }
            }

            {updated_k_values, result}
          else
            {updated_k_values, nil}
          end
        else
          {k_values, nil}
        end

      new_state = %{
        k_period: k_period,
        d_period: d_period,
        k_smoothing: k_smoothing,
        overbought: overbought,
        oversold: oversold,
        highs: new_highs,
        lows: new_lows,
        closes: new_closes,
        k_values: new_k_values,
        count: new_count
      }

      {:ok, new_state, result}
    rescue
      error -> {:error, error}
    end
  end

  def update_state(_state, _data_point) do
    {:error,
     %Errors.StreamStateError{
       message: "Invalid state format for Stochastic streaming",
       operation: :update_state,
       reason: "malformed state or missing required OHLC fields"
     }}
  end

  # Private functions

  defp validate_period(period, _name) when is_integer(period) and period >= 1, do: :ok

  defp validate_period(period, name) do
    {:error,
     %Errors.InvalidParams{
       message: "#{name} must be a positive integer, got #{inspect(period)}",
       param: name,
       value: period,
       expected: "positive integer"
     }}
  end

  defp validate_level(level, _name) when is_number(level) and level >= 0 and level <= 100, do: :ok

  defp validate_level(level, name) do
    {:error,
     %Errors.InvalidParams{
       message: "Invalid #{name} level: #{inspect(level)}",
       param: name,
       value: level,
       expected: "number between 0 and 100"
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
           message: "Stochastic requires OHLCV data with high, low, and close fields",
           expected: "OHLCV data with :high, :low, :close fields",
           received: "data without required fields"
         }}
    end
  end

  defp calculate_stochastic_values(data, k_period, d_period, k_smoothing, overbought, oversold) do
    # Extract price series
    highs = Utils.extract_highs(data)
    lows = Utils.extract_lows(data)
    closes = Utils.extract_closes(data)

    # Calculate %K values
    k_values = calculate_k_series(highs, lows, closes, k_period)

    # Apply K smoothing if specified
    smoothed_k_values =
      if k_smoothing > 1 do
        apply_smoothing(k_values, k_smoothing)
      else
        k_values
      end

    # Calculate %D values
    d_values = calculate_d_series(smoothed_k_values, d_period)

    # Build results
    results =
      build_stochastic_results(
        smoothed_k_values,
        d_values,
        k_period,
        d_period,
        k_smoothing,
        overbought,
        oversold,
        data
      )

    {:ok, results}
  end

  defp calculate_k_series(highs, lows, closes, k_period) do
    high_windows = Utils.sliding_window(highs, k_period)
    low_windows = Utils.sliding_window(lows, k_period)
    close_slice = Enum.drop(closes, k_period - 1)

    Enum.zip([high_windows, low_windows, close_slice])
    |> Enum.map(fn {high_window, low_window, close} ->
      calculate_k_value(high_window, low_window, close)
    end)
  end

  defp calculate_k_value(highs, lows, close) do
    highest_high = Enum.max_by(highs, &Decimal.to_float/1)
    lowest_low = Enum.min_by(lows, &Decimal.to_float/1)

    numerator = Decimal.sub(close, lowest_low)
    denominator = Decimal.sub(highest_high, lowest_low)

    case Decimal.equal?(denominator, Decimal.new("0")) do
      # Neutral when no price range
      true ->
        Decimal.new("50.0")

      false ->
        ratio = Decimal.div(numerator, denominator)
        Decimal.mult(ratio, Decimal.new("100"))
    end
  end

  defp apply_smoothing(values, smoothing_period) do
    Utils.sliding_window(values, smoothing_period)
    |> Enum.map(&Utils.mean/1)
  end

  defp calculate_d_series(k_values, d_period) do
    Utils.sliding_window(k_values, d_period)
    |> Enum.map(&Utils.mean/1)
  end

  defp build_stochastic_results(
         k_values,
         d_values,
         k_period,
         d_period,
         k_smoothing,
         overbought,
         oversold,
         original_data
       ) do
    # Align results - D values start later due to additional smoothing
    start_index = k_period + d_period - 2
    k_aligned = Enum.drop(k_values, d_period - 1)

    Enum.zip(k_aligned, d_values)
    |> Enum.with_index(start_index)
    |> Enum.map(fn {{k_value, d_value}, index} ->
      timestamp = get_data_timestamp(original_data, index)

      %{
        value: %{
          k: k_value,
          d: d_value
        },
        timestamp: timestamp,
        metadata: %{
          indicator: "Stochastic",
          k_period: k_period,
          d_period: d_period,
          k_smoothing: k_smoothing,
          overbought: overbought,
          oversold: oversold,
          k_signal: determine_signal(k_value, overbought, oversold),
          d_signal: determine_signal(d_value, overbought, oversold),
          crossover: determine_crossover(k_value, d_value)
        }
      }
    end)
  end

  defp determine_signal(value, overbought, oversold) do
    overbought_decimal = Decimal.new(overbought)
    oversold_decimal = Decimal.new(oversold)

    cond do
      Decimal.gt?(value, overbought_decimal) -> :overbought
      Decimal.lt?(value, oversold_decimal) -> :oversold
      true -> :neutral
    end
  end

  defp determine_crossover(k_value, d_value) do
    cond do
      Decimal.gt?(k_value, d_value) -> :bullish
      Decimal.lt?(k_value, d_value) -> :bearish
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
