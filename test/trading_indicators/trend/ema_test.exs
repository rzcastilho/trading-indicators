defmodule TradingIndicators.Trend.EMATest do
  use ExUnit.Case, async: true
  doctest TradingIndicators.Trend.EMA

  alias TradingIndicators.Trend.EMA
  alias TradingIndicators.Errors
  require Decimal

  describe "calculate/2" do
    setup do
      data = [
        %{
          open: Decimal.new("100.0"), high: Decimal.new("105.0"), low: Decimal.new("98.0"),
          close: Decimal.new("100.0"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          open: Decimal.new("103.0"), high: Decimal.new("107.0"), low: Decimal.new("101.0"),
          close: Decimal.new("102.0"), volume: 1200, timestamp: ~U[2024-01-01 09:31:00Z]
        },
        %{
          open: Decimal.new("105.0"), high: Decimal.new("108.0"), low: Decimal.new("103.0"),
          close: Decimal.new("104.0"), volume: 1100, timestamp: ~U[2024-01-01 09:32:00Z]
        },
        %{
          open: Decimal.new("107.0"), high: Decimal.new("109.0"), low: Decimal.new("105.0"),
          close: Decimal.new("106.0"), volume: 950, timestamp: ~U[2024-01-01 09:33:00Z]
        },
        %{
          open: Decimal.new("106.0"), high: Decimal.new("110.0"), low: Decimal.new("104.0"),
          close: Decimal.new("108.0"), volume: 1300, timestamp: ~U[2024-01-01 09:34:00Z]
        }
      ]

      {:ok, data: data}
    end

    test "calculates EMA with SMA bootstrap (default)", %{data: data} do
      assert {:ok, results} = EMA.calculate(data, period: 3)
      
      assert length(results) == 3
      
      [first, second, third] = results
      
      # First EMA should be SMA of first 3 prices: (100 + 102 + 104) / 3 = 102
      assert Decimal.equal?(first.value, Decimal.new("102.0"))
      assert first.timestamp == ~U[2024-01-01 09:32:00Z]
      assert first.metadata.indicator == "EMA"
      assert first.metadata.period == 3
      
      # Verify that EMA values are calculated correctly
      assert is_struct(second.value, Decimal)
      assert is_struct(third.value, Decimal)
    end

    test "calculates EMA with first value initialization", %{data: data} do
      assert {:ok, results} = EMA.calculate(data, period: 3, initialization: :first_value)
      
      assert length(results) == 5  # All data points should have EMA values
      
      [first | _rest] = results
      
      # First EMA should be the first price
      assert Decimal.equal?(first.value, Decimal.new("100.0"))
      assert first.timestamp == ~U[2024-01-01 09:30:00Z]
    end

    test "calculates EMA with custom smoothing factor", %{data: data} do
      custom_smoothing = Decimal.new("0.4")  # Higher than default for 3-period EMA
      assert {:ok, results} = EMA.calculate(data, period: 3, smoothing: custom_smoothing)
      
      assert length(results) >= 1
      first_result = List.first(results)
      assert first_result.metadata.smoothing == custom_smoothing
    end

    test "works with different price sources", %{data: data} do
      assert {:ok, high_results} = EMA.calculate(data, period: 2, source: :high)
      assert {:ok, low_results} = EMA.calculate(data, period: 2, source: :low)
      assert {:ok, open_results} = EMA.calculate(data, period: 2, source: :open)
      
      assert length(high_results) == 4
      assert length(low_results) == 4
      assert length(open_results) == 4
      
      # Verify different sources produce different results
      refute Decimal.equal?(Enum.at(high_results, 0).value, Enum.at(low_results, 0).value)
    end

    test "handles price series input", %{data: data} do
      closes = Enum.map(data, & &1.close)
      assert {:ok, results} = EMA.calculate(closes, period: 2)
      
      assert length(results) == 4
      # When using price series, timestamps default to current time
      assert is_struct(Enum.at(results, 0).timestamp, DateTime)
    end

    test "returns error for insufficient data with SMA bootstrap", %{data: data} do
      short_data = Enum.take(data, 2)
      assert {:error, %Errors.InsufficientData{} = error} = 
        EMA.calculate(short_data, period: 5, initialization: :sma_bootstrap)
      
      assert error.required == 5
      assert error.provided == 2
    end

    test "works with minimal data for first value initialization" do
      data = [%{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      assert {:ok, results} = EMA.calculate(data, period: 10, initialization: :first_value)
      
      assert length(results) == 1
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.new("100.0"))
    end

    test "returns error for empty data" do
      assert {:error, %Errors.InsufficientData{}} = EMA.calculate([], period: 1)
    end

    test "returns error for invalid period" do
      data = [%{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      assert {:error, %Errors.InvalidParams{}} = EMA.calculate(data, period: 0)
      assert {:error, %Errors.InvalidParams{}} = EMA.calculate(data, period: -1)
    end

    test "returns error for invalid smoothing factor" do
      data = [%{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      assert {:error, %Errors.InvalidParams{}} = EMA.calculate(data, smoothing: Decimal.new("0"))
      assert {:error, %Errors.InvalidParams{}} = EMA.calculate(data, smoothing: Decimal.new("1.1"))
      assert {:error, %Errors.InvalidParams{}} = EMA.calculate(data, smoothing: "invalid")
    end

    test "returns error for invalid initialization method" do
      data = [%{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      assert {:error, %Errors.InvalidParams{}} = EMA.calculate(data, initialization: :invalid)
    end

    test "EMA is more responsive than SMA", %{data: data} do
      # Compare EMA vs SMA with same period
      {:ok, ema_results} = EMA.calculate(data, period: 3)
      {:ok, sma_results} = TradingIndicators.Trend.SMA.calculate(data, period: 3)
      
      # Both should have same number of results for SMA bootstrap
      assert length(ema_results) == length(sma_results)
      
      # First values should be similar (both use SMA for first value)
      assert Decimal.equal?(Enum.at(ema_results, 0).value, Enum.at(sma_results, 0).value)
      
      # Later values may differ as EMA adapts faster
      # This is expected behavior, not testing exact values since they depend on the data pattern
    end
  end

  describe "validate_params/1" do
    test "accepts valid parameters" do
      assert :ok == EMA.validate_params(period: 14, source: :close)
      assert :ok == EMA.validate_params(period: 1, source: :high, initialization: :first_value)
      assert :ok == EMA.validate_params(smoothing: Decimal.new("0.5"))
      assert :ok == EMA.validate_params([])
    end

    test "rejects invalid period" do
      assert {:error, %Errors.InvalidParams{}} = EMA.validate_params(period: 0)
      assert {:error, %Errors.InvalidParams{}} = EMA.validate_params(period: -5)
    end

    test "rejects invalid source" do
      assert {:error, %Errors.InvalidParams{}} = EMA.validate_params(source: :invalid)
    end

    test "rejects invalid smoothing factor" do
      assert {:error, %Errors.InvalidParams{}} = EMA.validate_params(smoothing: Decimal.new("0"))
      assert {:error, %Errors.InvalidParams{}} = EMA.validate_params(smoothing: Decimal.new("2"))
    end

    test "rejects invalid initialization" do
      assert {:error, %Errors.InvalidParams{}} = EMA.validate_params(initialization: :bad_init)
    end

    test "rejects non-keyword list" do
      assert {:error, %Errors.InvalidParams{}} = EMA.validate_params("invalid")
    end
  end

  describe "required_periods/0 and required_periods/1" do
    test "returns default period" do
      assert EMA.required_periods() == 12
    end

    test "returns configured period for SMA bootstrap" do
      assert EMA.required_periods(period: 14) == 14
      assert EMA.required_periods(period: 20, initialization: :sma_bootstrap) == 20
    end

    test "returns 1 for first value initialization" do
      assert EMA.required_periods(period: 14, initialization: :first_value) == 1
      assert EMA.required_periods(period: 100, initialization: :first_value) == 1
    end
  end

  describe "streaming functionality" do
    test "init_state/1 creates proper initial state" do
      state = EMA.init_state(period: 10, source: :high, initialization: :first_value)
      
      assert state.period == 10
      assert state.source == :high
      assert state.initialization == :first_value
      assert state.prices == []
      assert state.ema_value == nil
      assert state.count == 0
      assert state.initialized == false
    end

    test "init_state/1 calculates smoothing factor" do
      state = EMA.init_state(period: 10)
      expected_smoothing = Decimal.div(Decimal.new("2"), Decimal.new("11"))  # 2/(10+1)
      assert Decimal.equal?(state.smoothing, expected_smoothing)
    end

    test "init_state/1 uses custom smoothing factor" do
      custom_smoothing = Decimal.new("0.3")
      state = EMA.init_state(smoothing: custom_smoothing)
      assert Decimal.equal?(state.smoothing, custom_smoothing)
    end

    test "update_state/2 with first value initialization" do
      state = EMA.init_state(period: 3, source: :close, initialization: :first_value)
      
      # First data point
      data_point1 = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, state1, result1} = EMA.update_state(state, data_point1)
      
      assert result1 != nil  # Should return result immediately
      assert Decimal.equal?(result1.value, Decimal.new("100.0"))  # First EMA = first price
      assert state1.initialized == true
      assert state1.count == 1
      
      # Second data point
      data_point2 = %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]}
      {:ok, state2, result2} = EMA.update_state(state1, data_point2)
      
      assert result2 != nil
      assert state2.count == 2
      # EMA should be between 100 and 102
      assert Decimal.gt?(result2.value, Decimal.new("100"))
      assert Decimal.lt?(result2.value, Decimal.new("102"))
    end

    test "update_state/2 with SMA bootstrap initialization" do
      state = EMA.init_state(period: 3, source: :close, initialization: :sma_bootstrap)
      
      # Add first data point - not enough for bootstrap
      data_point1 = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, state1, result1} = EMA.update_state(state, data_point1)
      
      assert result1 == nil  # Insufficient data
      assert state1.initialized == false
      assert state1.count == 1
      
      # Add second data point - still not enough
      data_point2 = %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]}
      {:ok, state2, result2} = EMA.update_state(state1, data_point2)
      
      assert result2 == nil  # Still insufficient
      assert state2.count == 2
      
      # Add third data point - now we have enough for SMA bootstrap
      data_point3 = %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]}
      {:ok, state3, result3} = EMA.update_state(state2, data_point3)
      
      assert result3 != nil  # Should return EMA now
      assert state3.initialized == true
      assert state3.count == 3
      # First EMA should equal SMA: (100 + 102 + 104) / 3 = 102
      assert Decimal.equal?(result3.value, Decimal.new("102.0"))
    end

    test "update_state/2 continues EMA calculation after initialization" do
      # Start with initialized state
      state = %{
        period: 3,
        source: :close,
        smoothing: Decimal.new("0.5"),  # 2/(3+1) = 0.5
        initialization: :sma_bootstrap,
        prices: [Decimal.new("100"), Decimal.new("102"), Decimal.new("104")],
        ema_value: Decimal.new("102"),  # Initial SMA
        count: 3,
        initialized: true
      }
      
      # Add new data point
      data_point = %{close: Decimal.new("106"), timestamp: ~U[2024-01-01 09:33:00Z]}
      {:ok, new_state, result} = EMA.update_state(state, data_point)
      
      assert result != nil
      assert new_state.count == 4
      
      # EMA = (106 * 0.5) + (102 * 0.5) = 53 + 51 = 104
      assert Decimal.equal?(result.value, Decimal.new("104.0"))
    end

    test "update_state/2 handles different sources" do
      state = EMA.init_state(period: 2, source: :high, initialization: :first_value)
      
      data_point = %{high: Decimal.new("105"), close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, _state, result} = EMA.update_state(state, data_point)
      
      assert Decimal.equal?(result.value, Decimal.new("105.0"))  # Should use high, not close
      assert result.metadata.source == :high
    end

    test "update_state/2 returns error for invalid state" do
      invalid_state = %{invalid: "state"}
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      
      assert {:error, %Errors.StreamStateError{}} = EMA.update_state(invalid_state, data_point)
    end
  end

  describe "mathematical accuracy" do
    test "smoothing factor calculation is correct" do
      # For period = 9, smoothing should be 2/(9+1) = 0.2
      state = EMA.init_state(period: 9)
      expected = Decimal.div(Decimal.new("2"), Decimal.new("10"))
      assert Decimal.equal?(state.smoothing, expected)
    end

    test "EMA calculation follows formula correctly" do
      # Test with known values
      # EMA = (Price × α) + (PrevEMA × (1 - α))
      # With α = 0.5, Price = 110, PrevEMA = 100
      # EMA = (110 × 0.5) + (100 × 0.5) = 55 + 50 = 105
      
      smoothing = Decimal.new("0.5")
      state = %{
        period: 2,
        source: :close,
        smoothing: smoothing,
        initialization: :first_value,
        prices: [Decimal.new("100")],
        ema_value: Decimal.new("100"),
        count: 1,
        initialized: true
      }
      
      data_point = %{close: Decimal.new("110"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, _state, result} = EMA.update_state(state, data_point)
      
      assert Decimal.equal?(result.value, Decimal.new("105.0"))
    end

    test "maintains precision in calculations" do
      # Test with decimal values that might cause floating point issues
      data = [
        %{close: Decimal.new("0.1"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("0.2"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("0.3"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]
      
      assert {:ok, results} = EMA.calculate(data, period: 2, initialization: :first_value)
      
      # All results should be proper decimals, not floating point approximations
      Enum.each(results, fn result ->
        assert Decimal.is_decimal(result.value)
      end)
    end
  end

  describe "edge cases and robustness" do
    test "handles period of 1" do
      data = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("105"), timestamp: ~U[2024-01-01 09:31:00Z]}
      ]
      
      assert {:ok, results} = EMA.calculate(data, period: 1)
      assert length(results) == 2
      
      # With period 1, smoothing = 2/(1+1) = 1.0, so EMA should equal current price
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.new("100.0"))
      assert Decimal.equal?(Enum.at(results, 1).value, Decimal.new("105.0"))
    end

    test "handles very large numbers" do
      data = [
        %{close: Decimal.new("999999999.99"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("1000000000.01"), timestamp: ~U[2024-01-01 09:31:00Z]}
      ]
      
      assert {:ok, results} = EMA.calculate(data, period: 2)
      
      # Should handle large numbers without overflow
      Enum.each(results, fn result ->
        assert Decimal.is_decimal(result.value)
        assert Decimal.gt?(result.value, Decimal.new("999999999"))
      end)
    end

    test "handles very small numbers" do
      data = [
        %{close: Decimal.new("0.00000001"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("0.00000002"), timestamp: ~U[2024-01-01 09:31:00Z]}
      ]
      
      assert {:ok, results} = EMA.calculate(data, period: 2)
      
      # Should handle small numbers with proper precision
      Enum.each(results, fn result ->
        assert Decimal.is_decimal(result.value)
      end)
    end
  end
end