defmodule TradingIndicators.Trend.KAMATest do
  use ExUnit.Case, async: true
  doctest TradingIndicators.Trend.KAMA

  alias TradingIndicators.Trend.KAMA
  alias TradingIndicators.Errors
  require Decimal

  describe "calculate/2" do
    test "calculates KAMA with trending data" do
      # Create trending data to test KAMA adaptation
      data =
        for i <- 0..15 do
          # Steady uptrend
          price = 100 + i * 0.5

          %{
            close: Decimal.new(to_string(price)),
            timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :minute)
          }
        end

      assert {:ok, results} = KAMA.calculate(data, period: 10)

      assert length(results) >= 1

      first_result = List.first(results)
      assert Decimal.is_decimal(first_result.value)
      assert first_result.metadata.indicator == "KAMA"
      assert first_result.metadata.period == 10
      assert Map.has_key?(first_result.metadata, :efficiency_ratio)
    end

    test "returns error for insufficient data" do
      short_data = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]}
      ]

      assert {:error, %Errors.InsufficientData{}} = KAMA.calculate(short_data, period: 10)
    end

    test "returns error for invalid period" do
      data = [%{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      assert {:error, %Errors.InvalidParams{}} = KAMA.calculate(data, period: 0)
    end
  end

  describe "streaming functionality" do
    test "init_state/1 creates proper initial state" do
      state = KAMA.init_state(period: 10, fast_period: 2, slow_period: 30)

      assert state.period == 10
      assert state.fast_period == 2
      assert state.slow_period == 30
      assert state.prices == []
      assert state.kama_value == nil
      assert state.count == 0
      assert Decimal.is_decimal(state.fast_sc)
      assert Decimal.is_decimal(state.slow_sc)
    end

    test "update_state/2 accumulates data" do
      state = KAMA.init_state(period: 5, source: :close)

      # Generate sufficient data points
      data_points =
        for i <- 100..110 do
          %{
            close: Decimal.new(to_string(i)),
            timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i - 100, :minute)
          }
        end

      # Process data points
      {final_state, final_result} =
        Enum.reduce(data_points, {state, nil}, fn data_point, {current_state, _prev_result} ->
          {:ok, new_state, result} = KAMA.update_state(current_state, data_point)
          {new_state, result}
        end)

      # Should eventually get a KAMA result
      if final_result do
        assert Decimal.is_decimal(final_result.value)
        assert Map.has_key?(final_result.metadata, :efficiency_ratio)
      end

      assert final_state.count == length(data_points)
    end
  end
end
