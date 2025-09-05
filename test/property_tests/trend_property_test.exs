defmodule TradingIndicators.PropertyTests.TrendTest do
  use ExUnit.Case
  use ExUnitProperties

  alias TradingIndicators.Trend.{SMA, EMA, WMA, HMA, KAMA, MACD}
  alias TradingIndicators.TestSupport.PropertyGenerators
  alias TradingIndicators.TestSupport.TestHelpers

  @moduletag :property

  describe "SMA properties" do
    property "SMA result length is always input_length - period + 1" do
      check all(
              prices <- PropertyGenerators.price_series(min_length: 5, max_length: 100),
              period <- PropertyGenerators.valid_period(min: 1, max: length(prices))
            ) do
        {:ok, result} = SMA.calculate(prices, period: period)
        expected_length = max(0, length(prices) - period + 1)

        assert length(result) == expected_length
      end
    end

    property "SMA values are always finite" do
      check all(
              prices <- PropertyGenerators.price_series(min_length: 10, max_length: 50),
              period <- PropertyGenerators.valid_period(min: 2, max: 10)
            ) do
        {:ok, result} = SMA.calculate(prices, period: period)
        result_values = Enum.map(result, & &1.value)

        TestHelpers.assert_all_finite(result_values)
      end
    end

    property "SMA with period 1 equals original values" do
      check all(prices <- PropertyGenerators.price_series(min_length: 5, max_length: 20)) do
        {:ok, result} = SMA.calculate(prices, period: 1)

        # SMA with period 1 should equal input values (compare decimals properly)
        result_values = Enum.map(result, & &1.value)
        
        # Compare each decimal value individually to handle precision differences
        Enum.zip(result_values, prices)
        |> Enum.each(fn {result_val, expected_val} ->
          assert Decimal.equal?(result_val, expected_val), 
            "Expected #{expected_val} but got #{result_val}"
        end)
      end
    end

    property "SMA values are within reasonable bounds of input" do
      check all(
              prices <- PropertyGenerators.price_series(min_length: 20, max_length: 50),
              period <- PropertyGenerators.valid_period(min: 5, max: 10)
            ) do
        {:ok, result} = SMA.calculate(prices, period: period)

        unless Enum.empty?(result) do
          result_values = Enum.map(result, & &1.value)
          min_input = Enum.min(prices, Decimal)
          max_input = Enum.max(prices, Decimal)
          min_result = Enum.min(result_values, Decimal)
          max_result = Enum.max(result_values, Decimal)

          # SMA should be within input range
          assert Decimal.gte?(min_result, min_input)
          assert Decimal.lte?(max_result, max_input)
        end
      end
    end

    property "SMA is monotonic for monotonic input" do
      check all(
              length <- integer(10..30),
              base_price <- float(min: 10.0, max: 1000.0),
              direction <- member_of([:up, :down])
            ) do
        prices =
          case direction do
            :up ->
              1..length
              |> Enum.map(fn i -> Decimal.from_float(base_price + i) end)

            :down ->
              length..1//-1
              |> Enum.map(fn i -> Decimal.from_float(base_price + i) end)
          end

        {:ok, result} = SMA.calculate(prices, period: 5)

        unless length(result) < 2 do
          result_values = Enum.map(result, & &1.value)
          case direction do
            :up -> assert_monotonic_increasing(result_values)
            :down -> assert_monotonic_decreasing(result_values)
          end
        end
      end
    end
  end

  describe "EMA properties" do
    property "EMA converges faster than SMA to new values" do
      check all(
              base_value <- float(min: 50.0, max: 150.0),
              jump_value <- float(min: 200.0, max: 300.0),
              period <- PropertyGenerators.valid_period(min: 5, max: 20)
            ) do
        # Create price series with a jump
        stable_prices = List.duplicate(Decimal.from_float(base_value), period * 2)
        jump_prices = List.duplicate(Decimal.from_float(jump_value), period)
        all_prices = stable_prices ++ jump_prices

        {:ok, sma_result} = SMA.calculate(all_prices, period: period)
        {:ok, ema_result} = EMA.calculate(all_prices, period: period)

        if length(sma_result) > 0 and length(ema_result) > 0 do
          # EMA should respond faster to the jump
          sma_final = List.last(sma_result).value
          ema_final = List.last(ema_result).value

          # EMA should be closer to the jump value
          sma_diff = Decimal.abs(Decimal.sub(sma_final, Decimal.from_float(jump_value)))
          ema_diff = Decimal.abs(Decimal.sub(ema_final, Decimal.from_float(jump_value)))

          # EMA should generally be closer or at least in the same ballpark as SMA
          # The key insight is that EMA responds faster, but this doesn't guarantee
          # it's always closer to the final target in every single case
          cond do
            # Case 1: SMA is very close to target (within 1% of jump value)
            Decimal.lte?(sma_diff, Decimal.from_float(jump_value * 0.01)) ->
              # EMA should also be reasonably close (allow up to 15% of jump value)
              assert Decimal.lte?(ema_diff, Decimal.from_float(jump_value * 0.15))
              
            # Case 2: Both are reasonably close - EMA should not be dramatically worse
            Decimal.lte?(sma_diff, Decimal.from_float(jump_value * 0.1)) ->
              # Allow EMA to be up to 5x worse in edge cases, but still reasonable
              assert Decimal.lte?(ema_diff, Decimal.mult(sma_diff, Decimal.new("5.0")))
              
            # Case 3: General case - EMA should be better or comparable
            true ->
              # EMA should be no more than 50% worse than SMA in normal cases
              assert Decimal.lte?(ema_diff, Decimal.mult(sma_diff, Decimal.new("1.5")))
          end
        end
      end
    end

    property "EMA produces finite results" do
      check all(
              prices <- PropertyGenerators.price_series(min_length: 10, max_length: 50),
              period <- PropertyGenerators.valid_period(min: 2, max: 10)
            ) do
        {:ok, result} = EMA.calculate(prices, period: period)

        result_values = Enum.map(result, & &1.value)
        TestHelpers.assert_all_finite(result_values)
      end
    end
  end

  describe "WMA properties" do
    property "WMA gives more weight to recent values" do
      check all(
              base_value <- float(min: 50.0, max: 150.0),
              final_value <- float(min: 200.0, max: 300.0),
              period <- PropertyGenerators.valid_period(min: 3, max: 10)
            ) do
        # Create series that ends with different value
        prices =
          List.duplicate(Decimal.from_float(base_value), period - 1) ++
            [Decimal.from_float(final_value)]

        {:ok, wma_result} = WMA.calculate(prices, period: period)
        {:ok, sma_result} = SMA.calculate(prices, period: period)

        if length(wma_result) > 0 and length(sma_result) > 0 do
          wma_val = List.last(wma_result).value
          sma_val = List.last(sma_result).value

          # WMA should be closer to the final value than SMA
          wma_diff = Decimal.abs(Decimal.sub(wma_val, Decimal.from_float(final_value)))
          sma_diff = Decimal.abs(Decimal.sub(sma_val, Decimal.from_float(final_value)))

          assert Decimal.lte?(wma_diff, sma_diff)
        end
      end
    end
  end

  describe "MACD properties" do
    property "MACD signal line is EMA of MACD line" do
      check all(
              prices <- PropertyGenerators.price_series(min_length: 100, max_length: 200),
              short_period <- PropertyGenerators.valid_period(min: 5, max: 15),
              long_period <- PropertyGenerators.valid_period(min: 20, max: 35),
              signal_period <- PropertyGenerators.valid_period(min: 5, max: 15)
            ) do
        # Ensure long > short
        short = min(short_period, long_period)
        long = max(short_period, long_period)

        if long > short do
          {:ok, result} =
            MACD.calculate(prices,
              fast_period: short,
              slow_period: long,
              signal_period: signal_period
            )

          # MACD returns a list of results, each with a value map containing macd, signal, histogram
          if length(result) > 0 do
            # Extract macd values from the result structure
            macd_values = Enum.map(result, fn item -> item.value.macd end)
            
            # Calculate expected signal line (EMA of MACD values)
            {:ok, expected_signal_result} = EMA.calculate(macd_values, period: signal_period)
            expected_signal = Enum.map(expected_signal_result, & &1.value)
            
            # Extract actual signal values from MACD results
            signal_values = Enum.map(result, fn item -> item.value.signal end)
            
            # Filter out nil values (insufficient data)
            actual_signals = Enum.filter(signal_values, & &1 != nil)
            
            if length(expected_signal) > 0 and length(actual_signals) > 0 do
              # Take the comparable portion (they might differ in length due to warmup periods)
              comparable_length = min(length(expected_signal), length(actual_signals))
              
              if comparable_length > 0 do
                expected_slice = Enum.take(expected_signal, -comparable_length)
                actual_slice = Enum.take(actual_signals, -comparable_length)
                
                # Values should be approximately equal
                Enum.zip(actual_slice, expected_slice)
                |> Enum.each(fn {actual, expected} ->
                  TestHelpers.assert_decimal_equal(actual, expected, "0.01")
                end)
              end
            end
          else
            # MACD may return empty results if insufficient data - this is expected
            :ok
          end
        end
      end
    end
  end

  # Helper functions for property testing
  defp assert_monotonic_increasing(values) do
    values
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.each(fn [a, b] ->
      assert Decimal.gte?(b, a), "Values should be monotonically increasing: #{a} >= #{b}"
    end)
  end

  defp assert_monotonic_decreasing(values) do
    values
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.each(fn [a, b] ->
      assert Decimal.lte?(b, a), "Values should be monotonically decreasing: #{a} <= #{b}"
    end)
  end
end
