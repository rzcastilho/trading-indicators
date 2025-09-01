defmodule TradingIndicators.TypesTest do
  use ExUnit.Case, async: true
  require Decimal

  alias TradingIndicators.TestSupport.DataGenerator
  alias TradingIndicators.Types

  doctest TradingIndicators.Types

  describe "valid_ohlcv?/1" do
    test "returns true for valid OHLCV data" do
      data = %{
        open: Decimal.new("100.0"),
        high: Decimal.new("105.0"),
        low: Decimal.new("99.0"),
        close: Decimal.new("103.0"),
        volume: 1000,
        timestamp: ~U[2024-01-01 09:30:00Z]
      }

      assert Types.valid_ohlcv?(data)
    end

    test "returns false for missing required fields" do
      data = %{
        open: Decimal.new("100.0"),
        high: Decimal.new("105.0"),
        close: Decimal.new("103.0")
        # missing low, volume, timestamp
      }

      refute Types.valid_ohlcv?(data)
    end

    test "returns false for invalid field types" do
      data = %{
        # should be Decimal
        open: "100.0",
        high: Decimal.new("105.0"),
        low: Decimal.new("99.0"),
        close: Decimal.new("103.0"),
        volume: 1000,
        timestamp: ~U[2024-01-01 09:30:00Z]
      }

      refute Types.valid_ohlcv?(data)
    end

    test "returns false for negative volume" do
      data = %{
        open: Decimal.new("100.0"),
        high: Decimal.new("105.0"),
        low: Decimal.new("99.0"),
        close: Decimal.new("103.0"),
        # negative volume
        volume: -100,
        timestamp: ~U[2024-01-01 09:30:00Z]
      }

      refute Types.valid_ohlcv?(data)
    end

    test "returns false for non-DateTime timestamp" do
      data = %{
        open: Decimal.new("100.0"),
        high: Decimal.new("105.0"),
        low: Decimal.new("99.0"),
        close: Decimal.new("103.0"),
        volume: 1000,
        # should be DateTime
        timestamp: "2024-01-01"
      }

      refute Types.valid_ohlcv?(data)
    end

    test "returns false for non-map input" do
      refute Types.valid_ohlcv?([1, 2, 3])
      refute Types.valid_ohlcv?("invalid")
      refute Types.valid_ohlcv?(nil)
    end
  end

  describe "valid_indicator_result?/1" do
    test "returns true for valid indicator result with numeric value" do
      result = %{
        value: Decimal.new("14.5"),
        timestamp: ~U[2024-01-01 09:30:00Z],
        metadata: %{period: 14}
      }

      assert Types.valid_indicator_result?(result)
    end

    test "returns true for valid indicator result with map value" do
      result = %{
        value: %{macd: Decimal.new("1.5"), signal: Decimal.new("1.2"), histogram: Decimal.new("0.3")},
        timestamp: ~U[2024-01-01 09:30:00Z],
        metadata: %{fast: 12, slow: 26}
      }

      assert Types.valid_indicator_result?(result)
    end

    test "returns false for missing required fields" do
      result = %{
        value: Decimal.new("14.5")
        # missing timestamp
      }

      refute Types.valid_indicator_result?(result)
    end

    test "returns false for invalid timestamp" do
      result = %{
        value: Decimal.new("14.5"),
        timestamp: "invalid"
      }

      refute Types.valid_indicator_result?(result)
    end

    test "returns false for invalid value type" do
      result = %{
        # should be number or map
        value: "invalid",
        timestamp: ~U[2024-01-01 09:30:00Z]
      }

      refute Types.valid_indicator_result?(result)
    end

    test "returns false for non-map input" do
      refute Types.valid_indicator_result?([1, 2, 3])
      refute Types.valid_indicator_result?("invalid")
      refute Types.valid_indicator_result?(nil)
    end
  end

  describe "resolve_period/1" do
    test "converts period atoms to integers" do
      assert Types.resolve_period(:short) == 14
      assert Types.resolve_period(:medium) == 21
      assert Types.resolve_period(:long) == 50
    end

    test "returns integer periods unchanged" do
      assert Types.resolve_period(10) == 10
      assert Types.resolve_period(1) == 1
      assert Types.resolve_period(100) == 100
    end
  end

  describe "type validation with generated data" do
    test "validates generated OHLCV data" do
      data = DataGenerator.sample_ohlcv_data(10)

      Enum.each(data, fn ohlcv ->
        assert Types.valid_ohlcv?(ohlcv), "Generated OHLCV data should be valid: #{inspect(ohlcv)}"
      end)
    end

    test "validates known test data" do
      data = DataGenerator.known_test_data()

      Enum.each(data, fn ohlcv ->
        assert Types.valid_ohlcv?(ohlcv), "Known test data should be valid: #{inspect(ohlcv)}"
      end)
    end
  end
end
