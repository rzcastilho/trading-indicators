defmodule TradingIndicators.PropertyTests.MomentumTest do
  use ExUnit.Case
  use ExUnitProperties

  alias TradingIndicators.Momentum.{RSI, Stochastic, CCI, ROC, WilliamsR}
  alias TradingIndicators.TestSupport.PropertyGenerators
  alias TradingIndicators.TestSupport.TestHelpers

  @moduletag :property

  describe "RSI properties" do
    property "RSI values are always between 0 and 100" do
      check all(
              prices <- PropertyGenerators.price_series(min_length: 20, max_length: 100),
              period <- PropertyGenerators.valid_period(min: 2, max: 30)
            ) do
        case RSI.calculate(prices, period: period) do
          {:ok, result} ->
            result_values = Enum.map(result, & &1.value)
            Enum.each(result_values, fn rsi_value ->
              assert Decimal.gte?(rsi_value, Decimal.new("0"))
              assert Decimal.lte?(rsi_value, Decimal.new("100"))
            end)
            
          {:error, _reason} ->
            # Skip test if insufficient data - this is expected behavior
            :ok
        end
      end
    end

    property "RSI approaches 100 for consistently rising prices" do
      check all(
              base_price <- float(min: 50.0, max: 100.0),
              rise_amount <- float(min: 1.0, max: 5.0),
              # Standard RSI period
              period <- PropertyGenerators.valid_period(min: 14, max: 14)
            ) do
        # Create consistently rising prices
        prices =
          1..30
          |> Enum.map(fn i ->
            Decimal.from_float(base_price + i * rise_amount)
          end)

        {:ok, result} = RSI.calculate(prices, period: period)

        unless Enum.empty?(result) do
          final_rsi = List.last(result).value
          # RSI should be high (> 70) for consistently rising prices
          assert Decimal.gt?(final_rsi, Decimal.new("70"))
        end
      end
    end

    property "RSI approaches 0 for consistently falling prices" do
      check all(
              base_price <- float(min: 100.0, max: 200.0),
              fall_amount <- float(min: 1.0, max: 5.0),
              period <- PropertyGenerators.valid_period(min: 14, max: 14)
            ) do
        # Create consistently falling prices
        prices =
          1..30
          |> Enum.map(fn i ->
            price = base_price - i * fall_amount
            # Prevent negative prices
            Decimal.from_float(max(price, 1.0))
          end)

        {:ok, result} = RSI.calculate(prices, period: period)

        unless Enum.empty?(result) do
          final_rsi = List.last(result).value
          # RSI should be low (< 30) for consistently falling prices
          assert Decimal.lt?(final_rsi, Decimal.new("30"))
        end
      end
    end

    property "RSI around 50 for sideways prices" do
      check all(
              base_price <- float(min: 50.0, max: 150.0),
              period <- PropertyGenerators.valid_period(min: 14, max: 14)
            ) do
        # Create sideways (oscillating) prices
        prices =
          1..50
          |> Enum.map(fn i ->
            # Small oscillations
            variation = :math.sin(i * 0.3) * 2.0
            Decimal.from_float(base_price + variation)
          end)

        {:ok, result} = RSI.calculate(prices, period: period)

        unless Enum.empty?(result) do
          result_values = Enum.map(result, & &1.value)
          avg_rsi =
            result_values
            |> Enum.map(&Decimal.to_float/1)
            |> Enum.sum()
            |> Kernel./(length(result_values))

          # Average RSI should be reasonably near 50 for sideways market (allow wider tolerance)
          # RSI can vary quite a bit even in sideways markets due to short-term fluctuations
          assert avg_rsi > 25.0 and avg_rsi < 75.0
        end
      end
    end
  end

  describe "Stochastic properties" do
    property "Stochastic %K and %D values are between 0 and 100" do
      check all(
              data <- PropertyGenerators.ohlcv_data(count: 50),
              k_period <- PropertyGenerators.valid_period(min: 5, max: 20),
              d_period <- PropertyGenerators.valid_period(min: 2, max: 10)
            ) do
        {:ok, result} = Stochastic.calculate(data, k_period: k_period, d_period: d_period)

        # Stochastic returns a list of results, each with value.k and value.d
        unless Enum.empty?(result) do
          Enum.each(result, fn stoch_result ->
            k_value = stoch_result.value.k
            d_value = stoch_result.value.d
            
            # Check %K values
            assert Decimal.gte?(k_value, Decimal.new("0"))
            assert Decimal.lte?(k_value, Decimal.new("100"))
            
            # Check %D values (may be nil if insufficient data)
            if d_value != nil do
              assert Decimal.gte?(d_value, Decimal.new("0"))
              assert Decimal.lte?(d_value, Decimal.new("100"))
            end
          end)
        end
      end
    end

    property "%D is smoothed version of %K" do
      check all(
              data <- PropertyGenerators.ohlcv_data(count: 30),
              k_period <- PropertyGenerators.valid_period(min: 14, max: 14),
              d_period <- PropertyGenerators.valid_period(min: 3, max: 3)
            ) do
        {:ok, result} = Stochastic.calculate(data, k_period: k_period, d_period: d_period)

        # Extract K and D values from the result structure
        unless Enum.empty?(result) do
          k_values = Enum.map(result, fn item -> item.value.k end)
          d_values = Enum.map(result, fn item -> item.value.d end) |> Enum.filter(& &1 != nil)
          
          # Only test volatility if we have enough data points
          if length(k_values) > 2 and length(d_values) > 2 do
            # %D should generally be less volatile than %K
            # Calculate simple volatility (standard deviation)
            k_volatility = calculate_volatility(k_values)
            d_volatility = calculate_volatility(d_values)

            # %D should generally be less volatile (smoothed)
            if k_volatility > 0 do
              # Allow some tolerance
              assert d_volatility <= k_volatility * 1.2
            end
          end
        end
      end
    end
  end

  describe "CCI properties" do
    property "CCI can exceed ±100 but typically stays within ±200" do
      check all(
              data <- PropertyGenerators.ohlcv_data(count: 50),
              period <- PropertyGenerators.valid_period(min: 14, max: 20)
            ) do
        {:ok, result} = CCI.calculate(data, period: period)

        # CCI should produce finite values
        result_values = Enum.map(result, & &1.value)
        TestHelpers.assert_all_finite(result_values)

        # Most values should be within reasonable bounds
        extreme_values =
          Enum.count(result_values, fn cci ->
            Decimal.gt?(Decimal.abs(cci), Decimal.new("300"))
          end)

        # Less than 10% should be extremely high
        extreme_ratio = extreme_values / length(result_values)
        assert extreme_ratio < 0.1
      end
    end
  end

  describe "ROC properties" do
    property "ROC reflects percentage change correctly" do
      check all(
              prices <- PropertyGenerators.price_series(min_length: 20, max_length: 50),
              period <- PropertyGenerators.valid_period(min: 1, max: 10)
            ) do
        {:ok, result} = ROC.calculate(prices, period: period)

        # Manually verify a few ROC calculations
        if length(prices) > period and length(result) > 0 do
          # Check first calculable ROC value
          current_price = Enum.at(prices, period)
          previous_price = Enum.at(prices, 0)

          expected_roc =
            Decimal.mult(
              Decimal.div(
                Decimal.sub(current_price, previous_price),
                previous_price
              ),
              Decimal.new("100")
            )

          actual_roc = Enum.at(result, 0).value
          TestHelpers.assert_decimal_equal(actual_roc, expected_roc, "0.01")
        end
      end
    end

    property "ROC is positive for price increases" do
      check all(
              base_price <- float(min: 50.0, max: 100.0),
              # 5% to 20% increase
              increase_pct <- float(min: 0.05, max: 0.20),
              # 1-period ROC
              period <- PropertyGenerators.valid_period(min: 1, max: 1)
            ) do
        # Create simple two-price series with known increase
        start_price = Decimal.from_float(base_price)
        end_price = Decimal.mult(start_price, Decimal.from_float(1 + increase_pct))
        prices = [start_price, end_price]

        {:ok, result} = ROC.calculate(prices, period: period)

        unless Enum.empty?(result) do
          roc_value = List.last(result).value
          assert Decimal.gt?(roc_value, Decimal.new("0"))

          # Should be approximately equal to the increase percentage * 100
          expected_roc = Decimal.from_float(increase_pct * 100)
          TestHelpers.assert_decimal_equal(roc_value, expected_roc, "0.1")
        end
      end
    end
  end

  describe "Williams %R properties" do
    property "Williams %R values are between -100 and 0" do
      check all(
              data <- PropertyGenerators.ohlcv_data(count: 30),
              period <- PropertyGenerators.valid_period(min: 14, max: 14)
            ) do
        {:ok, result} = WilliamsR.calculate(data, period: period)

        result_values = Enum.map(result, & &1.value)
        Enum.each(result_values, fn wr_value ->
          assert Decimal.gte?(wr_value, Decimal.new("-100"))
          assert Decimal.lte?(wr_value, Decimal.new("0"))
        end)
      end
    end

    property "Williams %R approaches -100 for prices at period lows" do
      check all(
              base_high <- float(min: 100.0, max: 200.0),
              low_price <- float(min: 50.0, max: 99.0),
              period <- PropertyGenerators.valid_period(min: 14, max: 14)
            ) do
        # Create OHLC data where current close is at period low
        high_prices = List.duplicate(Decimal.from_float(base_high), period)
        low_prices = List.duplicate(Decimal.from_float(low_price), period)
        # Close at low
        close_prices = List.duplicate(Decimal.from_float(low_price), period)

        data =
          Enum.zip([high_prices, low_prices, close_prices])
          |> Enum.with_index()
          |> Enum.map(fn {{high, low, close}, i} ->
            %{
              open: close,
              high: high,
              low: low,
              close: close,
              volume: 1000,
              timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i * 60, :second)
            }
          end)

        {:ok, result} = WilliamsR.calculate(data, period: period)

        unless Enum.empty?(result) do
          final_wr = List.last(result).value
          # Should be very close to -100 when close is at period low
          assert Decimal.lt?(final_wr, Decimal.new("-90"))
        end
      end
    end
  end

  # Helper functions
  defp calculate_volatility(values) when length(values) < 2, do: 0.0

  defp calculate_volatility(values) do
    floats = Enum.map(values, &Decimal.to_float/1)
    mean = Enum.sum(floats) / length(floats)

    variance =
      floats
      |> Enum.map(fn x -> :math.pow(x - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(floats) - 1)

    :math.sqrt(variance)
  end
end
