defmodule TradingIndicators.Trend.MACD do
  @moduledoc """
  Moving Average Convergence Divergence (MACD) indicator implementation.

  MACD is a trend-following momentum indicator that shows the relationship 
  between two moving averages of a security's price. It consists of three components:

  1. **MACD Line**: Difference between the fast EMA and slow EMA
  2. **Signal Line**: EMA of the MACD line  
  3. **Histogram**: Difference between MACD line and Signal line

  ## Formula

  - MACD Line = EMA(fast_period) - EMA(slow_period)
  - Signal Line = EMA(MACD Line, signal_period)
  - Histogram = MACD Line - Signal Line

  ## Default Parameters

  - Fast Period: 12
  - Slow Period: 26  
  - Signal Period: 9

  ## Examples

      iex> data = [
      ...>   %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
      ...>   %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ...> ] ++ (for i <- 4..30 do
      ...>   %{close: Decimal.new(to_string(100 + i)), timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :minute)}
      ...> end)
      iex> {:ok, result} = TradingIndicators.Trend.MACD.calculate(data, fast_period: 5, slow_period: 10, signal_period: 3)
      iex> [first | _rest] = result
      iex> is_map(first.value)
      true
      iex> Map.has_key?(first.value, :macd)
      true

  ## Parameters

  - `:fast_period` - Fast EMA period (default: 12, must be < slow_period)
  - `:slow_period` - Slow EMA period (default: 26, must be > fast_period)  
  - `:signal_period` - Signal line EMA period (default: 9)
  - `:source` - Source price field to use (default: `:close`)

  ## Output Format

  Each result contains a value map with:
  - `:macd` - MACD line value
  - `:signal` - Signal line value  
  - `:histogram` - Histogram value

  ## Notes

  - Requires at least `slow_period` data points to start calculation
  - Signal line requires additional `signal_period` MACD values
  - Histogram is only available when both MACD and Signal are calculated
  - Uses precise Decimal arithmetic for accuracy
  - Supports streaming/real-time updates
  """

  @behaviour TradingIndicators.Behaviour

  alias TradingIndicators.{Types, Utils, Errors}
  alias TradingIndicators.Trend.EMA
  require Decimal

  @default_fast_period 12
  @default_slow_period 26
  @default_signal_period 9
  @precision 6

  @doc """
  Calculates MACD for the given data series.

  ## Parameters

  - `data` - List of OHLCV data points or price series
  - `opts` - Calculation options (keyword list)

  ## Options

  - `:fast_period` - Fast EMA period (default: #{@default_fast_period})
  - `:slow_period` - Slow EMA period (default: #{@default_slow_period})
  - `:signal_period` - Signal line period (default: #{@default_signal_period})
  - `:source` - Price source (default: `:close`)

  ## Returns

  - `{:ok, results}` - List of MACD calculations
  - `{:error, reason}` - Error if calculation fails

  ## Example

      data = [%{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}] ++ more_data
      {:ok, result} = MACD.calculate(data, fast_period: 8, slow_period: 21, signal_period: 5)
  """
  @impl true
  @spec calculate(Types.data_series() | [Decimal.t()], keyword()) ::
          {:ok, Types.result_series()} | {:error, term()}
  def calculate(data, opts \\ []) when is_list(data) do
    with :ok <- validate_params(opts),
         fast_period <- Keyword.get(opts, :fast_period, @default_fast_period),
         slow_period <- Keyword.get(opts, :slow_period, @default_slow_period),
         signal_period <- Keyword.get(opts, :signal_period, @default_signal_period),
         source <- Keyword.get(opts, :source, :close),
         :ok <- Utils.validate_data_length(data, slow_period) do
      calculate_macd_values(data, fast_period, slow_period, signal_period, source)
    end
  end

  @doc """
  Validates parameters for MACD calculation.

  ## Parameters

  - `opts` - Options keyword list

  ## Returns

  - `:ok` if parameters are valid
  - `{:error, exception}` if parameters are invalid
  """
  @impl true
  @spec validate_params(keyword()) :: :ok | {:error, Exception.t()}
  def validate_params(opts) when is_list(opts) do
    fast_period = Keyword.get(opts, :fast_period, @default_fast_period)
    slow_period = Keyword.get(opts, :slow_period, @default_slow_period)
    signal_period = Keyword.get(opts, :signal_period, @default_signal_period)
    source = Keyword.get(opts, :source, :close)

    with :ok <- validate_period(fast_period, :fast_period),
         :ok <- validate_period(slow_period, :slow_period),
         :ok <- validate_period(signal_period, :signal_period),
         :ok <- validate_period_relationship(fast_period, slow_period),
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
  Returns the minimum number of periods required for MACD calculation.

  ## Returns

  - Default slow period if no options provided
  - Configured slow period from options

  ## Example

      iex> TradingIndicators.Trend.MACD.required_periods()
      26
  """
  @impl true
  @spec required_periods() :: pos_integer()
  def required_periods, do: @default_slow_period

  @doc """
  Returns required periods for specific configuration.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Required number of periods (slow period)

  ## Example

      iex> TradingIndicators.Trend.MACD.required_periods(fast_period: 8, slow_period: 21)
      21
  """
  @spec required_periods(keyword()) :: pos_integer()
  def required_periods(opts) do
    Keyword.get(opts, :slow_period, @default_slow_period)
  end

  @doc """
  Initializes streaming state for real-time MACD calculation.

  ## Parameters

  - `opts` - Configuration options

  ## Returns

  - Initial state for streaming calculations

  ## Example

      state = MACD.init_state(fast_period: 8, slow_period: 21, signal_period: 5)
  """
  @impl true
  @spec init_state(keyword()) :: map()
  def init_state(opts \\ []) do
    fast_period = Keyword.get(opts, :fast_period, @default_fast_period)
    slow_period = Keyword.get(opts, :slow_period, @default_slow_period)
    signal_period = Keyword.get(opts, :signal_period, @default_signal_period)
    source = Keyword.get(opts, :source, :close)

    %{
      fast_period: fast_period,
      slow_period: slow_period,
      signal_period: signal_period,
      source: source,
      fast_ema_state: EMA.init_state(period: fast_period, source: source),
      slow_ema_state: EMA.init_state(period: slow_period, source: source),
      # Signal always uses MACD values
      signal_ema_state: EMA.init_state(period: signal_period, source: :close),
      macd_values: [],
      count: 0
    }
  end

  @doc """
  Updates streaming state with new data point.

  ## Parameters

  - `state` - Current streaming state
  - `data_point` - New OHLCV data point

  ## Returns

  - `{:ok, new_state, macd_result}` - Updated state with result
  - `{:ok, new_state, nil}` - Updated state, insufficient data
  - `{:error, reason}` - Error occurred

  ## Example

      state = MACD.init_state(fast_period: 5, slow_period: 10, signal_period: 3)
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, new_state, result} = MACD.update_state(state, data_point)
  """
  @impl true
  @spec update_state(map(), Types.ohlcv() | Decimal.t()) ::
          {:ok, map(), Types.indicator_result() | nil} | {:error, term()}
  def update_state(
        %{
          fast_period: fast_period,
          slow_period: slow_period,
          signal_period: signal_period,
          source: source,
          fast_ema_state: fast_ema_state,
          slow_ema_state: slow_ema_state,
          signal_ema_state: signal_ema_state,
          macd_values: macd_values,
          count: count
        } = _state,
        data_point
      ) do
    try do
      new_count = count + 1

      # Update both EMA states
      {:ok, new_fast_ema_state, fast_ema_result} = EMA.update_state(fast_ema_state, data_point)
      {:ok, new_slow_ema_state, slow_ema_result} = EMA.update_state(slow_ema_state, data_point)

      case {fast_ema_result, slow_ema_result} do
        {%{value: fast_value}, %{value: slow_value}} ->
          # Calculate MACD line
          macd_line = Decimal.sub(fast_value, slow_value)

          # Create synthetic data point for signal EMA (MACD line as "close" price)
          timestamp = get_timestamp(data_point)
          macd_data_point = %{close: macd_line, timestamp: timestamp}

          # Update signal EMA state with MACD value
          {:ok, new_signal_ema_state, signal_result} =
            EMA.update_state(signal_ema_state, macd_data_point)

          # Build result
          result_value = build_macd_result(macd_line, signal_result)

          result = %{
            value: result_value,
            timestamp: timestamp,
            metadata: %{
              indicator: "MACD",
              fast_period: fast_period,
              slow_period: slow_period,
              signal_period: signal_period,
              source: source
            }
          }

          new_state = %{
            fast_period: fast_period,
            slow_period: slow_period,
            signal_period: signal_period,
            source: source,
            fast_ema_state: new_fast_ema_state,
            slow_ema_state: new_slow_ema_state,
            signal_ema_state: new_signal_ema_state,
            macd_values: [macd_line | macd_values],
            count: new_count
          }

          {:ok, new_state, result}

        _ ->
          # Not enough data for MACD calculation yet
          new_state = %{
            fast_period: fast_period,
            slow_period: slow_period,
            signal_period: signal_period,
            source: source,
            fast_ema_state: new_fast_ema_state,
            slow_ema_state: new_slow_ema_state,
            # Unchanged since no MACD yet
            signal_ema_state: signal_ema_state,
            macd_values: macd_values,
            count: new_count
          }

          {:ok, new_state, nil}
      end
    rescue
      error -> {:error, error}
    end
  end

  def update_state(_state, _data_point) do
    {:error,
     %Errors.StreamStateError{
       message: "Invalid state format for MACD streaming",
       operation: :update_state,
       reason: "malformed state"
     }}
  end

  # Private functions

  defp validate_period(period, _name) when is_integer(period) and period >= 1, do: :ok

  defp validate_period(period, name) do
    {:error,
     %Errors.InvalidParams{
       message:
         "#{String.capitalize(to_string(name))} must be a positive integer, got #{inspect(period)}",
       param: name,
       value: period,
       expected: "positive integer"
     }}
  end

  defp validate_period_relationship(fast_period, slow_period) do
    if fast_period < slow_period do
      :ok
    else
      {:error,
       %Errors.InvalidParams{
         message: "Fast period (#{fast_period}) must be less than slow period (#{slow_period})",
         param: :period_relationship,
         value: {fast_period, slow_period},
         expected: "fast_period < slow_period"
       }}
    end
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

  defp calculate_macd_values(data, fast_period, slow_period, signal_period, source) do
    # Calculate fast and slow EMAs
    with {:ok, fast_ema_results} <- EMA.calculate(data, period: fast_period, source: source),
         {:ok, slow_ema_results} <- EMA.calculate(data, period: slow_period, source: source) do
      # Align EMAs - we need both to exist for the same timestamp
      aligned_emas = align_ema_results(fast_ema_results, slow_ema_results)

      # Calculate MACD line for each aligned pair
      macd_lines = calculate_macd_lines(aligned_emas)

      # Calculate signal line from MACD values
      signal_results = calculate_signal_line(macd_lines, signal_period)

      # Combine MACD and signal to create final results
      combine_macd_signal_results(
        macd_lines,
        signal_results,
        fast_period,
        slow_period,
        signal_period,
        source
      )
    end
  end

  defp align_ema_results(fast_results, slow_results) do
    # Create map for fast lookup by timestamp
    fast_map = Map.new(fast_results, fn result -> {result.timestamp, result.value} end)

    # Find matching timestamps in slow results
    slow_results
    |> Enum.filter(fn slow_result ->
      Map.has_key?(fast_map, slow_result.timestamp)
    end)
    |> Enum.map(fn slow_result ->
      fast_value = Map.get(fast_map, slow_result.timestamp)
      {fast_value, slow_result.value, slow_result.timestamp}
    end)
  end

  defp calculate_macd_lines(aligned_emas) do
    Enum.map(aligned_emas, fn {fast_value, slow_value, timestamp} ->
      macd_value = Decimal.sub(fast_value, slow_value) |> Decimal.round(@precision)
      %{value: macd_value, timestamp: timestamp}
    end)
  end

  defp calculate_signal_line(macd_lines, signal_period) do
    # Convert MACD lines to format suitable for EMA calculation
    macd_data =
      Enum.map(macd_lines, fn macd ->
        %{close: macd.value, timestamp: macd.timestamp}
      end)

    case EMA.calculate(macd_data, period: signal_period, source: :close) do
      {:ok, signal_results} -> signal_results
      # Not enough data for signal line yet
      {:error, _} -> []
    end
  end

  defp combine_macd_signal_results(
         macd_lines,
         signal_results,
         fast_period,
         slow_period,
         signal_period,
         source
       ) do
    # Create signal lookup map
    signal_map = Map.new(signal_results, fn result -> {result.timestamp, result.value} end)

    # Combine MACD with available signal values
    results =
      Enum.map(macd_lines, fn macd ->
        macd_value = macd.value
        signal_value = Map.get(signal_map, macd.timestamp)

        histogram_value =
          if signal_value do
            Decimal.sub(macd_value, signal_value) |> Decimal.round(@precision)
          else
            nil
          end

        result_value = %{
          macd: macd_value,
          signal: signal_value,
          histogram: histogram_value
        }

        %{
          value: result_value,
          timestamp: macd.timestamp,
          metadata: %{
            indicator: "MACD",
            fast_period: fast_period,
            slow_period: slow_period,
            signal_period: signal_period,
            source: source
          }
        }
      end)

    {:ok, results}
  end

  defp build_macd_result(macd_line, signal_result) do
    signal_value = if signal_result, do: signal_result.value, else: nil

    histogram_value =
      if signal_value do
        Decimal.sub(macd_line, signal_value) |> Decimal.round(@precision)
      else
        nil
      end

    %{
      macd: Decimal.round(macd_line, @precision),
      signal: signal_value,
      histogram: histogram_value
    }
  end

  defp get_timestamp(%{timestamp: timestamp}), do: timestamp
  defp get_timestamp(_), do: DateTime.utc_now()
end
