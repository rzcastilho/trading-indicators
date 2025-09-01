ExUnit.start()

# Add test support modules and helpers
defmodule TradingIndicators.TestSupport.DataGenerator do
  @moduledoc """
  Helper functions for generating test data.
  """

  @doc """
  Generates sample OHLCV data for testing.
  """
  def sample_ohlcv_data(count \\ 50) do
    base_price = 100.0
    base_time = ~U[2024-01-01 09:30:00Z]

    1..count
    |> Enum.map(fn i ->
      # Simple price evolution for testing
      drift = i * 0.1
      volatility = :rand.normal(0, 2.0)
      close = base_price + drift + volatility
      open = close + :rand.normal(0, 0.5)
      high = max(open, close) + abs(:rand.normal(0, 1.0))
      low = min(open, close) - abs(:rand.normal(0, 1.0))
      volume = trunc(1000 + abs(:rand.normal(0, 500)))

      %{
        open: Decimal.from_float(Float.round(open, 2)),
        high: Decimal.from_float(Float.round(high, 2)),
        low: Decimal.from_float(Float.round(low, 2)),
        close: Decimal.from_float(Float.round(close, 2)),
        volume: volume,
        timestamp: DateTime.add(base_time, (i - 1) * 60, :second)
      }
    end)
  end

  @doc """
  Generates simple price series for testing.
  """
  def sample_prices(count \\ 50, start_price \\ 100.0) do
    1..count
    |> Enum.map(fn i ->
      start_price + i * 0.5 + :rand.normal(0, 2.0)
    end)
    |> Enum.map(&Decimal.from_float(Float.round(&1, 2)))
  end

  @doc """
  Generates known test data with predictable results.
  """
  def known_test_data do
    [
      %{
        open: Decimal.new("100.0"),
        high: Decimal.new("105.0"),
        low: Decimal.new("99.0"),
        close: Decimal.new("103.0"),
        volume: 1000,
        timestamp: ~U[2024-01-01 09:30:00Z]
      },
      %{
        open: Decimal.new("103.0"),
        high: Decimal.new("107.0"),
        low: Decimal.new("102.0"),
        close: Decimal.new("106.0"),
        volume: 1200,
        timestamp: ~U[2024-01-01 09:31:00Z]
      },
      %{
        open: Decimal.new("106.0"),
        high: Decimal.new("108.0"),
        low: Decimal.new("104.0"),
        close: Decimal.new("105.0"),
        volume: 800,
        timestamp: ~U[2024-01-01 09:32:00Z]
      },
      %{
        open: Decimal.new("105.0"),
        high: Decimal.new("109.0"),
        low: Decimal.new("103.0"),
        close: Decimal.new("108.0"),
        volume: 1500,
        timestamp: ~U[2024-01-01 09:33:00Z]
      },
      %{
        open: Decimal.new("108.0"),
        high: Decimal.new("110.0"),
        low: Decimal.new("106.0"),
        close: Decimal.new("107.0"),
        volume: 900,
        timestamp: ~U[2024-01-01 09:34:00Z]
      }
    ]
  end
end
