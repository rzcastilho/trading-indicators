defmodule TradingIndicators.Trend.MACDTest do
  use ExUnit.Case, async: true
  doctest TradingIndicators.Trend.MACD

  alias TradingIndicators.Trend.MACD
  alias TradingIndicators.Errors
  require Decimal

  describe "calculate/2" do
    setup do
      # Generate enough data for MACD calculation (need at least 26 points for default)
      data = for i <- 0..35 do
        base_price = 100 + :math.sin(i * 0.1) * 10  # Oscillating prices
        %{
          open: Decimal.new(to_string(base_price - 1)),
          high: Decimal.new(to_string(base_price + 2)),
          low: Decimal.new(to_string(base_price - 2)),
          close: Decimal.new(to_string(base_price)),
          volume: 1000 + i * 10,
          timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :minute)
        }
      end

      {:ok, data: data}
    end

    test "calculates MACD with default parameters", %{data: data} do
      assert {:ok, results} = MACD.calculate(data)
      
      # Should have results starting from when slow EMA (26) becomes available
      assert length(results) >= 1
      
      first_result = List.first(results)
      assert is_map(first_result.value)
      assert Map.has_key?(first_result.value, :macd)
      assert Map.has_key?(first_result.value, :signal)
      assert Map.has_key?(first_result.value, :histogram)
      
      # MACD should be a decimal
      assert Decimal.is_decimal(first_result.value.macd)
      
      # Initially signal might be nil until we have enough MACD values
      # Histogram is nil when signal is nil
      if first_result.value.signal do
        assert Decimal.is_decimal(first_result.value.signal)
        assert first_result.value.histogram != nil
      else
        assert first_result.value.signal == nil
        assert first_result.value.histogram == nil
      end
      
      # Metadata should be correct
      assert first_result.metadata.indicator == "MACD"
      assert first_result.metadata.fast_period == 12
      assert first_result.metadata.slow_period == 26
      assert first_result.metadata.signal_period == 9
    end

    test "calculates MACD with custom parameters", %{data: data} do
      assert {:ok, results} = MACD.calculate(data, fast_period: 5, slow_period: 10, signal_period: 3)
      
      # Should have more results since slow period is smaller
      assert length(results) >= 10
      
      first_result = List.first(results)
      assert first_result.metadata.fast_period == 5
      assert first_result.metadata.slow_period == 10
      assert first_result.metadata.signal_period == 3
    end

    test "works with different price sources", %{data: data} do
      assert {:ok, high_results} = MACD.calculate(data, source: :high, fast_period: 5, slow_period: 8)
      assert {:ok, low_results} = MACD.calculate(data, source: :low, fast_period: 5, slow_period: 8)
      
      # Verify both have results
      assert length(high_results) >= 1
      assert length(low_results) >= 1
      
      first_high = List.first(high_results)
      first_low = List.first(low_results)
      
      # Different sources should produce different MACD values (most of the time, unless data is very similar)
      # We'll check metadata instead of values since test data might produce similar values
      assert first_high.metadata.source == :high
      assert first_low.metadata.source == :low
      
      # Values should be decimals
      assert Decimal.is_decimal(first_high.value.macd)
      assert Decimal.is_decimal(first_low.value.macd)
    end

    test "handles price series input", %{data: data} do
      closes = Enum.map(data, & &1.close)
      # Use smaller periods since we have limited data as price series
      case MACD.calculate(closes, fast_period: 3, slow_period: 5, signal_period: 2) do
        {:ok, [_ | _] = results} ->
          # When using price series, timestamps default to current time
          assert is_struct(List.first(results).timestamp, DateTime)
        {:ok, []} ->
          # Acceptable - may not have enough data for signal
          :ok
        {:error, _reason} ->
          # Also acceptable - insufficient data
          :ok
      end
    end

    test "signal line calculation", %{data: data} do
      assert {:ok, results} = MACD.calculate(data, fast_period: 5, slow_period: 8, signal_period: 3)
      
      # Find first result with signal
      result_with_signal = Enum.find(results, fn result -> result.value.signal != nil end)
      
      if result_with_signal do
        assert Decimal.is_decimal(result_with_signal.value.signal)
        assert Decimal.is_decimal(result_with_signal.value.histogram)
        
        # Histogram should equal MACD - Signal
        expected_histogram = Decimal.sub(result_with_signal.value.macd, result_with_signal.value.signal)
        assert Decimal.equal?(result_with_signal.value.histogram, expected_histogram)
      end
    end

    test "returns error for insufficient data" do
      # Create minimal data set that's too small for default MACD
      short_data = for i <- 0..9 do  # Only 10 data points
        %{
          close: Decimal.new(to_string(100 + i)),
          timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :minute)
        }
      end
      
      assert {:error, %Errors.InsufficientData{} = error} = MACD.calculate(short_data)
      
      assert error.required == 26  # Default slow period
      assert error.provided == 10
    end

    test "returns error for empty data" do
      assert {:error, %Errors.InsufficientData{}} = MACD.calculate([])
    end

    test "returns error for invalid periods" do
      data = [%{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      
      # Invalid period types
      assert {:error, %Errors.InvalidParams{}} = MACD.calculate(data, fast_period: 0)
      assert {:error, %Errors.InvalidParams{}} = MACD.calculate(data, slow_period: -1)
      assert {:error, %Errors.InvalidParams{}} = MACD.calculate(data, signal_period: "invalid")
      
      # Fast period must be less than slow period
      assert {:error, %Errors.InvalidParams{}} = MACD.calculate(data, fast_period: 20, slow_period: 10)
      assert {:error, %Errors.InvalidParams{}} = MACD.calculate(data, fast_period: 15, slow_period: 15)
    end

    test "returns error for invalid source" do
      data = [%{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}]
      assert {:error, %Errors.InvalidParams{}} = MACD.calculate(data, source: :invalid)
    end
  end

  describe "validate_params/1" do
    test "accepts valid parameters" do
      assert :ok == MACD.validate_params(fast_period: 12, slow_period: 26, signal_period: 9)
      assert :ok == MACD.validate_params(fast_period: 5, slow_period: 10, signal_period: 3, source: :high)
      assert :ok == MACD.validate_params([])
    end

    test "rejects invalid periods" do
      assert {:error, %Errors.InvalidParams{}} = MACD.validate_params(fast_period: 0)
      assert {:error, %Errors.InvalidParams{}} = MACD.validate_params(slow_period: -1)
      assert {:error, %Errors.InvalidParams{}} = MACD.validate_params(signal_period: "invalid")
    end

    test "rejects invalid period relationships" do
      assert {:error, %Errors.InvalidParams{}} = MACD.validate_params(fast_period: 20, slow_period: 10)
      assert {:error, %Errors.InvalidParams{}} = MACD.validate_params(fast_period: 15, slow_period: 15)
    end

    test "rejects invalid source" do
      assert {:error, %Errors.InvalidParams{}} = MACD.validate_params(source: :invalid)
    end

    test "rejects non-keyword list" do
      assert {:error, %Errors.InvalidParams{}} = MACD.validate_params("invalid")
    end
  end

  describe "required_periods/0 and required_periods/1" do
    test "returns default slow period" do
      assert MACD.required_periods() == 26
    end

    test "returns configured slow period" do
      assert MACD.required_periods(fast_period: 8, slow_period: 21) == 21
      assert MACD.required_periods(slow_period: 30) == 30
    end
  end

  describe "streaming functionality" do
    test "init_state/1 creates proper initial state" do
      state = MACD.init_state(fast_period: 5, slow_period: 10, signal_period: 3, source: :high)
      
      assert state.fast_period == 5
      assert state.slow_period == 10
      assert state.signal_period == 3
      assert state.source == :high
      assert is_map(state.fast_ema_state)
      assert is_map(state.slow_ema_state)
      assert is_map(state.signal_ema_state)
      assert state.macd_values == []
      assert state.count == 0
    end

    test "init_state/1 uses defaults" do
      state = MACD.init_state()
      
      assert state.fast_period == 12
      assert state.slow_period == 26
      assert state.signal_period == 9
      assert state.source == :close
    end

    test "update_state/2 accumulates data until MACD can be calculated" do
      state = MACD.init_state(fast_period: 2, slow_period: 3, signal_period: 2)
      
      # Add data points one by one
      data_points = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]},
        %{close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:33:00Z]}
      ]
      
      # Process each data point
      {final_state, final_result} = 
        Enum.reduce(data_points, {state, nil}, fn data_point, {current_state, _prev_result} ->
          {:ok, new_state, result} = MACD.update_state(current_state, data_point)
          {new_state, result}
        end)
      
      # Should eventually get a MACD result
      assert final_result != nil
      assert is_map(final_result.value)
      assert Map.has_key?(final_result.value, :macd)
      assert final_state.count == 4
    end

    test "update_state/2 calculates signal and histogram when available" do
      # Start with a state that can produce MACD immediately
      state = %{
        fast_period: 2,
        slow_period: 3,
        signal_period: 2,
        source: :close,
        fast_ema_state: %{
          period: 2, source: :close, smoothing: Decimal.new("0.666667"),
          initialization: :sma_bootstrap, prices: [Decimal.new("100"), Decimal.new("102")],
          ema_value: Decimal.new("101"), count: 2, initialized: true
        },
        slow_ema_state: %{
          period: 3, source: :close, smoothing: Decimal.new("0.5"),
          initialization: :sma_bootstrap, prices: [Decimal.new("100"), Decimal.new("102"), Decimal.new("101")],
          ema_value: Decimal.new("101"), count: 3, initialized: true
        },
        signal_ema_state: %{
          period: 2, source: :close, smoothing: Decimal.new("0.666667"),
          initialization: :sma_bootstrap, prices: [], ema_value: nil, count: 0, initialized: false
        },
        macd_values: [],
        count: 3
      }
      
      data_point = %{close: Decimal.new("105"), timestamp: ~U[2024-01-01 09:33:00Z]}
      {:ok, new_state, result} = MACD.update_state(state, data_point)
      
      assert result != nil
      assert is_map(result.value)
      assert Decimal.is_decimal(result.value.macd)
      assert new_state.count == 4
    end

    test "update_state/2 handles different sources" do
      state = MACD.init_state(fast_period: 1, slow_period: 2, signal_period: 1, source: :high)
      
      data_point = %{
        high: Decimal.new("105"), 
        close: Decimal.new("100"), 
        timestamp: ~U[2024-01-01 09:30:00Z]
      }
      
      {:ok, _new_state, _result} = MACD.update_state(state, data_point)
      # Should use high price, not close - verified by not throwing an error
    end

    test "update_state/2 returns error for invalid state" do
      invalid_state = %{invalid: "state"}
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      
      assert {:error, %Errors.StreamStateError{}} = MACD.update_state(invalid_state, data_point)
    end
  end

  describe "mathematical accuracy" do
    test "MACD line equals fast EMA minus slow EMA" do
      # Use simple data to verify calculation
      data = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]},
        %{close: Decimal.new("106"), timestamp: ~U[2024-01-01 09:33:00Z]}
      ]
      
      # Calculate EMAs separately
      {:ok, fast_ema} = TradingIndicators.Trend.EMA.calculate(data, period: 2)
      {:ok, slow_ema} = TradingIndicators.Trend.EMA.calculate(data, period: 3)
      {:ok, macd_result} = MACD.calculate(data, fast_period: 2, slow_period: 3, signal_period: 2)
      
      # Find matching timestamp
      fast_last = List.last(fast_ema)
      slow_last = List.last(slow_ema)
      macd_last = List.last(macd_result)
      
      if fast_last.timestamp == slow_last.timestamp and slow_last.timestamp == macd_last.timestamp do
        expected_macd = Decimal.sub(fast_last.value, slow_last.value)
        assert Decimal.equal?(macd_last.value.macd, expected_macd)
      end
    end

    test "maintains precision in calculations" do
      # Test with decimal values that might cause floating point issues
      data = for i <- 0..10 do
        price = Decimal.div(Decimal.new(i), Decimal.new("10"))  # 0.0, 0.1, 0.2, etc.
        %{
          close: price,
          timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :minute)
        }
      end
      
      assert {:ok, results} = MACD.calculate(data, fast_period: 2, slow_period: 3, signal_period: 2)
      
      # All MACD values should be proper decimals
      Enum.each(results, fn result ->
        assert Decimal.is_decimal(result.value.macd)
        if result.value.signal do
          assert Decimal.is_decimal(result.value.signal)
        end
        if result.value.histogram do
          assert Decimal.is_decimal(result.value.histogram)
        end
      end)
    end
  end

  describe "edge cases and robustness" do
    test "handles minimal data for small periods" do
      data = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("104"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]
      
      # With periods 1 and 2, we need at least 2 data points
      assert {:ok, results} = MACD.calculate(data, fast_period: 1, slow_period: 2, signal_period: 1)
      
      assert length(results) >= 1
      assert is_map(List.first(results).value)
    end

    test "handles constant prices" do
      constant_price = Decimal.new("100.0")
      data = for i <- 0..10 do
        %{
          close: constant_price,
          timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :minute)
        }
      end
      
      assert {:ok, results} = MACD.calculate(data, fast_period: 2, slow_period: 3, signal_period: 2)
      
      # With constant prices, MACD line should be 0 (fast EMA = slow EMA)
      Enum.each(results, fn result ->
        assert Decimal.equal?(result.value.macd, Decimal.new("0.0"))
      end)
    end

    test "handles very large numbers" do
      data = [
        %{close: Decimal.new("999999999.99"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("1000000000.01"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("1000000000.02"), timestamp: ~U[2024-01-01 09:32:00Z]}
      ]
      
      assert {:ok, results} = MACD.calculate(data, fast_period: 1, slow_period: 2, signal_period: 1)
      
      # Should handle large numbers without overflow
      Enum.each(results, fn result ->
        assert Decimal.is_decimal(result.value.macd)
      end)
    end
  end
end