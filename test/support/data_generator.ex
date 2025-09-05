defmodule TradingIndicators.TestSupport.DataGenerator do
  @moduledoc """
  Test data generation utilities for Trading Indicators tests.

  This module provides functions to generate sample price data for testing
  indicators across different scenarios and sizes.
  """

  @doc """
  Generate sample price data with specified size.

  ## Parameters

  - `size` - Number of data points to generate

  ## Returns

  List of OHLCV data points with realistic price movements.

  ## Examples

      iex> data = TradingIndicators.TestSupport.DataGenerator.sample_prices(5)
      iex> length(data)
      5
      iex> hd(data) |> Map.has_key?(:close)
      true
  """
  def sample_prices(size) when is_integer(size) and size > 0 do
    base_price = 100.0

    1..size
    |> Enum.map_reduce(base_price, fn i, current_price ->
      # Create realistic price movement with some volatility
      # -2% to +2%
      change_percent = :rand.uniform() * 0.04 - 0.02
      new_price = current_price * (1 + change_percent)

      # Calculate OHLC with realistic relationships
      open = current_price
      close = new_price

      {low, high} =
        if new_price > current_price do
          {current_price * 0.995, new_price * 1.005}
        else
          {new_price * 0.995, current_price * 1.005}
        end

      data_point = %{
        open: Decimal.from_float(open),
        high: Decimal.from_float(high),
        low: Decimal.from_float(low),
        close: Decimal.from_float(close),
        volume: :rand.uniform(10000) + 1000,
        timestamp: DateTime.add(DateTime.utc_now(), -i, :minute)
      }

      {data_point, new_price}
    end)
    |> elem(0)
  end

  def sample_prices(_size) do
    raise ArgumentError, "Size must be a positive integer"
  end

  @doc """
  Generate sample price data with trend.

  ## Parameters

  - `size` - Number of data points
  - `trend` - `:up`, `:down`, or `:sideways`

  ## Returns

  List of OHLCV data points with specified trend.
  """
  def sample_prices_with_trend(size, trend \\ :sideways) do
    base_price = 100.0

    trend_factor =
      case trend do
        # 0.1% upward bias
        :up -> 0.001
        # 0.1% downward bias
        :down -> -0.001
        # No bias
        :sideways -> 0
      end

    1..size
    |> Enum.map_reduce(base_price, fn i, current_price ->
      # Add trend bias to random movement
      change_percent = :rand.uniform() * 0.04 - 0.02 + trend_factor
      new_price = current_price * (1 + change_percent)

      # Calculate OHLC
      open = current_price
      close = new_price

      {low, high} =
        if new_price > current_price do
          {current_price * 0.995, new_price * 1.005}
        else
          {new_price * 0.995, current_price * 1.005}
        end

      data_point = %{
        open: Decimal.from_float(open),
        high: Decimal.from_float(high),
        low: Decimal.from_float(low),
        close: Decimal.from_float(close),
        volume: :rand.uniform(10000) + 1000,
        timestamp: DateTime.add(DateTime.utc_now(), -i, :minute)
      }

      {data_point, new_price}
    end)
    |> elem(0)
  end

  @doc """
  Generate deterministic sample data for consistent testing.

  ## Parameters

  - `size` - Number of data points

  ## Returns

  List of OHLCV data with predictable values for reproducible tests.
  """
  def deterministic_sample_prices(size) when is_integer(size) and size > 0 do
    1..size
    |> Enum.map(fn i ->
      # Gradual price increase
      base = 100 + i * 0.5

      %{
        open: Decimal.from_float(base),
        high: Decimal.from_float(base + 1),
        low: Decimal.from_float(base - 1),
        close: Decimal.from_float(base + 0.25),
        volume: 1000 + i * 10,
        timestamp: DateTime.add(DateTime.utc_now(), -i, :minute)
      }
    end)
  end

  @doc """
  Generate edge case data for testing boundary conditions.

  ## Returns

  List containing various edge case scenarios.
  """
  def edge_case_data do
    [
      # Normal data
      %{
        open: Decimal.new("100"),
        high: Decimal.new("105"),
        low: Decimal.new("99"),
        close: Decimal.new("103"),
        volume: 1000,
        timestamp: ~U[2024-01-01 09:30:00Z]
      },

      # Zero volume
      %{
        open: Decimal.new("103"),
        high: Decimal.new("106"),
        low: Decimal.new("102"),
        close: Decimal.new("105"),
        volume: 0,
        timestamp: ~U[2024-01-01 09:31:00Z]
      },

      # Very high volume
      %{
        open: Decimal.new("105"),
        high: Decimal.new("107"),
        low: Decimal.new("104"),
        close: Decimal.new("106"),
        volume: 1_000_000,
        timestamp: ~U[2024-01-01 09:32:00Z]
      },

      # Doji pattern (open = close)
      %{
        open: Decimal.new("106"),
        high: Decimal.new("108"),
        low: Decimal.new("105"),
        close: Decimal.new("106"),
        volume: 1500,
        timestamp: ~U[2024-01-01 09:33:00Z]
      },

      # Gap up
      %{
        open: Decimal.new("110"),
        high: Decimal.new("112"),
        low: Decimal.new("109"),
        close: Decimal.new("111"),
        volume: 2000,
        timestamp: ~U[2024-01-01 09:34:00Z]
      }
    ]
  end

  @doc """
  Generate large dataset for performance testing.

  ## Parameters

  - `size` - Number of data points (default: 10,000)

  ## Returns

  Large dataset suitable for performance benchmarking.
  """
  def large_dataset(size \\ 10_000) do
    sample_prices(size)
  end

  @doc """
  Generate sample OHLCV data with specified size.

  This is an alias for `sample_prices/1` to maintain API compatibility.

  ## Parameters

  - `size` - Number of data points to generate

  ## Returns

  List of OHLCV data points with realistic price movements.
  """
  def sample_ohlcv_data(size) do
    sample_prices(size)
  end

  @doc """
  Generate known test data with predictable values for testing purposes.

  ## Returns

  List of OHLCV data points with known values for validation tests.
  """
  def known_test_data do
    [
      %{
        open: Decimal.new("100.0"),
        high: Decimal.new("105.0"),
        low: Decimal.new("99.0"),
        close: Decimal.new("103.0"),
        volume: 1000,
        timestamp: DateTime.add(DateTime.utc_now(), -1, :minute)
      },
      %{
        open: Decimal.new("103.0"),
        high: Decimal.new("107.0"),
        low: Decimal.new("102.0"),
        close: Decimal.new("106.0"),
        volume: 1200,
        timestamp: DateTime.add(DateTime.utc_now(), -2, :minute)
      },
      %{
        open: Decimal.new("106.0"),
        high: Decimal.new("108.0"),
        low: Decimal.new("104.0"),
        close: Decimal.new("105.0"),
        volume: 800,
        timestamp: DateTime.add(DateTime.utc_now(), -3, :minute)
      },
      %{
        open: Decimal.new("105.0"),
        high: Decimal.new("109.0"),
        low: Decimal.new("103.0"),
        close: Decimal.new("108.0"),
        volume: 1500,
        timestamp: DateTime.add(DateTime.utc_now(), -4, :minute)
      },
      %{
        open: Decimal.new("108.0"),
        high: Decimal.new("110.0"),
        low: Decimal.new("106.0"),
        close: Decimal.new("107.0"),
        volume: 900,
        timestamp: DateTime.add(DateTime.utc_now(), -5, :minute)
      }
    ]
  end
end
