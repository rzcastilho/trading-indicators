defmodule TradingIndicators.Volatility.VolatilityIndex do
  @moduledoc """
  Volatility Index indicator implementation with multiple estimation methods.

  This module provides various volatility estimation methods commonly used in 
  quantitative finance and options trading. Each method captures different 
  aspects of price volatility.

  ## Estimation Methods

  1. **Historical Volatility**: Standard deviation of log returns annualized
  2. **Garman-Klass**: Uses OHLC data to estimate intraday volatility
  3. **Parkinson**: High-low range estimator

  ## Formulas

  **Historical Volatility:**
  HV = StdDev(ln(Close[t] / Close[t-1])) × √(periods_per_year)

  **Garman-Klass:**
  GK = ln(H/L) × ln(H/L) - (2×ln(2)-1) × ln(C/O) × ln(C/O)

  **Parkinson:**
  P = (1/(4×ln(2))) × ln(H/L)²

  ## Examples

      iex> data = [
      ...>   %{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{open: Decimal.new("103"), high: Decimal.new("107"), low: Decimal.new("101"), close: Decimal.new("106"), timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{open: Decimal.new("106"), high: Decimal.new("109"), low: Decimal.new("104"), close: Decimal.new("108"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ...> ]
      iex> {:ok, result} = TradingIndicators.Volatility.VolatilityIndex.calculate(data, period: 2, method: :historical)
      iex> [first | _] = result
      iex> Decimal.positive?(first.value)
      true

  ## Parameters

  - `:period` - Number of periods for calculation (required, must be >= 2)
  - `:method` - Estimation method (`:historical`, `:garman_klass`, `:parkinson`) (default: `:historical`)
  - `:periods_per_year` - Number of periods per year for annualization (default: 252 for daily data)
  - `:source` - Source price for historical volatility (default: `:close`)

  ## Notes

  - Requires at least `period` number of data points
  - Garman-Klass and Parkinson methods require OHLC data
  - Historical volatility can use any price source
  - Results are typically expressed as annualized percentages
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  require Decimal

  @default_period 20
  @default_method :historical
  # Trading days in a year
  @default_periods_per_year 252
  @precision 6

  # Mathematical constant: 2 * ln(2) - 1 ≈ 0.3862943611
  @two_ln2_minus_1 Decimal.from_float(2 * :math.log(2) - 1)
  # Mathematical constant: 1 / (4 * ln(2)) ≈ 0.3606737947
  @one_over_4ln2 Decimal.div(
                   Decimal.new("1"),
                   Decimal.mult(Decimal.new("4"), Decimal.from_float(:math.log(2)))
                 )

  @doc """
  Calculates Volatility Index for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - Calculation options (keyword list)

  ## Options

  - `:period` - Number of periods (default: #{@default_period})
  - `:method` - Estimation method (default: #{@default_method})
  - `:periods_per_year` - Annualization factor (default: #{@default_periods_per_year})
  - `:source` - Price source for historical method (default: `:close`)

  ## Returns

  - `{:ok, results}` - List of Volatility Index calculations
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [
        %{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{open: Decimal.new("103"), high: Decimal.new("107"), low: Decimal.new("101"), close: Decimal.new("106"), timestamp: ~U[2024-01-01 09:31:00Z]}
      ]
      {:ok, result} = VolatilityIndex.calculate(data, period: 20, method: :garman_klass)
  """
  @impl true
  @spec calculate(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         period <- Keyword.get(opts, :period, @default_period),
         method <- Keyword.get(opts, :method, @default_method),
         periods_per_year <- Keyword.get(opts, :periods_per_year, @default_periods_per_year),
         source <- Keyword.get(opts, :source, :close),
         :ok <- validate_data_length_for_method(data, period, method),
         :ok <- validate_data_for_method(data, method) do
      calculate_volatility_values(data, period, method, periods_per_year, source)
    end
  end

  @doc """
  Validates parameters for Volatility Index calculation.

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
    method = Keyword.get(opts, :method, @default_method)
    periods_per_year = Keyword.get(opts, :periods_per_year, @default_periods_per_year)
    source = Keyword.get(opts, :source, :close)

    with :ok <- validate_period(period),
         :ok <- validate_method(method),
         :ok <- validate_periods_per_year(periods_per_year),
         :ok <- validate_source(source) do
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
  Returns the minimum number of periods required for Volatility Index calculation.

  ## Returns

  - Default period + 1 (need extra period for returns calculation)

  ## Example

      iex> TradingIndicators.Volatility.VolatilityIndex.required_periods()
      21
  """
  @impl true
  @spec required_periods() :: pos_integer()
  def required_periods, do: @default_period + 1

  @doc """
  Returns required periods for specific configuration.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Required number of periods + 1

  ## Example

      iex> TradingIndicators.Volatility.VolatilityIndex.required_periods(period: 14)
      15
  """
  @spec required_periods(keyword()) :: pos_integer()
  def required_periods(opts) do
    period = Keyword.get(opts, :period, @default_period)
    period + 1
  end

  @doc """
  Initializes streaming state for real-time Volatility Index calculation.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = VolatilityIndex.init_state(period: 20, method: :historical)
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    method = Keyword.get(opts, :method, @default_method)
    periods_per_year = Keyword.get(opts, :periods_per_year, @default_periods_per_year)
    source = Keyword.get(opts, :source, :close)

    %{
      period: period,
      method: method,
      periods_per_year: periods_per_year,
      source: source,
      data_points: [],
      count: 0
    }
  end

  @doc """
  Updates streaming state with new data point.

  ## Parameters

  - `state` - Current streaming state
  - `data_point` - New OHLCV data point

  ## Returns

  - `{:ok, new_state, volatility_result}` - Updated state with result
  - `{:ok, new_state, nil}` - Updated state, insufficient data
  - `{:error, reason}` - Error occurred

  ## Example

      state = VolatilityIndex.init_state(period: 3, method: :historical)
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = VolatilityIndex.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv() | Decimal.t()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_state(
        %{
          period: period,
          method: method,
          periods_per_year: periods_per_year,
          source: source,
          data_points: data_points,
          count: count
        } = _state,
        data_point
      ) do
    try do
      new_data_points = update_data_buffer(data_points, data_point, period + 1)
      new_count = count + 1

      new_state = %{
        period: period,
        method: method,
        periods_per_year: periods_per_year,
        source: source,
        data_points: new_data_points,
        count: new_count
      }

      if new_count >= period + 1 do
        volatility_value =
          calculate_single_volatility(new_data_points, method, periods_per_year, source)

        timestamp = get_timestamp(data_point)

        result = %{
          value: Decimal.round(volatility_value, @precision),
          timestamp: timestamp,
          metadata: %{
            indicator: "VOLATILITY",
            period: period,
            method: method,
            periods_per_year: periods_per_year,
            source: source
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
       message: "Invalid state format for VolatilityIndex streaming",
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
         "Period must be an integer >= 2 for volatility calculation, got: #{inspect(period)}",
       param: :period,
       value: period,
       expected: "integer >= 2"
     }}
  end

  defp validate_method(method) when method in [:historical, :garman_klass, :parkinson], do: :ok

  defp validate_method(method) do
    {:error,
     %Errors.InvalidParams{
       message: "Invalid volatility method: #{inspect(method)}",
       param: :method,
       value: method,
       expected: "one of [:historical, :garman_klass, :parkinson]"
     }}
  end

  defp validate_periods_per_year(periods) when is_integer(periods) and periods > 0, do: :ok

  defp validate_periods_per_year(periods) do
    {:error,
     %Errors.InvalidParams{
       message: "Periods per year must be a positive integer, got: #{inspect(periods)}",
       param: :periods_per_year,
       value: periods,
       expected: "positive integer"
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

  defp validate_data_length_for_method(data, period, :historical) do
    # Need one extra for returns calculation
    Utils.validate_data_length(data, period + 1)
  end

  defp validate_data_length_for_method(data, period, _method) do
    # Garman-Klass and Parkinson don't need extra data
    Utils.validate_data_length(data, period)
  end

  defp validate_data_for_method([], _method), do: :ok
  # Historical can use any data
  defp validate_data_for_method(_data, :historical), do: :ok

  defp validate_data_for_method([%{open: _, high: _, low: _, close: _} | rest], method)
       when method in [:garman_klass, :parkinson] do
    validate_data_for_method(rest, method)
  end

  defp validate_data_for_method([%Decimal{} | _rest], method)
       when method in [:garman_klass, :parkinson] do
    {:error,
     %Errors.InvalidDataFormat{
       message: "#{method} method requires OHLC data, but got price series",
       expected: "OHLC data with :open, :high, :low, :close keys",
       received: "price series"
     }}
  end

  defp validate_data_for_method([invalid | _rest], method)
       when method in [:garman_klass, :parkinson] do
    {:error,
     %Errors.InvalidDataFormat{
       message: "#{method} method requires OHLC data with open, high, low, and close fields",
       expected: "map with :open, :high, :low, :close keys",
       received: inspect(invalid)
     }}
  end

  defp get_timestamp(%{timestamp: timestamp}), do: timestamp
  defp get_timestamp(_), do: DateTime.utc_now()

  defp calculate_volatility_values(data, period, method, periods_per_year, source) do
    case method do
      :historical -> calculate_historical_volatility(data, period, periods_per_year, source)
      :garman_klass -> calculate_garman_klass_volatility(data, period, periods_per_year)
      :parkinson -> calculate_parkinson_volatility(data, period, periods_per_year)
    end
  end

  defp calculate_historical_volatility(data, period, periods_per_year, source) do
    prices = extract_prices(data, source)
    log_returns = calculate_log_returns(prices)

    results =
      log_returns
      |> Utils.sliding_window(period)
      # Match indexing with other methods
      |> Enum.with_index(period - 1)
      |> Enum.map(fn {returns_window, index} ->
        volatility = calculate_historical_vol_from_returns(returns_window, periods_per_year)
        timestamp = get_data_timestamp(data, index)

        %{
          value: Decimal.round(volatility, @precision),
          timestamp: timestamp,
          metadata: %{
            indicator: "VOLATILITY",
            period: period,
            method: :historical,
            periods_per_year: periods_per_year,
            source: source
          }
        }
      end)

    {:ok, results}
  end

  defp calculate_garman_klass_volatility(data, period, periods_per_year) do
    gk_values = calculate_garman_klass_values(data)

    results =
      gk_values
      |> Utils.sliding_window(period)
      |> Enum.with_index(period - 1)
      |> Enum.map(fn {gk_window, index} ->
        volatility = calculate_annualized_volatility(gk_window, periods_per_year)
        timestamp = get_data_timestamp(data, index)

        %{
          value: Decimal.round(volatility, @precision),
          timestamp: timestamp,
          metadata: %{
            indicator: "VOLATILITY",
            period: period,
            method: :garman_klass,
            periods_per_year: periods_per_year
          }
        }
      end)

    {:ok, results}
  end

  defp calculate_parkinson_volatility(data, period, periods_per_year) do
    parkinson_values = calculate_parkinson_values(data)

    results =
      parkinson_values
      |> Utils.sliding_window(period)
      |> Enum.with_index(period - 1)
      |> Enum.map(fn {parkinson_window, index} ->
        volatility = calculate_annualized_volatility(parkinson_window, periods_per_year)
        timestamp = get_data_timestamp(data, index)

        %{
          value: Decimal.round(volatility, @precision),
          timestamp: timestamp,
          metadata: %{
            indicator: "VOLATILITY",
            period: period,
            method: :parkinson,
            periods_per_year: periods_per_year
          }
        }
      end)

    {:ok, results}
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

  defp calculate_log_returns([]), do: []
  defp calculate_log_returns([_single]), do: []

  defp calculate_log_returns(prices) do
    prices
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [prev_price, curr_price] ->
      ratio = Decimal.div(curr_price, prev_price)
      ratio_float = Decimal.to_float(ratio)
      log_return = :math.log(ratio_float)
      Decimal.from_float(log_return)
    end)
  end

  defp calculate_historical_vol_from_returns(returns, _periods_per_year) when length(returns) < 2 do
    Decimal.new("0.0")
  end

  defp calculate_historical_vol_from_returns(returns, periods_per_year) do
    std_dev = Utils.standard_deviation(returns)
    annualization_factor = :math.sqrt(periods_per_year)
    annualized = Decimal.mult(std_dev, Decimal.from_float(annualization_factor))
    # Convert to percentage
    Decimal.mult(annualized, Decimal.new("100"))
  end

  defp calculate_garman_klass_values(data) do
    Enum.map(data, fn %{open: o, high: h, low: l, close: c} ->
      # ln(H/L) * ln(H/L)
      hl_ratio = Decimal.div(h, l)
      hl_log = Decimal.from_float(:math.log(Decimal.to_float(hl_ratio)))
      hl_term = Decimal.mult(hl_log, hl_log)

      # ln(C/O) * ln(C/O)
      co_ratio = Decimal.div(c, o)
      co_log = Decimal.from_float(:math.log(Decimal.to_float(co_ratio)))
      co_term = Decimal.mult(co_log, co_log)

      # GK = ln(H/L)² - (2*ln(2)-1) * ln(C/O)²
      weighted_co_term = Decimal.mult(@two_ln2_minus_1, co_term)
      Decimal.sub(hl_term, weighted_co_term)
    end)
  end

  defp calculate_parkinson_values(data) do
    Enum.map(data, fn %{high: h, low: l} ->
      # P = (1/(4*ln(2))) * ln(H/L)²
      hl_ratio = Decimal.div(h, l)
      hl_log = Decimal.from_float(:math.log(Decimal.to_float(hl_ratio)))
      hl_squared = Decimal.mult(hl_log, hl_log)
      Decimal.mult(@one_over_4ln2, hl_squared)
    end)
  end

  defp calculate_annualized_volatility(values, _periods_per_year) when length(values) < 2 do
    Decimal.new("0.0")
  end

  defp calculate_annualized_volatility(values, periods_per_year) do
    mean_variance = Utils.mean(values)
    annualization_factor = Decimal.new(periods_per_year)
    annualized_variance = Decimal.mult(mean_variance, annualization_factor)

    # Take square root to get volatility
    variance_float = Decimal.to_float(annualized_variance)
    volatility_float = :math.sqrt(variance_float)
    volatility = Decimal.from_float(volatility_float)

    # Convert to percentage
    Decimal.mult(volatility, Decimal.new("100"))
  end

  defp calculate_single_volatility(data_points, method, periods_per_year, source) do
    case method do
      :historical ->
        prices = extract_prices(data_points, source)
        returns = calculate_log_returns(prices)
        latest_returns = Enum.take(returns, -@default_period)
        calculate_historical_vol_from_returns(latest_returns, periods_per_year)

      :garman_klass ->
        gk_values = calculate_garman_klass_values(data_points)
        latest_gk = Enum.take(gk_values, -@default_period)
        calculate_annualized_volatility(latest_gk, periods_per_year)

      :parkinson ->
        parkinson_values = calculate_parkinson_values(data_points)
        latest_parkinson = Enum.take(parkinson_values, -@default_period)
        calculate_annualized_volatility(latest_parkinson, periods_per_year)
    end
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

  defp update_data_buffer(data_points, new_point, max_size) do
    updated_points = data_points ++ [new_point]

    if length(updated_points) > max_size do
      # Take last N elements
      Enum.take(updated_points, -max_size)
    else
      updated_points
    end
  end
end
