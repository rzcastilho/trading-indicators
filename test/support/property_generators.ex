defmodule TradingIndicators.TestSupport.PropertyGenerators do
  @moduledoc """
  StreamData generators for property-based testing of trading indicators.
  """

  use ExUnitProperties
  import StreamData

  @doc """
  Generates valid OHLCV data with realistic constraints.
  """
  def ohlcv_data(opts \\ []) do
    count = Keyword.get(opts, :count, 50)
    min_price = Keyword.get(opts, :min_price, 10.0)
    max_price = Keyword.get(opts, :max_price, 1000.0)
    
    base_price = float(min: min_price, max: max_price)
    
    gen all base <- base_price,
            variations <- list_of(float(min: -0.1, max: 0.1), length: count) do
      
      base_time = ~U[2024-01-01 09:30:00Z]
      
      variations
      |> Enum.with_index()
      |> Enum.map(fn {variation, i} ->
        # Generate realistic OHLC relationships
        close_price = base * (1 + variation)
        volatility = abs(:rand.normal()) * 0.02 * close_price
        
        open = close_price + (:rand.normal() * 0.005 * close_price)
        high = max(open, close_price) + (abs(:rand.normal()) * volatility)
        low = min(open, close_price) - (abs(:rand.normal()) * volatility)
        volume = trunc(1000 + abs(:rand.normal()) * 5000)
        
        %{
          open: Decimal.from_float(Float.round(open, 2)),
          high: Decimal.from_float(Float.round(high, 2)),
          low: Decimal.from_float(Float.round(low, 2)),
          close: Decimal.from_float(Float.round(close_price, 2)),
          volume: volume,
          timestamp: DateTime.add(base_time, i * 60, :second)
        }
      end)
    end
  end

  @doc """
  Generates valid price series with configurable properties.
  """
  def price_series(opts \\ []) do
    min_length = Keyword.get(opts, :min_length, 1)
    max_length = Keyword.get(opts, :max_length, 100)
    min_price = Keyword.get(opts, :min_price, 1.0)
    max_price = Keyword.get(opts, :max_price, 1000.0)
    
    gen all length <- integer(min_length..max_length),
            prices <- list_of(float(min: min_price, max: max_price), length: length) do
      Enum.map(prices, fn price ->
        Decimal.from_float(Float.round(price, 2))
      end)
    end
  end

  @doc """
  Generates valid periods for indicators.
  """
  def valid_period(opts \\ []) do
    min_period = Keyword.get(opts, :min, 1)
    max_period = Keyword.get(opts, :max, 50)
    integer(min_period..max_period)
  end

  @doc """
  Generates trending price data (upward or downward).
  """
  def trending_prices(direction \\ :up, opts \\ []) do
    length = Keyword.get(opts, :length, 50)
    base_price = Keyword.get(opts, :base_price, 100.0)
    trend_strength = Keyword.get(opts, :trend_strength, 0.01)
    
    gen all noise <- list_of(float(min: -0.02, max: 0.02), length: length) do
      trend_multiplier = case direction do
        :up -> 1
        :down -> -1
      end
      
      noise
      |> Enum.with_index()
      |> Enum.map(fn {n, i} ->
        trend_component = i * trend_strength * trend_multiplier
        price = base_price * (1 + trend_component + n)
        Decimal.from_float(Float.round(price, 2))
      end)
    end
  end

  @doc """
  Generates sideways (ranging) price data.
  """
  def sideways_prices(opts \\ []) do
    length = Keyword.get(opts, :length, 50)
    base_price = Keyword.get(opts, :base_price, 100.0)
    range_pct = Keyword.get(opts, :range_pct, 0.05)
    
    gen all variations <- list_of(float(min: -range_pct, max: range_pct), length: length) do
      Enum.map(variations, fn variation ->
        price = base_price * (1 + variation)
        Decimal.from_float(Float.round(price, 2))
      end)
    end
  end

  @doc """
  Generates volatile price data with high variance.
  """
  def volatile_prices(opts \\ []) do
    length = Keyword.get(opts, :length, 50)
    base_price = Keyword.get(opts, :base_price, 100.0)
    volatility = Keyword.get(opts, :volatility, 0.1)
    
    gen all variations <- list_of(float(min: -volatility, max: volatility), length: length) do
      Enum.map(variations, fn variation ->
        price = base_price * (1 + variation)
        Decimal.from_float(Float.round(max(price, 0.01), 2))
      end)
    end
  end

  @doc """
  Generates volume data correlated with price movements.
  """
  def volume_series(price_changes, opts \\ []) do
    base_volume = Keyword.get(opts, :base_volume, 10_000)
    volume_multiplier = Keyword.get(opts, :volume_multiplier, 2.0)
    
    gen all noise <- list_of(float(min: 0.5, max: 2.0), length: length(price_changes)) do
      price_changes
      |> Enum.zip(noise)
      |> Enum.map(fn {price_change, noise_factor} ->
        # Higher volume on larger price changes
        volume_factor = 1 + (abs(Decimal.to_float(price_change)) * volume_multiplier)
        volume = trunc(base_volume * volume_factor * noise_factor)
        max(volume, 1)
      end)
    end
  end

  @doc """
  Generates parameters for specific indicators.
  """
  def indicator_params(indicator_type) do
    case indicator_type do
      :sma -> 
        gen all period <- valid_period(min: 2, max: 50) do
          %{period: period}
        end
        
      :ema ->
        gen all period <- valid_period(min: 2, max: 50) do
          %{period: period}
        end
        
      :rsi ->
        gen all period <- valid_period(min: 2, max: 30) do
          %{period: period}
        end
        
      :bollinger_bands ->
        gen all period <- valid_period(min: 10, max: 50),
                std_dev <- float(min: 1.0, max: 3.0) do
          %{period: period, std_dev: Decimal.from_float(Float.round(std_dev, 2))}
        end
        
      :stochastic ->
        gen all k_period <- valid_period(min: 5, max: 20),
                d_period <- valid_period(min: 2, max: 10) do
          %{k_period: k_period, d_period: d_period}
        end
        
      :macd ->
        gen all short <- valid_period(min: 5, max: 15),
                long <- valid_period(min: 20, max: 35),
                signal <- valid_period(min: 5, max: 15) do
          # Ensure long > short
          short_period = min(short, long)
          long_period = max(short, long)
          %{short_period: short_period, long_period: long_period, signal_period: signal}
        end
        
      _ ->
        # Generic parameters
        gen all period <- valid_period() do
          %{period: period}
        end
    end
  end

  @doc """
  Generates edge case data for stress testing.
  """
  def edge_case_data do
    one_of([
      # Empty data
      constant([]),
      
      # Single value
      gen all value <- float(min: 0.01, max: 1000.0) do
        [Decimal.from_float(Float.round(value, 2))]
      end,
      
      # Two values
      gen all v1 <- float(min: 0.01, max: 1000.0),
              v2 <- float(min: 0.01, max: 1000.0) do
        [v1, v2] |> Enum.map(&Decimal.from_float(Float.round(&1, 2)))
      end,
      
      # All same values
      gen all value <- float(min: 0.01, max: 1000.0),
              length <- integer(3..20) do
        List.duplicate(Decimal.from_float(Float.round(value, 2)), length)
      end,
      
      # Extreme values
      gen all length <- integer(5..20) do
        extreme_values = [0.01, 999999.99, 0.01, 999999.99]
        Stream.cycle(extreme_values)
        |> Enum.take(length)
        |> Enum.map(&Decimal.from_float/1)
      end,
      
      # Very small differences
      gen all base <- float(min: 100.0, max: 1000.0),
              length <- integer(10..30) do
        0..(length-1)
        |> Enum.map(fn i -> base + (i * 0.0001) end)
        |> Enum.map(&Decimal.from_float(Float.round(&1, 4)))
      end
    ])
  end

  @doc """
  Generates realistic market scenarios for integration testing.
  """
  def market_scenarios do
    one_of([
      # Bull market
      gen all length <- integer(50..200) do
        generate_bull_market(length)
      end,
      
      # Bear market  
      gen all length <- integer(50..200) do
        generate_bear_market(length)
      end,
      
      # Sideways market
      gen all length <- integer(50..200) do
        generate_sideways_market(length)
      end,
      
      # Volatile market
      gen all length <- integer(50..200) do
        generate_volatile_market(length)
      end
    ])
  end

  # Private helper functions
  defp generate_bull_market(length) do
    base_price = 100.0
    
    1..length
    |> Enum.map(fn i ->
      # Overall upward trend with noise
      trend = i * 0.02
      noise = :rand.normal(0, 0.01)
      price = base_price * (1 + trend + noise)
      Decimal.from_float(Float.round(max(price, 0.01), 2))
    end)
  end

  defp generate_bear_market(length) do
    base_price = 100.0
    
    1..length
    |> Enum.map(fn i ->
      # Overall downward trend with noise
      trend = -i * 0.015
      noise = :rand.normal(0, 0.01)
      price = base_price * (1 + trend + noise)
      Decimal.from_float(Float.round(max(price, 0.01), 2))
    end)
  end

  defp generate_sideways_market(length) do
    base_price = 100.0
    range = 0.1
    
    1..length
    |> Enum.map(fn _i ->
      # Oscillating around base price
      variation = :rand.uniform() * range - (range / 2)
      noise = :rand.normal(0, 0.005)
      price = base_price * (1 + variation + noise)
      Decimal.from_float(Float.round(price, 2))
    end)
  end

  defp generate_volatile_market(length) do
    base_price = 100.0
    
    1..length
    |> Enum.map(fn _i ->
      # High volatility with large swings
      variation = :rand.normal(0, 0.05)
      price = base_price * (1 + variation)
      Decimal.from_float(Float.round(max(price, 0.01), 2))
    end)
  end
end