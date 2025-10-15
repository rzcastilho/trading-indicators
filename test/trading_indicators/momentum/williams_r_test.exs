defmodule TradingIndicators.Momentum.WilliamsRTest do
  use ExUnit.Case
  alias TradingIndicators.Momentum.WilliamsR
  require Decimal
  doctest WilliamsR

  describe "calculate/2" do
    test "calculates Williams %R with sufficient data" do
      data = create_test_hlc_data(15)

      {:ok, results} = WilliamsR.calculate(data, period: 14)

      assert length(results) == 2

      result = List.first(results)
      assert %{value: wr_value, timestamp: _timestamp, metadata: metadata} = result

      assert Decimal.is_decimal(wr_value)
      assert Decimal.gte?(wr_value, Decimal.new("-100"))
      assert Decimal.lte?(wr_value, Decimal.new("0"))

      assert metadata.indicator == "Williams %R"
      assert metadata.period == 14
      assert metadata.overbought == -20
      assert metadata.oversold == -80
      assert metadata.signal in [:overbought, :oversold, :neutral]
    end

    test "calculates Williams %R with custom parameters" do
      data = create_test_hlc_data(12)

      {:ok, results} = WilliamsR.calculate(data, period: 10, overbought: -10, oversold: -90)

      assert length(results) > 0

      result = List.first(results)
      assert result.metadata.period == 10
      assert result.metadata.overbought == -10
      assert result.metadata.oversold == -90
    end

    test "returns error for insufficient data" do
      data = create_test_hlc_data(5)

      {:error, error} = WilliamsR.calculate(data, period: 14)

      assert %TradingIndicators.Errors.InsufficientData{} = error
      assert error.required == 14
      assert error.provided == 5
    end

    test "validates parameters correctly" do
      data = create_test_hlc_data(20)

      # Invalid period
      {:error, error} = WilliamsR.calculate(data, period: 0)
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.param == :period

      # Invalid overbought level (should be between -100 and 0)
      {:error, error} = WilliamsR.calculate(data, overbought: 20)
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.param == :overbought

      # Invalid level relationship
      {:error, error} = WilliamsR.calculate(data, overbought: -80, oversold: -20)
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.param == :levels
    end
  end

  describe "streaming functionality" do
    test "init_state/1 initializes proper state" do
      state = WilliamsR.init_state(period: 14, overbought: -10, oversold: -90)

      assert state.period == 14
      assert state.overbought == -10
      assert state.oversold == -90
      assert state.recent_highs == []
      assert state.recent_lows == []
      assert state.count == 0
    end

    test "update_state/2 processes data points correctly" do
      state = WilliamsR.init_state(period: 3)

      data_points = [
        %{
          high: Decimal.new("105"),
          low: Decimal.new("95"),
          close: Decimal.new("100"),
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          high: Decimal.new("107"),
          low: Decimal.new("97"),
          close: Decimal.new("102"),
          timestamp: ~U[2024-01-01 09:31:00Z]
        },
        %{
          high: Decimal.new("106"),
          low: Decimal.new("96"),
          close: Decimal.new("101"),
          timestamp: ~U[2024-01-01 09:32:00Z]
        },
        %{
          high: Decimal.new("108"),
          low: Decimal.new("98"),
          close: Decimal.new("103"),
          timestamp: ~U[2024-01-01 09:33:00Z]
        }
      ]

      {final_state, final_result} =
        Enum.reduce(data_points, {state, nil}, fn data_point, {acc_state, _} ->
          {:ok, new_state, result} = WilliamsR.update_state(acc_state, data_point)
          {new_state, result}
        end)

      assert final_state.count == 4
      # Should have a result after 3 data points
      assert is_map(final_result)
      assert final_result.metadata.indicator == "Williams %R"
      assert Decimal.is_decimal(final_result.value)
    end
  end

  describe "mathematical accuracy" do
    test "calculates correct Williams %R value" do
      # Test case with known values
      data = [
        %{
          high: Decimal.new("110"),
          low: Decimal.new("90"),
          close: Decimal.new("95"),
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          high: Decimal.new("115"),
          low: Decimal.new("85"),
          close: Decimal.new("90"),
          timestamp: ~U[2024-01-01 09:31:00Z]
        },
        %{
          high: Decimal.new("112"),
          low: Decimal.new("88"),
          close: Decimal.new("92"),
          timestamp: ~U[2024-01-01 09:32:00Z]
        }
      ]

      {:ok, results} = WilliamsR.calculate(data, period: 3)

      assert length(results) == 1
      result = List.first(results)

      # For the last period:
      # Highest high = 115, Lowest low = 85, Current close = 92
      # Williams %R = -((115 - 92) / (115 - 85)) * 100 = -(23 / 30) * 100 = -76.67%
      expected_wr = Decimal.new("-76.6667")
      assert Decimal.equal?(Decimal.round(result.value, 4), expected_wr)
    end

    test "handles edge cases correctly" do
      # Test case where high equals low (no price range)
      data = [
        %{
          high: Decimal.new("100"),
          low: Decimal.new("100"),
          close: Decimal.new("100"),
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          high: Decimal.new("100"),
          low: Decimal.new("100"),
          close: Decimal.new("100"),
          timestamp: ~U[2024-01-01 09:31:00Z]
        },
        %{
          high: Decimal.new("100"),
          low: Decimal.new("100"),
          close: Decimal.new("100"),
          timestamp: ~U[2024-01-01 09:32:00Z]
        }
      ]

      {:ok, results} = WilliamsR.calculate(data, period: 3)

      assert length(results) == 1
      result = List.first(results)

      # Should return neutral value (-50%) when no price range
      expected_wr = Decimal.new("-50.0")
      assert Decimal.equal?(result.value, expected_wr)
    end
  end

  describe "required_periods/0" do
    test "returns default required periods" do
      assert WilliamsR.required_periods() == 14
    end
  end

  describe "required_periods/1" do
    test "returns configured required periods" do
      assert WilliamsR.required_periods(period: 10) == 10
    end
  end

  # Helper function to create test HLC data
  defp create_test_hlc_data(count) do
    base_price = 100

    1..count
    |> Enum.map(fn i ->
      base = base_price + :rand.uniform(20) - 10
      high = base + :rand.uniform(5)
      low = base - :rand.uniform(5)
      close = (low + :rand.uniform(trunc(high - low))) |> max(low) |> min(high)

      %{
        high: Decimal.new(high),
        low: Decimal.new(low),
        close: Decimal.new(close),
        timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i * 60, :second)
      }
    end)
  end
end
