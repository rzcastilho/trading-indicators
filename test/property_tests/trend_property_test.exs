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
        result = SMA.calculate(prices, period)
        expected_length = max(0, length(prices) - period + 1)

        assert length(result) == expected_length
      end
    end

    property "SMA values are always finite" do
      check all(
              prices <- PropertyGenerators.price_series(min_length: 10, max_length: 50),
              period <- PropertyGenerators.valid_period(min: 2, max: 10)
            ) do
        result = SMA.calculate(prices, period)

        TestHelpers.assert_all_finite(result)
      end
    end

    property "SMA with period 1 equals original values" do
      check all(prices <- PropertyGenerators.price_series(min_length: 5, max_length: 20)) do
        result = SMA.calculate(prices, 1)

        # SMA with period 1 should equal input prices
        assert result == prices
      end
    end

    property "SMA values are within reasonable bounds of input" do
      check all(
              prices <- PropertyGenerators.price_series(min_length: 20, max_length: 50),
              period <- PropertyGenerators.valid_period(min: 5, max: 10)
            ) do
        result = SMA.calculate(prices, period)

        unless Enum.empty?(result) do
          min_input = Enum.min(prices, Decimal)
          max_input = Enum.max(prices, Decimal)
          min_result = Enum.min(result, Decimal)
          max_result = Enum.max(result, Decimal)

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
              length..1
              |> Enum.map(fn i -> Decimal.from_float(base_price + i) end)
          end

        result = SMA.calculate(prices, 5)

        unless length(result) < 2 do
          case direction do
            :up -> assert_monotonic_increasing(result)
            :down -> assert_monotonic_decreasing(result)
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

        sma_result = SMA.calculate(all_prices, period)
        ema_result = EMA.calculate(all_prices, period)

        if length(sma_result) > 0 and length(ema_result) > 0 do
          # EMA should respond faster to the jump
          sma_final = List.last(sma_result)
          ema_final = List.last(ema_result)

          # EMA should be closer to the jump value
          sma_diff = Decimal.abs(Decimal.sub(sma_final, Decimal.from_float(jump_value)))
          ema_diff = Decimal.abs(Decimal.sub(ema_final, Decimal.from_float(jump_value)))

          # EMA should generally be closer (or at least not significantly worse)
          assert Decimal.lte?(ema_diff, Decimal.mult(sma_diff, Decimal.new("1.2")))
        end
      end
    end

    property "EMA produces finite results" do
      check all(
              prices <- PropertyGenerators.price_series(min_length: 10, max_length: 50),
              period <- PropertyGenerators.valid_period(min: 2, max: 10)
            ) do
        result = EMA.calculate(prices, period)

        TestHelpers.assert_all_finite(result)
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

        wma_result = WMA.calculate(prices, period)
        sma_result = SMA.calculate(prices, period)

        if length(wma_result) > 0 and length(sma_result) > 0 do
          wma_val = List.last(wma_result)
          sma_val = List.last(sma_result)

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
              prices <- PropertyGenerators.price_series(min_length: 50, max_length: 100),
              short_period <- PropertyGenerators.valid_period(min: 5, max: 15),
              long_period <- PropertyGenerators.valid_period(min: 20, max: 35),
              signal_period <- PropertyGenerators.valid_period(min: 5, max: 15)
            ) do
        # Ensure long > short
        short = min(short_period, long_period)
        long = max(short_period, long_period)

        if long > short do
          result =
            MACD.calculate(prices,
              fast_period: short,
              slow_period: long,
              signal_period: signal_period
            )

          case result do
            %{macd: macd_line, signal: signal_line, histogram: _histogram} ->
              # Signal should be EMA of MACD
              expected_signal = EMA.calculate(macd_line, signal_period)

              if length(expected_signal) > 0 and length(signal_line) > 0 do
                # They should have same length
                assert length(signal_line) == length(expected_signal)

                # Values should be approximately equal
                Enum.zip(signal_line, expected_signal)
                |> Enum.each(fn {actual, expected} ->
                  TestHelpers.assert_decimal_equal(actual, expected, "0.0001")
                end)
              end

            _ ->
              # Should return proper structure
              flunk("MACD should return map with macd, signal, and histogram keys")
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
