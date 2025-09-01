defmodule TradingIndicators.TrendTest do
  use ExUnit.Case, async: true
  doctest TradingIndicators.Trend

  alias TradingIndicators.Trend
  alias TradingIndicators.Trend.{SMA, EMA, WMA, HMA, KAMA, MACD}
  require Decimal

  setup do
    data = [
      %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
      %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
      %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]},
      %{close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:33:00Z]},
      %{close: Decimal.new("105"), timestamp: ~U[2024-01-01 09:34:00Z]}
    ]

    {:ok, data: data}
  end

  describe "available_indicators/0" do
    test "returns all trend indicator modules" do
      indicators = Trend.available_indicators()
      
      assert SMA in indicators
      assert EMA in indicators
      assert WMA in indicators
      assert HMA in indicators
      assert KAMA in indicators
      assert MACD in indicators
      assert length(indicators) == 6
    end
  end

  describe "calculate/3" do
    test "calculates SMA through unified interface", %{data: data} do
      assert {:ok, results} = Trend.calculate(SMA, data, period: 3)
      assert length(results) == 3
      
      first_result = List.first(results)
      assert first_result.metadata.indicator == "SMA"
    end

    test "calculates EMA through unified interface", %{data: data} do
      assert {:ok, results} = Trend.calculate(EMA, data, period: 3)
      assert length(results) >= 1
      
      first_result = List.first(results)
      assert first_result.metadata.indicator == "EMA"
    end

    test "returns error for unknown indicator", %{data: data} do
      assert {:error, error} = Trend.calculate(:unknown, data, period: 3)
      assert error.param == :indicator
    end
  end

  describe "convenience functions" do
    test "sma/2 works", %{data: data} do
      assert {:ok, results} = Trend.sma(data, period: 3)
      assert List.first(results).metadata.indicator == "SMA"
    end

    test "ema/2 works", %{data: data} do
      assert {:ok, results} = Trend.ema(data, period: 3)
      assert List.first(results).metadata.indicator == "EMA"
    end

    test "wma/2 works", %{data: data} do
      assert {:ok, results} = Trend.wma(data, period: 3)
      assert List.first(results).metadata.indicator == "WMA"
    end
  end

  describe "streaming interface" do
    test "init_stream/2 initializes state for SMA" do
      state = Trend.init_stream(SMA, period: 5)
      assert state.period == 5
      assert state.prices == []
    end

    test "init_stream/2 initializes state for EMA" do
      state = Trend.init_stream(EMA, period: 5)
      assert state.period == 5
      assert state.ema_value == nil
    end

    test "update_stream/2 works with SMA state", %{data: data} do
      state = Trend.init_stream(SMA, period: 3)
      
      # Process data points
      {final_state, final_result} = 
        Enum.reduce(data, {state, nil}, fn data_point, {current_state, _prev} ->
          {:ok, new_state, result} = Trend.update_stream(current_state, data_point)
          {new_state, result}
        end)
      
      assert final_state.count == length(data)
      if final_result do
        assert final_result.metadata.indicator == "SMA"
      end
    end

    test "update_stream/2 returns error for unknown state format" do
      invalid_state = %{unknown: "state"}
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      
      assert {:error, error} = Trend.update_stream(invalid_state, data_point)
      assert error.operation == :update_stream
    end
  end

  describe "indicator_info/1" do
    test "returns info for SMA" do
      info = Trend.indicator_info(SMA)
      
      assert info.module == SMA
      assert info.name == "SMA"
      assert info.required_periods == 20
      assert info.supports_streaming == true
    end

    test "returns error for unknown indicator" do
      info = Trend.indicator_info(:unknown)
      assert info.error == "Unknown indicator"
    end
  end

  describe "all_indicators_info/0" do
    test "returns info for all indicators" do
      all_info = Trend.all_indicators_info()
      
      assert length(all_info) == 6
      assert Enum.all?(all_info, fn info -> Map.has_key?(info, :module) end)
      assert Enum.all?(all_info, fn info -> Map.has_key?(info, :name) end)
    end
  end
end