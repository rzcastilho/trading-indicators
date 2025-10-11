defmodule TradingIndicators.Volatility.StandardDeviation do
  @moduledoc """
  Standard Deviation (StdDev) volatility indicator implementation.

  The Standard Deviation measures the amount of variation or dispersion of a set of values.
  A high standard deviation indicates that the values tend to be spread out over a wider
  range, while a low standard deviation indicates that they tend to be close to the mean.

  ## Formula

  Population Standard Deviation:
  σ = √(Σ(x - μ)² / N)

  Sample Standard Deviation:
  s = √(Σ(x - μ)² / (N-1))

  Where:
  - x = individual price values
  - μ = mean of the price values
  - N = number of periods

  ## Examples

      iex> data = [
      ...>   %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]},
      ...>   %{close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:33:00Z]},
      ...>   %{close: Decimal.new("101"), timestamp: ~U[2024-01-01 09:34:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Volatility.StandardDeviation.calculate(data, period: 4)
      iex> [first | _] = result
      iex> Decimal.round(first.value, 2)
      Decimal.new("1.71")

  ## Parameters

  - `:period` - Number of periods to use in calculation (required, must be >= 2)
  - `:source` - Source price field to use (default: `:close`)
  - `:calculation` - Use `:sample` or `:population` formula (default: `:sample`)

  ## Notes

  - Requires at least `period` number of data points
  - Returns results only when sufficient data is available
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates
  - Sample standard deviation (N-1) is typically preferred for financial data
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  require Decimal

  @default_period 20
  @default_calculation :sample

  @doc """
  Calculates Standard Deviation for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - Calculation options (keyword list)

  ## Options

  - `:period` - Number of periods (default: #{@default_period})
  - `:source` - Price source (default: `:close`)
  - `:calculation` - `:sample` or `:population` (default: #{@default_calculation})

  ## Returns

  - `{:ok, results}` - List of Standard Deviation calculations
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]
      {:ok, result} = StandardDeviation.calculate(data, period: 3)
  """
  @impl true
  @spec calculate(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         period <- Keyword.get(opts, :period, @default_period),
         source <- Keyword.get(opts, :source, :close),
         calculation <- Keyword.get(opts, :calculation, @default_calculation),
         :ok <- Utils.validate_data_length(data, period) do
      prices = extract_prices(data, source)
      calculate_stddev_values(prices, period, calculation, source, data)
    end
  end

  @doc """
  Validates parameters for Standard Deviation calculation.

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
    source = Keyword.get(opts, :source, :close)
    calculation = Keyword.get(opts, :calculation, @default_calculation)

    with :ok <- validate_period(period),
         :ok <- validate_source(source),
         :ok <- validate_calculation(calculation) do
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
  Returns the minimum number of periods required for Standard Deviation calculation.

  ## Returns

  - Default period if no options provided
  - Configured period from options

  ## Example

      iex> TradingIndicators.Volatility.StandardDeviation.required_periods()
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

      iex> TradingIndicators.Volatility.StandardDeviation.required_periods(period: 14)
      14
  """
  @spec required_periods(keyword()) :: pos_integer()
  def required_periods(opts) do
    Keyword.get(opts, :period, @default_period)
  end

  @doc """
  Initializes streaming state for real-time Standard Deviation calculation.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = StandardDeviation.init_state(period: 14)
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    source = Keyword.get(opts, :source, :close)
    calculation = Keyword.get(opts, :calculation, @default_calculation)

    %{
      period: period,
      source: source,
      calculation: calculation,
      prices: [],
      count: 0
    }
  end

  @doc """
  Updates streaming state with new data point.

  ## Parameters

  - `state` - Current streaming state
  - `data_point` - New OHLCV data point

  ## Returns

  - `{:ok, new_state, stddev_value}` - Updated state with result
  - `{:ok, new_state, nil}` - Updated state, insufficient data
  - `{:error, reason}` - Error occurred

  ## Example

      state = StandardDeviation.init_state(period: 3)
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = StandardDeviation.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv() | Decimal.t()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_state(
        %{period: period, source: source, calculation: calculation, prices: prices, count: count} =
          _state,
        data_point
      ) do
    try do
      price = extract_single_price(data_point, source)
      new_prices = update_price_buffer(prices, price, period)
      new_count = count + 1

      new_state = %{
        period: period,
        source: source,
        calculation: calculation,
        prices: new_prices,
        count: new_count
      }

      if new_count >= period do
        stddev_value = calculate_standard_deviation(new_prices, calculation)

        timestamp = get_timestamp(data_point)

        result = %{
          value: stddev_value,
          timestamp: timestamp,
          metadata: %{
            indicator: "STDDEV",
            period: period,
            source: source,
            calculation: calculation
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
       message: "Invalid state format for StandardDeviation streaming",
       operation: :update_state,
       reason: "malformed state"
     }}
  end

  # Private functions

  defp validate_period(period) when is_integer(period) and period >= 2, do: :ok

  defp validate_period(period) do
    {:error,
     %Errors.InvalidParams{
       message:
         "Period must be an integer >= 2 for standard deviation calculation, got: #{inspect(period)}",
       param: :period,
       value: period,
       expected: "integer >= 2"
     }}
  end

  defp validate_source(source) when source in [:open, :high, :low, :close], do: :ok

  defp validate_source(source) do
    {:error,
     %Errors.InvalidParams{
       message: "Invalid source: #{inspect(source)}",
       param: :source,
       value: source,
       expected: "one of [:open, :high, :low, :close]"
     }}
  end

  defp validate_calculation(calculation) when calculation in [:sample, :population], do: :ok

  defp validate_calculation(calculation) do
    {:error,
     %Errors.InvalidParams{
       message: "Invalid calculation type: #{inspect(calculation)}",
       param: :calculation,
       value: calculation,
       expected: "one of [:sample, :population]"
     }}
  end

  defp extract_prices(data, source) when is_list(data) and length(data) > 0 do
    # Check if data is already a price series (list of decimals)
    case List.first(data) do
      # Already a price series
      %Decimal{} -> data
      # OHLCV data
      %{} = _ohlcv -> extract_ohlcv_prices(data, source)
      # Assume it's some other price series format
      _ -> data
    end
  end

  defp extract_ohlcv_prices(data, :close), do: Utils.extract_closes(data)
  defp extract_ohlcv_prices(data, :open), do: Utils.extract_opens(data)
  defp extract_ohlcv_prices(data, :high), do: Utils.extract_highs(data)
  defp extract_ohlcv_prices(data, :low), do: Utils.extract_lows(data)

  defp extract_single_price(%Decimal{} = price, _source) do
    price
  end

  defp extract_single_price(price, _source) when is_number(price) do
    Decimal.new(price)
  end

  defp extract_single_price(%{} = data_point, source) do
    Map.fetch!(data_point, source)
  end

  defp get_timestamp(%{timestamp: timestamp}), do: timestamp
  defp get_timestamp(_), do: DateTime.utc_now()

  defp calculate_stddev_values(prices, period, calculation, source, original_data) do
    results =
      prices
      |> Utils.sliding_window(period)
      |> Enum.with_index(period - 1)
      |> Enum.map(fn {window, index} ->
        stddev_value = calculate_standard_deviation(window, calculation)

        timestamp = get_data_timestamp(original_data, index)

        %{
          value: stddev_value,
          timestamp: timestamp,
          metadata: %{
            indicator: "STDDEV",
            period: period,
            source: source,
            calculation: calculation
          }
        }
      end)

    {:ok, results}
  end

  defp get_data_timestamp(data, index) when is_list(data) do
    if index < length(data) do
      case Enum.at(data, index) do
        %{timestamp: timestamp} -> timestamp
        # For price series without timestamps
        _ -> DateTime.utc_now()
      end
    else
      DateTime.utc_now()
    end
  end

  defp update_price_buffer(prices, new_price, period) do
    updated_prices = prices ++ [new_price]

    if length(updated_prices) > period do
      # Take last N elements
      Enum.take(updated_prices, -period)
    else
      updated_prices
    end
  end

  defp calculate_standard_deviation(values, :sample) do
    # Utils already implements sample std dev
    Utils.standard_deviation(values)
  end

  defp calculate_standard_deviation(values, :population) do
    calculate_population_standard_deviation(values)
  end

  # Population standard deviation with N denominator
  defp calculate_population_standard_deviation(values) when length(values) < 2,
    do: Decimal.new("0.0")

  defp calculate_population_standard_deviation(values) when is_list(values) do
    mean_val = Utils.mean(values)

    sum_squared_diffs =
      values
      |> Enum.map(fn value ->
        diff = Decimal.sub(value, mean_val)
        Decimal.mult(diff, diff)
      end)
      |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

    variance = Decimal.div(sum_squared_diffs, Decimal.new(length(values)))

    # Convert to float for sqrt calculation, then back to Decimal
    variance_float = Decimal.to_float(variance)
    sqrt_result = :math.sqrt(variance_float)
    Decimal.from_float(sqrt_result)
  end
end
