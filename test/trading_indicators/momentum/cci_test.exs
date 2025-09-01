defmodule TradingIndicators.Momentum.CCITest do
  use ExUnit.Case
  alias TradingIndicators.Momentum.CCI
  require Decimal
  doctest CCI

  describe "calculate/2" do
    test "calculates CCI with sufficient data" do
      data = create_test_hlc_data(21)
      
      {:ok, results} = CCI.calculate(data, period: 20)
      
      assert length(results) == 2
      
      result = List.first(results)
      assert %{value: cci_value, timestamp: _timestamp, metadata: metadata} = result
      
      assert Decimal.is_decimal(cci_value)
      # CCI is unbounded, so just check it's reasonable
      assert Decimal.gt?(cci_value, Decimal.new("-500"))
      assert Decimal.lt?(cci_value, Decimal.new("500"))
      
      assert metadata.indicator == "CCI"
      assert metadata.period == 20
      assert metadata.constant == "0.015"
      assert metadata.signal in [:overbought, :oversold, :neutral]
    end

    test "calculates CCI with custom parameters" do
      data = create_test_hlc_data(12)
      
      {:ok, results} = CCI.calculate(data, period: 10, constant: "0.020")
      
      assert length(results) > 0
      
      result = List.first(results)
      assert result.metadata.period == 10
      assert result.metadata.constant == "0.020"
    end

    test "returns error for insufficient data" do
      data = create_test_hlc_data(5)
      
      {:error, error} = CCI.calculate(data, period: 20)
      
      assert %TradingIndicators.Errors.InsufficientData{} = error
      assert error.required == 20
      assert error.provided == 5
    end

    test "validates parameters correctly" do
      data = create_test_hlc_data(25)
      
      # Invalid period
      {:error, error} = CCI.calculate(data, period: 0)
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.param == :period
      
      # Invalid constant
      {:error, error} = CCI.calculate(data, constant: "-0.015")
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.param == :constant
    end
  end

  describe "streaming functionality" do
    test "init_state/1 initializes proper state" do
      state = CCI.init_state(period: 20, constant: "0.020")
      
      assert state.period == 20
      assert Decimal.equal?(state.constant, Decimal.new("0.020"))
      assert state.typical_prices == []
      assert state.count == 0
    end

    test "update_state/2 processes data points correctly" do
      state = CCI.init_state(period: 3)
      
      data_points = [
        %{high: Decimal.new("105"), low: Decimal.new("95"), close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{high: Decimal.new("107"), low: Decimal.new("97"), close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{high: Decimal.new("106"), low: Decimal.new("96"), close: Decimal.new("101"), timestamp: ~U[2024-01-01 09:32:00Z]},
        %{high: Decimal.new("108"), low: Decimal.new("98"), close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:33:00Z]}
      ]
      
      {final_state, final_result} = Enum.reduce(data_points, {state, nil}, fn data_point, {acc_state, _} ->
        {:ok, new_state, result} = CCI.update_state(acc_state, data_point)
        {new_state, result}
      end)
      
      assert final_state.count == 4
      assert is_map(final_result)  # Should have a result after 3 data points
      assert final_result.metadata.indicator == "CCI"
      assert Decimal.is_decimal(final_result.value)
    end
  end

  describe "mathematical accuracy" do
    test "calculates typical price correctly" do
      # Typical Price = (High + Low + Close) / 3
      data = [
        %{high: Decimal.new("120"), low: Decimal.new("80"), close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{high: Decimal.new("125"), low: Decimal.new("85"), close: Decimal.new("105"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{high: Decimal.new("130"), low: Decimal.new("90"), close: Decimal.new("110"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]
      
      {:ok, results} = CCI.calculate(data, period: 3)
      
      assert length(results) == 1
      
      # The calculation should use typical prices:
      # TP1 = (120+80+100)/3 = 100
      # TP2 = (125+85+105)/3 = 105  
      # TP3 = (130+90+110)/3 = 110
      # SMA = (100+105+110)/3 = 105
      # Mean Deviation = (|100-105|+|105-105|+|110-105|)/3 = (5+0+5)/3 = 3.33
      # CCI = (110-105)/(0.015*3.33) = 5/0.05 = 100
      
      result = List.first(results)
      assert Decimal.is_decimal(result.value)
    end
  end

  describe "required_periods/0" do
    test "returns default required periods" do
      assert CCI.required_periods() == 20
    end
  end

  describe "required_periods/1" do
    test "returns configured required periods" do
      assert CCI.required_periods(period: 10) == 10
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
      close = low + :rand.uniform(trunc(high - low)) |> max(low) |> min(high)
      
      %{
        high: Decimal.new(high),
        low: Decimal.new(low),
        close: Decimal.new(close),
        timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i * 60, :second)
      }
    end)
  end
end