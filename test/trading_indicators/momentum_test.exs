defmodule TradingIndicators.MomentumTest do
  use ExUnit.Case
  alias TradingIndicators.Momentum
  alias TradingIndicators.Momentum.{RSI, Stochastic, WilliamsR, CCI, ROC}
  alias TradingIndicators.Momentum.Momentum, as: MomentumIndicator

  describe "available_indicators/0" do
    test "returns list of all momentum indicator modules" do
      indicators = Momentum.available_indicators()
      
      assert length(indicators) == 6
      assert RSI in indicators
      assert Stochastic in indicators
      assert WilliamsR in indicators
      assert CCI in indicators
      assert ROC in indicators
      assert MomentumIndicator in indicators
    end
  end

  describe "calculate/3" do
    setup do
      data = [
        %{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("95"), close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
        %{open: Decimal.new("100"), high: Decimal.new("107"), low: Decimal.new("97"), close: Decimal.new("102"), volume: 1200, timestamp: ~U[2024-01-01 09:31:00Z]},
        %{open: Decimal.new("102"), high: Decimal.new("106"), low: Decimal.new("99"), close: Decimal.new("101"), volume: 1100, timestamp: ~U[2024-01-01 09:32:00Z]},
        %{open: Decimal.new("101"), high: Decimal.new("108"), low: Decimal.new("98"), close: Decimal.new("103"), volume: 1300, timestamp: ~U[2024-01-01 09:33:00Z]},
        %{open: Decimal.new("103"), high: Decimal.new("109"), low: Decimal.new("100"), close: Decimal.new("105"), volume: 1400, timestamp: ~U[2024-01-01 09:34:00Z]}
      ]
      %{data: data}
    end

    test "calculates RSI with valid indicator", %{data: data} do
      {:ok, results} = Momentum.calculate(RSI, data, period: 4)
      assert length(results) == 1
      assert %{value: _value, timestamp: _timestamp, metadata: %{indicator: "RSI"}} = List.first(results)
    end

    test "calculates Stochastic with valid indicator", %{data: data} do
      {:ok, results} = Momentum.calculate(Stochastic, data, k_period: 3, d_period: 2)
      assert length(results) >= 1
      assert %{value: %{k: _k_value, d: _d_value}, metadata: %{indicator: "Stochastic"}} = List.first(results)
    end

    test "calculates Williams %R with valid indicator", %{data: data} do
      {:ok, results} = Momentum.calculate(WilliamsR, data, period: 3)
      assert length(results) == 3
      assert %{value: _value, metadata: %{indicator: "Williams %R"}} = List.first(results)
    end

    test "calculates CCI with valid indicator", %{data: data} do
      {:ok, results} = Momentum.calculate(CCI, data, period: 3)
      assert length(results) == 3
      assert %{value: _value, metadata: %{indicator: "CCI"}} = List.first(results)
    end

    test "calculates ROC with valid indicator", %{data: data} do
      {:ok, results} = Momentum.calculate(ROC, data, period: 3)
      assert length(results) == 2
      assert %{value: _value, metadata: %{indicator: "ROC"}} = List.first(results)
    end

    test "calculates Momentum with valid indicator", %{data: data} do
      {:ok, results} = Momentum.calculate(MomentumIndicator, data, period: 3)
      assert length(results) == 2
      assert %{value: _value, metadata: %{indicator: "Momentum"}} = List.first(results)
    end

    test "returns error for unknown indicator", %{data: data} do
      {:error, error} = Momentum.calculate(UnknownIndicator, data)
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.message =~ "Unknown momentum indicator"
    end
  end

  describe "init_stream/2" do
    test "initializes streaming state for RSI" do
      state = Momentum.init_stream(RSI, period: 14)
      
      assert %{period: 14, source: :close, avg_gain: nil, avg_loss: nil} = state
    end

    test "initializes streaming state for Stochastic" do
      state = Momentum.init_stream(Stochastic, k_period: 14, d_period: 3)
      
      assert %{k_period: 14, d_period: 3, highs: [], lows: [], closes: []} = state
    end

    test "raises error for unknown indicator" do
      assert_raise ArgumentError, ~r/Unknown momentum indicator/, fn ->
        Momentum.init_stream(UnknownIndicator, period: 14)
      end
    end
  end

  describe "update_stream/2" do
    setup do
      data_point = %{
        open: Decimal.new("100"), 
        high: Decimal.new("105"), 
        low: Decimal.new("95"), 
        close: Decimal.new("100"), 
        volume: 1000, 
        timestamp: ~U[2024-01-01 09:30:00Z]
      }
      %{data_point: data_point}
    end

    test "updates RSI streaming state", %{data_point: data_point} do
      state = Momentum.init_stream(RSI, period: 14)
      
      {:ok, new_state, result} = Momentum.update_stream(state, data_point)
      
      assert new_state.count == 1
      assert is_nil(result)  # Not enough data yet
    end

    test "updates Stochastic streaming state", %{data_point: data_point} do
      state = Momentum.init_stream(Stochastic, k_period: 3, d_period: 2)
      
      {:ok, new_state, result} = Momentum.update_stream(state, data_point)
      
      assert new_state.count == 1
      assert length(new_state.highs) == 1
      assert is_nil(result)  # Not enough data yet
    end

    test "returns error for unknown state format" do
      invalid_state = %{unknown: "state"}
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      
      {:error, error} = Momentum.update_stream(invalid_state, data_point)
      assert %TradingIndicators.Errors.StreamStateError{} = error
    end
  end

  describe "convenience functions" do
    setup do
      data = [
        %{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("95"), close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
        %{open: Decimal.new("100"), high: Decimal.new("107"), low: Decimal.new("97"), close: Decimal.new("102"), volume: 1200, timestamp: ~U[2024-01-01 09:31:00Z]},
        %{open: Decimal.new("102"), high: Decimal.new("106"), low: Decimal.new("99"), close: Decimal.new("101"), volume: 1100, timestamp: ~U[2024-01-01 09:32:00Z]},
        %{open: Decimal.new("101"), high: Decimal.new("108"), low: Decimal.new("98"), close: Decimal.new("103"), volume: 1300, timestamp: ~U[2024-01-01 09:33:00Z]},
        %{open: Decimal.new("103"), high: Decimal.new("109"), low: Decimal.new("100"), close: Decimal.new("105"), volume: 1400, timestamp: ~U[2024-01-01 09:34:00Z]}
      ]
      %{data: data}
    end

    test "rsi/2 calculates RSI", %{data: data} do
      {:ok, results} = Momentum.rsi(data, period: 4)
      assert length(results) == 1
      assert %{metadata: %{indicator: "RSI"}} = List.first(results)
    end

    test "stochastic/2 calculates Stochastic", %{data: data} do
      {:ok, results} = Momentum.stochastic(data, k_period: 3, d_period: 2)
      assert length(results) >= 1
      assert %{metadata: %{indicator: "Stochastic"}} = List.first(results)
    end

    test "williams_r/2 calculates Williams %R", %{data: data} do
      {:ok, results} = Momentum.williams_r(data, period: 3)
      assert length(results) == 3
      assert %{metadata: %{indicator: "Williams %R"}} = List.first(results)
    end

    test "cci/2 calculates CCI", %{data: data} do
      {:ok, results} = Momentum.cci(data, period: 3)
      assert length(results) == 3
      assert %{metadata: %{indicator: "CCI"}} = List.first(results)
    end

    test "roc/2 calculates ROC", %{data: data} do
      {:ok, results} = Momentum.roc(data, period: 3)
      assert length(results) == 2
      assert %{metadata: %{indicator: "ROC"}} = List.first(results)
    end

    test "momentum/2 calculates Momentum", %{data: data} do
      {:ok, results} = Momentum.momentum(data, period: 3)
      assert length(results) == 2
      assert %{metadata: %{indicator: "Momentum"}} = List.first(results)
    end
  end

  describe "indicator_info/1" do
    test "returns information for valid indicator" do
      info = Momentum.indicator_info(RSI)
      
      assert info.module == RSI
      assert info.name == "RSI"
      assert info.required_periods == 15
      assert info.supports_streaming == true
    end

    test "returns error for invalid indicator" do
      info = Momentum.indicator_info(UnknownIndicator)
      
      assert %{error: "Unknown indicator"} = info
    end
  end

  describe "all_indicators_info/0" do
    test "returns information for all indicators" do
      all_info = Momentum.all_indicators_info()
      
      assert length(all_info) == 6
      assert Enum.all?(all_info, &Map.has_key?(&1, :module))
      assert Enum.all?(all_info, &Map.has_key?(&1, :name))
      assert Enum.all?(all_info, &Map.has_key?(&1, :required_periods))
      assert Enum.all?(all_info, &Map.has_key?(&1, :supports_streaming))
    end
  end
end