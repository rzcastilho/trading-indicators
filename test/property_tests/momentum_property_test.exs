defmodule TradingIndicators.PropertyTests.MomentumTest do
  use ExUnit.Case
  use ExUnitProperties

  alias TradingIndicators.Momentum.{RSI, Stochastic, CCI, ROC, WilliamsR}
  alias TradingIndicators.TestSupport.PropertyGenerators
  alias TradingIndicators.TestSupport.TestHelpers

  @moduletag :property

  describe "RSI properties" do
    property "RSI values are always between 0 and 100" do
      check all prices <- PropertyGenerators.price_series(min_length: 20, max_length: 100),
                period <- PropertyGenerators.valid_period(min: 2, max: 30) do
        result = RSI.calculate(prices, period)
        
        Enum.each(result, fn rsi_value ->
          assert Decimal.gte?(rsi_value, Decimal.new("0"))
          assert Decimal.lte?(rsi_value, Decimal.new("100"))
        end)
      end
    end

    property "RSI approaches 100 for consistently rising prices" do
      check all base_price <- float(min: 50.0, max: 100.0),
                rise_amount <- float(min: 1.0, max: 5.0),
                period <- PropertyGenerators.valid_period(min: 14, max: 14) do # Standard RSI period
        
        # Create consistently rising prices
        prices = 1..30
        |> Enum.map(fn i -> 
          Decimal.from_float(base_price + (i * rise_amount))
        end)
        
        result = RSI.calculate(prices, period)
        
        unless Enum.empty?(result) do
          final_rsi = List.last(result)
          # RSI should be high (> 70) for consistently rising prices
          assert Decimal.gt?(final_rsi, Decimal.new("70"))
        end
      end
    end

    property "RSI approaches 0 for consistently falling prices" do
      check all base_price <- float(min: 100.0, max: 200.0),
                fall_amount <- float(min: 1.0, max: 5.0),
                period <- PropertyGenerators.valid_period(min: 14, max: 14) do
        
        # Create consistently falling prices
        prices = 1..30
        |> Enum.map(fn i -> 
          price = base_price - (i * fall_amount)
          Decimal.from_float(max(price, 1.0)) # Prevent negative prices
        end)
        
        result = RSI.calculate(prices, period)
        
        unless Enum.empty?(result) do
          final_rsi = List.last(result)
          # RSI should be low (< 30) for consistently falling prices
          assert Decimal.lt?(final_rsi, Decimal.new("30"))
        end
      end
    end

    property "RSI around 50 for sideways prices" do
      check all base_price <- float(min: 50.0, max: 150.0),
                period <- PropertyGenerators.valid_period(min: 14, max: 14) do
        
        # Create sideways (oscillating) prices
        prices = 1..50
        |> Enum.map(fn i -> 
          variation = :math.sin(i * 0.3) * 2.0 # Small oscillations
          Decimal.from_float(base_price + variation)
        end)
        
        result = RSI.calculate(prices, period)
        
        unless Enum.empty?(result) do
          avg_rsi = result
          |> Enum.map(&Decimal.to_float/1)
          |> Enum.sum()
          |> Kernel./(length(result))
          
          # Average RSI should be near 50 for sideways market
          assert avg_rsi > 40.0 and avg_rsi < 60.0
        end
      end
    end
  end

  describe "Stochastic properties" do
    property "Stochastic %K and %D values are between 0 and 100" do
      check all data <- PropertyGenerators.ohlcv_data(count: 50),
                k_period <- PropertyGenerators.valid_period(min: 5, max: 20),
                d_period <- PropertyGenerators.valid_period(min: 2, max: 10) do
        
        result = Stochastic.calculate(data, k_period: k_period, d_period: d_period)
        
        case result do
          %{k: k_values, d: d_values} ->
            # Check %K values
            Enum.each(k_values, fn k ->
              assert Decimal.gte?(k, Decimal.new("0"))
              assert Decimal.lte?(k, Decimal.new("100"))
            end)
            
            # Check %D values
            Enum.each(d_values, fn d ->
              assert Decimal.gte?(d, Decimal.new("0"))
              assert Decimal.lte?(d, Decimal.new("100"))
            end)
            
          _ -> flunk("Stochastic should return map with k and d keys")
        end
      end
    end

    property "%D is smoothed version of %K" do
      check all data <- PropertyGenerators.ohlcv_data(count: 30),
                k_period <- PropertyGenerators.valid_period(min: 14, max: 14),
                d_period <- PropertyGenerators.valid_period(min: 3, max: 3) do
        
        result = Stochastic.calculate(data, k_period: k_period, d_period: d_period)
        
        case result do
          %{k: k_values, d: d_values} ->
            # %D should generally be less volatile than %K
            # Calculate simple volatility (standard deviation)
            k_volatility = calculate_volatility(k_values)
            d_volatility = calculate_volatility(d_values)
            
            # %D should generally be less volatile (smoothed)
            if k_volatility > 0 do
              assert d_volatility <= k_volatility * 1.2 # Allow some tolerance
            end
            
          _ -> flunk("Stochastic should return proper structure")
        end
      end
    end
  end

  describe "CCI properties" do
    property "CCI can exceed ±100 but typically stays within ±200" do
      check all data <- PropertyGenerators.ohlcv_data(count: 50),
                period <- PropertyGenerators.valid_period(min: 14, max: 20) do
        
        result = CCI.calculate(data, period)
        
        # CCI should produce finite values
        TestHelpers.assert_all_finite(result)
        
        # Most values should be within reasonable bounds
        extreme_values = Enum.count(result, fn cci ->
          Decimal.gt?(Decimal.abs(cci), Decimal.new("300"))
        end)
        
        # Less than 10% should be extremely high
        extreme_ratio = extreme_values / length(result)
        assert extreme_ratio < 0.1
      end
    end
  end

  describe "ROC properties" do
    property "ROC reflects percentage change correctly" do
      check all prices <- PropertyGenerators.price_series(min_length: 20, max_length: 50),
                period <- PropertyGenerators.valid_period(min: 1, max: 10) do
        
        result = ROC.calculate(prices, period)
        
        # Manually verify a few ROC calculations
        if length(prices) > period and length(result) > 0 do
          # Check first calculable ROC value
          current_price = Enum.at(prices, period)
          previous_price = Enum.at(prices, 0)
          expected_roc = Decimal.mult(
            Decimal.div(
              Decimal.sub(current_price, previous_price),
              previous_price
            ),
            Decimal.new("100")
          )
          
          actual_roc = Enum.at(result, 0)
          TestHelpers.assert_decimal_equal(actual_roc, expected_roc, "0.01")
        end
      end
    end

    property "ROC is positive for price increases" do
      check all base_price <- float(min: 50.0, max: 100.0),
                increase_pct <- float(min: 0.05, max: 0.20), # 5% to 20% increase
                period <- PropertyGenerators.valid_period(min: 1, max: 1) do # 1-period ROC
        
        # Create simple two-price series with known increase
        start_price = Decimal.from_float(base_price)
        end_price = Decimal.mult(start_price, Decimal.from_float(1 + increase_pct))
        prices = [start_price, end_price]
        
        result = ROC.calculate(prices, period)
        
        unless Enum.empty?(result) do
          roc_value = List.last(result)
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
      check all data <- PropertyGenerators.ohlcv_data(count: 30),
                period <- PropertyGenerators.valid_period(min: 14, max: 14) do
        
        result = WilliamsR.calculate(data, period)
        
        Enum.each(result, fn wr_value ->
          assert Decimal.gte?(wr_value, Decimal.new("-100"))
          assert Decimal.lte?(wr_value, Decimal.new("0"))
        end)
      end
    end

    property "Williams %R approaches -100 for prices at period lows" do
      check all base_high <- float(min: 100.0, max: 200.0),
                low_price <- float(min: 50.0, max: 99.0),
                period <- PropertyGenerators.valid_period(min: 14, max: 14) do
        
        # Create OHLC data where current close is at period low
        high_prices = List.duplicate(Decimal.from_float(base_high), period)
        low_prices = List.duplicate(Decimal.from_float(low_price), period)
        close_prices = List.duplicate(Decimal.from_float(low_price), period) # Close at low
        
        data = Enum.zip([high_prices, low_prices, close_prices])
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
        
        result = WilliamsR.calculate(data, period)
        
        unless Enum.empty?(result) do
          final_wr = List.last(result)
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
    
    variance = floats
    |> Enum.map(fn x -> :math.pow(x - mean, 2) end)
    |> Enum.sum()
    |> Kernel./(length(floats) - 1)
    
    :math.sqrt(variance)
  end
end