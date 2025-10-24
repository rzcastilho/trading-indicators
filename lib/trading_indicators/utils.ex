defmodule TradingIndicators.Utils do
  require Decimal

  @moduledoc """
  Common utility functions used throughout the TradingIndicators library.

  This module provides helper functions for data extraction, mathematical calculations,
  and data validation that are shared across multiple indicator implementations.

  ## Price Extraction Functions

  - `extract_closes/1` - Extract closing prices from OHLCV data
  - `extract_highs/1` - Extract high prices from OHLCV data
  - `extract_lows/1` - Extract low prices from OHLCV data
  - `extract_opens/1` - Extract opening prices from OHLCV data
  - `extract_volumes/1` - Extract volume data from OHLCV data
  - `extract_volumes_as_decimal/1` - Extract volume data as Decimal values
  - `extract_volume_as_decimal/1` - Extract single volume value as Decimal

  ## Mathematical Functions

  - `mean/1` - Calculate arithmetic mean
  - `standard_deviation/1` - Calculate standard deviation
  - `variance/1` - Calculate variance
  - `percentage_change/2` - Calculate percentage change between values

  ## Data Processing Functions

  - `sliding_window/2` - Create sliding windows from data series
  - `validate_data_length/2` - Validate minimum data requirements
  - `typical_price/1` - Calculate typical price (H+L+C)/3
  - `true_range/2` - Calculate true range value

  ## Volume Analysis Functions

  - `validate_volumes/1` - Validate volume data in series
  - `has_volume?/1` - Check if series has non-zero volume periods
  - `filter_zero_volume/1` - Remove data points with zero volume
  - `volume_weighted_price/2` - Calculate volume-weighted price by variant
  """

  alias TradingIndicators.Errors
  alias TradingIndicators.Types

  @doc """
  Extracts closing prices from OHLCV data series.

  ## Parameters

  - `data` - List of OHLCV data points

  ## Returns

  - List of closing prices

  ## Example

      iex> data = [
      ...>   %{open: Decimal.new("100.0"), high: Decimal.new("105.0"), low: Decimal.new("99.0"), close: Decimal.new("103.0"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
      ...>   %{open: Decimal.new("103.0"), high: Decimal.new("107.0"), low: Decimal.new("102.0"), close: Decimal.new("106.0"), volume: 1200, timestamp: ~U[2024-01-01 09:31:00Z]}
      ...> ]
      iex> TradingIndicators.Utils.extract_closes(data)
      [Decimal.new("103.0"), Decimal.new("106.0")]
  """
  @spec extract_closes(Types.data_series()) :: Types.close_series()
  def extract_closes(data) when is_list(data) do
    Enum.map(data, & &1.close)
  end

  @doc """
  Extracts high prices from OHLCV data series.

  ## Parameters

  - `data` - List of OHLCV data points

  ## Returns

  - List of high prices
  """
  @spec extract_highs(Types.data_series()) :: Types.high_series()
  def extract_highs(data) when is_list(data) do
    Enum.map(data, & &1.high)
  end

  @doc """
  Extracts low prices from OHLCV data series.

  ## Parameters

  - `data` - List of OHLCV data points

  ## Returns

  - List of low prices
  """
  @spec extract_lows(Types.data_series()) :: Types.low_series()
  def extract_lows(data) when is_list(data) do
    Enum.map(data, & &1.low)
  end

  @doc """
  Extracts opening prices from OHLCV data series.

  ## Parameters

  - `data` - List of OHLCV data points

  ## Returns

  - List of opening prices
  """
  @spec extract_opens(Types.data_series()) :: Types.open_series()
  def extract_opens(data) when is_list(data) do
    Enum.map(data, & &1.open)
  end

  @doc """
  Extracts volume data from OHLCV data series.

  ## Parameters

  - `data` - List of OHLCV data points

  ## Returns

  - List of volume values
  """
  @spec extract_volumes(Types.data_series()) :: Types.volume_series()
  def extract_volumes(data) when is_list(data) do
    Enum.map(data, & &1.volume)
  end

  @doc """
  Extracts volume data from OHLCV data series as Decimal values.

  This is useful for trend indicators that need to calculate moving averages
  or other statistics on volume using Decimal precision.

  ## Parameters

  - `data` - List of OHLCV data points

  ## Returns

  - List of volume values as Decimal

  ## Example

      iex> data = [
      ...>   %{volume: 1000, close: Decimal.new("100.0")},
      ...>   %{volume: 1200, close: Decimal.new("101.0")}
      ...> ]
      iex> TradingIndicators.Utils.extract_volumes_as_decimal(data)
      [Decimal.new("1000"), Decimal.new("1200")]
  """
  @spec extract_volumes_as_decimal(Types.data_series()) :: [Decimal.t()]
  def extract_volumes_as_decimal(data) when is_list(data) do
    Enum.map(data, fn point -> Decimal.new(point.volume) end)
  end

  @doc """
  Extracts a single volume value from a data point as Decimal.

  ## Parameters

  - `data_point` - Single OHLCV data point

  ## Returns

  - Volume value as Decimal

  ## Example

      iex> data_point = %{volume: 1000, close: Decimal.new("100.0")}
      iex> TradingIndicators.Utils.extract_volume_as_decimal(data_point)
      Decimal.new("1000")
  """
  @spec extract_volume_as_decimal(Types.ohlcv()) :: Decimal.t()
  def extract_volume_as_decimal(%{volume: volume}) do
    Decimal.new(volume)
  end

  @doc """
  Calculates the arithmetic mean of a list of numbers.

  ## Parameters

  - `values` - List of numerical values

  ## Returns

  - The arithmetic mean as a float
  - Returns 0.0 for empty list

  ## Example

      iex> TradingIndicators.Utils.mean([Decimal.new("1"), Decimal.new("2"), Decimal.new("3"), Decimal.new("4"), Decimal.new("5")])
      Decimal.new("3")

      iex> TradingIndicators.Utils.mean([])
      Decimal.new("0.0")
  """
  @spec mean([Decimal.t()]) :: Decimal.t()
  def mean([]), do: Decimal.new("0.0")

  def mean(values) when is_list(values) do
    sum = Enum.reduce(values, Decimal.new("0"), &Decimal.add/2)
    Decimal.div(sum, Decimal.new(length(values)))
  end

  @doc """
  Calculates the standard deviation of a list of numbers.

  Uses the sample standard deviation formula (N-1 denominator).

  ## Parameters

  - `values` - List of numerical values

  ## Returns

  - The standard deviation as a float
  - Returns 0.0 for lists with less than 2 elements

  ## Example

      iex> result = TradingIndicators.Utils.standard_deviation([Decimal.new("1"), Decimal.new("2"), Decimal.new("3"), Decimal.new("4"), Decimal.new("5")])
      iex> Decimal.round(result, 6)
      Decimal.new("1.581139")
  """
  @spec standard_deviation([Decimal.t()]) :: Decimal.t()
  def standard_deviation(values) when length(values) < 2, do: Decimal.new("0.0")

  def standard_deviation(values) when is_list(values) do
    mean_val = mean(values)
    variance_val = variance(values, mean_val)

    # Convert to float for sqrt calculation, then back to Decimal
    variance_float = Decimal.to_float(variance_val)
    sqrt_result = :math.sqrt(variance_float)
    Decimal.from_float(sqrt_result)
  end

  @doc """
  Calculates the variance of a list of numbers.

  Uses the sample variance formula (N-1 denominator).

  ## Parameters

  - `values` - List of numerical values
  - `mean_val` - (Optional) Pre-calculated mean to avoid recalculation

  ## Returns

  - The variance as a float
  """
  @spec variance([Decimal.t()], Decimal.t() | nil) :: Decimal.t()
  def variance(values, mean_val \\ nil)
  def variance(values, nil) when is_list(values), do: variance(values, mean(values))
  def variance(values, _mean_val) when length(values) < 2, do: Decimal.new("0.0")

  def variance(values, mean_val) when is_list(values) do
    sum_squared_diffs =
      values
      |> Enum.map(fn value ->
        diff = Decimal.sub(value, mean_val)
        Decimal.mult(diff, diff)
      end)
      |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

    Decimal.div(sum_squared_diffs, Decimal.new(length(values) - 1))
  end

  @doc """
  Calculates the percentage change between two values.

  ## Parameters

  - `old_value` - The original value
  - `new_value` - The new value

  ## Returns

  - The percentage change as a float
  - Returns 0.0 if old_value is 0

  ## Example

      iex> TradingIndicators.Utils.percentage_change(Decimal.new("100"), Decimal.new("110"))
      Decimal.new("10.00")

      iex> TradingIndicators.Utils.percentage_change(Decimal.new("100"), Decimal.new("90"))
      Decimal.new("-10.00")
  """
  @spec percentage_change(Decimal.t(), Decimal.t()) :: Decimal.t()
  def percentage_change(%Decimal{} = old_value, new_value) do
    case Decimal.equal?(old_value, Decimal.new("0")) do
      true -> Decimal.new("0.0")
      false -> percentage_change_calc(old_value, new_value)
    end
  end

  defp percentage_change_calc(old_value, new_value) do
    diff = Decimal.sub(new_value, old_value)
    ratio = Decimal.div(diff, old_value)
    Decimal.mult(ratio, Decimal.new("100.0"))
  end

  @doc """
  Creates sliding windows of specified size from a data series.

  ## Parameters

  - `data` - List of data points
  - `window_size` - Size of each window

  ## Returns

  - List of windows, each containing `window_size` elements

  ## Example

      iex> TradingIndicators.Utils.sliding_window([1, 2, 3, 4, 5], 3)
      [[1, 2, 3], [2, 3, 4], [3, 4, 5]]
  """
  @spec sliding_window([term()], pos_integer()) :: [[term()]]
  def sliding_window(data, window_size) when length(data) < window_size, do: []

  def sliding_window(data, window_size) when is_list(data) and window_size > 0 do
    data
    |> Enum.with_index()
    |> Enum.reduce([], fn {_value, index}, acc ->
      if index + window_size <= length(data) do
        window = Enum.slice(data, index, window_size)
        [window | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Validates that data series has sufficient length for calculation.

  ## Parameters

  - `data` - Data series to validate
  - `required_length` - Minimum required length

  ## Returns

  - `:ok` if data is sufficient
  - `{:error, exception}` if data is insufficient

  ## Example

      iex> TradingIndicators.Utils.validate_data_length([1, 2, 3], 2)
      :ok

      iex> TradingIndicators.Utils.validate_data_length([1], 2)
      {:error, %TradingIndicators.Errors.InsufficientData{message: "Insufficient data: required 2, got 1", required: 2, provided: 1}}
  """
  @spec validate_data_length([term()], non_neg_integer()) :: :ok | {:error, Exception.t()}
  def validate_data_length(data, required_length) when is_list(data) do
    actual_length = length(data)

    if actual_length >= required_length do
      :ok
    else
      {:error,
       %Errors.InsufficientData{
         message: "Insufficient data: required #{required_length}, got #{actual_length}",
         required: required_length,
         provided: actual_length
       }}
    end
  end

  @doc """
  Calculates the typical price for OHLCV data points.

  Typical price = (High + Low + Close) / 3

  ## Parameters

  - `data` - OHLCV data point or list of OHLCV data points

  ## Returns

  - Typical price value or list of typical price values

  ## Example

      iex> data = %{open: Decimal.new("100.0"), high: Decimal.new("105.0"), low: Decimal.new("99.0"), close: Decimal.new("103.0"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}
      iex> result = TradingIndicators.Utils.typical_price(data)
      iex> Decimal.round(result, 6)
      Decimal.new("102.333333")
  """
  @spec typical_price(Types.ohlcv() | Types.data_series()) :: Decimal.t() | [Decimal.t()]
  def typical_price(%{high: high, low: low, close: close}) do
    sum = high |> Decimal.add(low) |> Decimal.add(close)
    Decimal.div(sum, Decimal.new("3.0"))
  end

  def typical_price(data) when is_list(data) do
    Enum.map(data, &typical_price/1)
  end

  @doc """
  Calculates the True Range for two consecutive OHLCV data points.

  True Range is the maximum of:
  - Current High - Current Low
  - |Current High - Previous Close|
  - |Current Low - Previous Close|

  ## Parameters

  - `current` - Current period OHLCV data
  - `previous` - Previous period OHLCV data (optional)

  ## Returns

  - True Range value as float

  ## Example

      iex> current = %{high: Decimal.new("105.0"), low: Decimal.new("99.0"), close: Decimal.new("103.0")}
      iex> previous = %{close: Decimal.new("101.0")}
      iex> TradingIndicators.Utils.true_range(current, previous)
      Decimal.new("6.0")
  """
  @spec true_range(Types.ohlcv(), Types.ohlcv() | nil) :: Decimal.t()
  def true_range(%{high: high, low: low} = _current, nil) do
    Decimal.sub(high, low)
  end

  def true_range(%{high: high, low: low} = _current, %{close: prev_close} = _previous) do
    hl_diff = Decimal.sub(high, low)
    hc_diff = Decimal.abs(Decimal.sub(high, prev_close))
    lc_diff = Decimal.abs(Decimal.sub(low, prev_close))

    Decimal.max(hl_diff, Decimal.max(hc_diff, lc_diff))
  end

  @doc """
  Calculates True Range for a series of OHLCV data points.

  ## Parameters

  - `data` - List of OHLCV data points (at least 1 element)

  ## Returns

  - List of True Range values

  ## Example

      iex> data = [
      ...>   %{high: Decimal.new("105.0"), low: Decimal.new("99.0"), close: Decimal.new("103.0")},
      ...>   %{high: Decimal.new("107.0"), low: Decimal.new("102.0"), close: Decimal.new("106.0")}
      ...> ]
      iex> TradingIndicators.Utils.true_range_series(data)
      [Decimal.new("6.0"), Decimal.new("5.0")]
  """
  @spec true_range_series(Types.data_series()) :: [Decimal.t()]
  def true_range_series([]), do: []

  def true_range_series([first | rest]) do
    first_tr = true_range(first, nil)

    rest_trs =
      [first | rest]
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [prev, curr] -> true_range(curr, prev) end)

    [first_tr | rest_trs]
  end

  @doc """
  Rounds a number to specified decimal places.

  ## Parameters

  - `number` - Number to round
  - `precision` - Number of decimal places (default: 2)

  ## Returns

  - Rounded number as float

  ## Example

      iex> TradingIndicators.Utils.round_to(Decimal.new("3.14159"), 2)
      Decimal.new("3.14")

      iex> TradingIndicators.Utils.round_to(Decimal.new("3.14159"), 4)
      Decimal.new("3.1416")
  """
  @spec round_to(Decimal.t(), non_neg_integer()) :: Decimal.t()
  def round_to(%Decimal{} = number, precision \\ 2) do
    Decimal.round(number, precision)
  end

  @doc """
  Checks if a list contains only numerical values.

  ## Parameters

  - `values` - List to check

  ## Returns

  - `true` if all values are numbers
  - `false` otherwise

  ## Example

      iex> TradingIndicators.Utils.all_decimals?([Decimal.new("1"), Decimal.new("2.5"), Decimal.new("3")])
      true

      iex> TradingIndicators.Utils.all_decimals?([Decimal.new("1"), "2", Decimal.new("3")])
      false
  """
  @spec all_decimals?([term()]) :: boolean()
  def all_decimals?(values) when is_list(values) do
    Enum.all?(values, &Decimal.is_decimal/1)
  end

  # Legacy function for backward compatibility
  @spec all_numbers?([term()]) :: boolean()
  def all_numbers?(values) when is_list(values) do
    all_decimals?(values)
  end

  @doc """
  Fills missing values in a data series using forward fill method.

  ## Parameters

  - `data` - List of values that may contain nil
  - `default_value` - Default value to use if first element is nil (default: 0)

  ## Returns

  - List with nil values replaced by previous non-nil value

  ## Example

      iex> TradingIndicators.Utils.forward_fill([Decimal.new("1"), nil, Decimal.new("3"), nil, nil, Decimal.new("6")])
      [Decimal.new("1"), Decimal.new("1"), Decimal.new("3"), Decimal.new("3"), Decimal.new("3"), Decimal.new("6")]
  """
  @spec forward_fill([term()], term()) :: [term()]
  def forward_fill(data, default_value \\ Decimal.new("0"))
  def forward_fill([], _default_value), do: []

  def forward_fill([first | rest], default_value) do
    first_value = first || default_value

    {result, _last_value} =
      Enum.reduce(rest, {[first_value], first_value}, fn current, {acc, last_val} ->
        new_val = current || last_val
        {[new_val | acc], new_val}
      end)

    Enum.reverse(result)
  end

  @doc """
  Validates that all volume values in a data series are non-negative integers.

  ## Parameters

  - `data` - List of OHLCV data points

  ## Returns

  - `:ok` if all volumes are valid
  - `{:error, exception}` if any volume is invalid

  ## Example

      iex> data = [
      ...>   %{volume: 1000, close: Decimal.new("100.0")},
      ...>   %{volume: 0, close: Decimal.new("101.0")}
      ...> ]
      iex> TradingIndicators.Utils.validate_volumes(data)
      :ok
  """
  @spec validate_volumes(Types.data_series()) :: :ok | {:error, Exception.t()}
  def validate_volumes([]), do: :ok

  def validate_volumes([%{volume: volume} | rest]) when is_integer(volume) and volume >= 0 do
    validate_volumes(rest)
  end

  def validate_volumes([%{volume: volume} = data_point | _rest]) do
    {:error,
     %Errors.ValidationError{
       message: "Volume must be a non-negative integer",
       field: :volume,
       value: volume,
       constraint: "must be non-negative integer, got #{inspect(volume)} in #{inspect(data_point)}"
     }}
  end

  def validate_volumes([invalid | _rest]) do
    {:error,
     %Errors.InvalidDataFormat{
       message: "Data point missing volume field",
       expected: "map with :volume key",
       received: inspect(invalid)
     }}
  end

  @doc """
  Checks if a data series has any non-zero volume periods.

  ## Parameters

  - `data` - List of OHLCV data points

  ## Returns

  - `true` if there are non-zero volume periods
  - `false` if all volumes are zero or empty data

  ## Example

      iex> data = [%{volume: 0}, %{volume: 1000}, %{volume: 0}]
      iex> TradingIndicators.Utils.has_volume?(data)
      true

      iex> TradingIndicators.Utils.has_volume?([%{volume: 0}, %{volume: 0}])
      false
  """
  @spec has_volume?(Types.data_series()) :: boolean()
  def has_volume?([]), do: false

  def has_volume?(data) when is_list(data) do
    Enum.any?(data, fn
      %{volume: volume} when is_integer(volume) -> volume > 0
      _ -> false
    end)
  end

  @doc """
  Filters out data points with zero volume.

  ## Parameters

  - `data` - List of OHLCV data points

  ## Returns

  - List of data points with non-zero volume

  ## Example

      iex> data = [
      ...>   %{volume: 0, close: Decimal.new("100.0")},
      ...>   %{volume: 1000, close: Decimal.new("101.0")},
      ...>   %{volume: 0, close: Decimal.new("102.0")}
      ...> ]
      iex> result = TradingIndicators.Utils.filter_zero_volume(data)
      iex> length(result)
      1
  """
  @spec filter_zero_volume(Types.data_series()) :: Types.data_series()
  def filter_zero_volume(data) when is_list(data) do
    Enum.filter(data, fn
      %{volume: volume} when is_integer(volume) -> volume > 0
      _ -> false
    end)
  end

  @doc """
  Calculates volume-weighted price for a data point based on specified variant.

  ## Parameters

  - `data_point` - Single OHLCV data point
  - `variant` - Price variant (`:close`, `:typical`, `:weighted`, `:open`)

  ## Returns

  - Price * Volume as Decimal

  ## Example

      iex> data_point = %{high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000}
      iex> result = TradingIndicators.Utils.volume_weighted_price(data_point, :close)
      iex> Decimal.to_integer(result)
      103000
  """
  @spec volume_weighted_price(Types.ohlcv(), atom()) :: Decimal.t()
  def volume_weighted_price(%{close: close, volume: volume}, :close) do
    Decimal.mult(close, Decimal.new(volume))
  end

  def volume_weighted_price(%{open: open, volume: volume}, :open) do
    Decimal.mult(open, Decimal.new(volume))
  end

  def volume_weighted_price(%{high: high, low: low, close: close, volume: volume}, :typical) do
    typical_price = typical_price(%{high: high, low: low, close: close})
    Decimal.mult(typical_price, Decimal.new(volume))
  end

  def volume_weighted_price(%{high: high, low: low, close: close, volume: volume}, :weighted) do
    # Weighted Price = (High + Low + 2*Close) / 4
    close_x2 = Decimal.mult(close, Decimal.new("2"))
    sum = Decimal.add(high, Decimal.add(low, close_x2))
    weighted_price = Decimal.div(sum, Decimal.new("4"))
    Decimal.mult(weighted_price, Decimal.new(volume))
  end
end
