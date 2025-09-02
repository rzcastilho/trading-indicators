defmodule TradingIndicators.IntegrationTests.ComprehensiveIntegrationTest do
  use ExUnit.Case
  
  alias TradingIndicators.TestSupport.{IntegrationHelpers, DataGenerator}
  alias TradingIndicators.{Pipeline, Streaming}

  @moduletag :integration

  describe "Cross-module indicator integration" do
    test "multiple indicators work together on same dataset" do
      data = DataGenerator.sample_ohlcv_data(100)
      
      indicators = %{
        sma_14: {TradingIndicators.Trend.SMA, :calculate, [period: 14]},
        ema_14: {TradingIndicators.Trend.EMA, :calculate, [period: 14]},
        rsi_14: {TradingIndicators.Momentum.RSI, :calculate, [period: 14]},
        bollinger: {TradingIndicators.Volatility.BollingerBands, :calculate, [period: 20, multiplier: Decimal.new("2.0")]},
        macd: {TradingIndicators.Trend.MACD, :calculate, [fast_period: 12, slow_period: 26, signal_period: 9]}
      }
      
      result = IntegrationHelpers.test_indicator_pipeline(data, indicators)
      
      # All individual indicators should succeed
      assert result.individual.sma_14.success
      assert result.individual.ema_14.success
      assert result.individual.rsi_14.success
      assert result.individual.bollinger.success
      assert result.individual.macd.success
      
      # Pipeline should also succeed
      assert result.pipeline.success
      
      # Results should have reasonable lengths
      assert length(result.individual.sma_14.result) > 0
      assert length(result.individual.ema_14.result) > 0
      assert length(result.individual.rsi_14.result) > 0
    end

    test "indicators maintain consistency across different data qualities" do
      scenarios = IntegrationHelpers.create_integration_scenarios()
      
      # Test with normal data
      consistency_result = IntegrationHelpers.validate_cross_indicator_consistency(scenarios.normal_data)
      assert consistency_result.overall_consistent
      
      # Test each scenario
      Enum.each(scenarios, fn {scenario_name, data} ->
        unless Enum.empty?(data) do
          try do
            # Test basic indicators on each scenario
            {:ok, sma_result} = TradingIndicators.Trend.SMA.calculate(data, period: 10)
            {:ok, ema_result} = TradingIndicators.Trend.EMA.calculate(data, period: 10)
            
            # Results should be finite (no NaN or infinite values)
            assert Enum.all?(sma_result, fn result -> not (Decimal.nan?(result.value) or Decimal.inf?(result.value)) end), 
                   "SMA produced non-finite values for #{scenario_name}"
            assert Enum.all?(ema_result, fn result -> not (Decimal.nan?(result.value) or Decimal.inf?(result.value)) end), 
                   "EMA produced non-finite values for #{scenario_name}"
                   
          rescue
            error ->
              # Some scenarios should raise errors (like invalid data)
              assert scenario_name in [:missing_fields, :invalid_ohlc, :empty_data], 
                     "Unexpected error for #{scenario_name}: #{inspect(error)}"
          end
        end
      end)
    end
  end

  describe "Streaming integration" do
    test "streaming maintains consistency with batch calculations" do
      initial_data = DataGenerator.sample_ohlcv_data(50)
      additional_data = DataGenerator.sample_ohlcv_data(25)
      all_data = initial_data ++ additional_data
      
      indicators = %{
        sma_10: {TradingIndicators.Trend.SMA, :calculate, [period: 10]},
        ema_10: {TradingIndicators.Trend.EMA, :calculate, [period: 10]},
        rsi_14: {TradingIndicators.Momentum.RSI, :calculate, [period: 14]}
      }
      
      # Test streaming integration
      streaming_result = IntegrationHelpers.test_streaming_integration(
        initial_data, 
        additional_data, 
        indicators
      )
      
      # Calculate batch results for comparison
      {:ok, sma_batch} = TradingIndicators.Trend.SMA.calculate(all_data, period: 10)
      {:ok, ema_batch} = TradingIndicators.Trend.EMA.calculate(all_data, period: 10)
      {:ok, rsi_batch} = TradingIndicators.Momentum.RSI.calculate(all_data, period: 14)
      
      batch_results = %{
        sma_10: Enum.map(sma_batch, & &1.value),
        ema_10: Enum.map(ema_batch, & &1.value),
        rsi_14: Enum.map(rsi_batch, & &1.value)
      }
      
      # Compare streaming vs batch results
      Enum.each(streaming_result.streaming, fn {indicator, stream_data} ->
        if stream_data.success do
          batch_result = batch_results[indicator]
          stream_result = stream_data.total_results
          
          # Results should have similar length
          length_diff = abs(length(batch_result) - length(stream_result))
          assert length_diff <= 1, "Length difference too large for #{indicator}"
          
          # Last few values should be approximately equal
          if length(batch_result) > 5 and length(stream_result) > 5 do
            batch_last = Enum.take(batch_result, -5)
            stream_last = Enum.take(stream_result, -5)
            
            min_length = min(length(batch_last), length(stream_last))
            batch_subset = Enum.take(batch_last, min_length)
            stream_subset = Enum.take(stream_last, min_length)
            
            Enum.zip(batch_subset, stream_subset)
            |> Enum.each(fn {batch_val, stream_val} ->
              diff = Decimal.abs(Decimal.sub(batch_val, stream_val))
              tolerance = Decimal.mult(batch_val, Decimal.new("0.01")) # 1% tolerance
              
              assert Decimal.lte?(diff, tolerance), 
                     "Streaming result differs significantly from batch for #{indicator}"
            end)
          end
        end
      end)
    end
  end

  describe "Pipeline integration" do
    test "complex pipeline with multiple indicator dependencies" do
      data = DataGenerator.sample_ohlcv_data(100)
      
      pipeline = Pipeline.new()
      |> Pipeline.add_stage(:sma_20, TradingIndicators.Trend.SMA, [period: 20])
      |> Pipeline.add_stage(:ema_12, TradingIndicators.Trend.EMA, [period: 12])
      |> Pipeline.add_stage(:rsi, TradingIndicators.Momentum.RSI, [period: 14])
      |> Pipeline.add_stage(:bollinger, TradingIndicators.Volatility.BollingerBands, [period: 20, multiplier: Decimal.new("2.0")])
      |> Pipeline.add_stage(:macd, TradingIndicators.Trend.MACD, [fast_period: 12, slow_period: 26, signal_period: 9])
      
      {:ok, result} = Pipeline.execute(pipeline, data)
      
      # All indicators should execute successfully
      assert Map.has_key?(result.stage_results, :sma_20)
      assert Map.has_key?(result.stage_results, :ema_12)
      assert Map.has_key?(result.stage_results, :rsi)
      assert Map.has_key?(result.stage_results, :bollinger)
      assert Map.has_key?(result.stage_results, :macd)
      
      # Results should be valid (all results should be success tuples)
      assert match?({:ok, _}, result.stage_results.sma_20)
      assert match?({:ok, _}, result.stage_results.ema_12)
      assert match?({:ok, _}, result.stage_results.rsi)
      assert match?({:ok, _}, result.stage_results.bollinger)
      assert match?({:ok, _}, result.stage_results.macd)
      
      # Extract the actual results for validation
      {:ok, rsi_results} = result.stage_results.rsi
      {:ok, bollinger_results} = result.stage_results.bollinger
      
      # Cross-validate some relationships
      # RSI should be between 0 and 100
      Enum.each(rsi_results, fn rsi_result ->
        assert Decimal.gte?(rsi_result.value, Decimal.new("0"))
        assert Decimal.lte?(rsi_result.value, Decimal.new("100"))
      end)
      
      # Bollinger bands should have proper structure
      assert Map.has_key?(bollinger_results, :upper)
      assert Map.has_key?(bollinger_results, :middle)
      assert Map.has_key?(bollinger_results, :lower)
    end
  end

  describe "Error handling integration" do
    test "consistent error handling across modules" do
      invalid_scenarios = %{
        empty_data: [],
        nil_data: nil,
        invalid_ohlc: [
          %{
            open: Decimal.new("100"),
            high: Decimal.new("95"), # Invalid: high < open
            low: Decimal.new("105"), # Invalid: low > open
            close: Decimal.new("98"),
            volume: 1000,
            timestamp: ~U[2024-01-01 09:30:00Z]
          }
        ],
        missing_fields: [
          %{open: Decimal.new("100"), high: Decimal.new("105")} # Missing required fields
        ]
      }
      
      indicators = %{
        sma: {TradingIndicators.Trend.SMA, :calculate, [period: 14]},
        ema: {TradingIndicators.Trend.EMA, :calculate, [period: 14]},
        rsi: {TradingIndicators.Momentum.RSI, :calculate, [period: 14]},
        atr: {TradingIndicators.Volatility.ATR, :calculate, [period: 14]}
      }
      
      error_results = IntegrationHelpers.test_error_propagation(invalid_scenarios, indicators)
      
      # Verify error handling consistency
      Enum.each(error_results, fn {scenario, scenario_results} ->
        case scenario do
          :empty_data ->
            # Empty data should either return empty list or raise appropriate error
            Enum.each(scenario_results, fn {_indicator, result} ->
              assert result.expected_error or match?(%{result: []}, result)
            end)
            
          :nil_data ->
            # Nil data should raise errors
            Enum.each(scenario_results, fn {_indicator, result} ->
              assert result.expected_error, "Should raise error for nil data"
            end)
            
          :invalid_ohlc ->
            # Invalid OHLC relationships should raise errors  
            Enum.each(scenario_results, fn {_indicator, result} ->
              assert result.expected_error, "Should raise error for invalid OHLC"
            end)
            
          :missing_fields ->
            # Missing required fields should raise errors
            Enum.each(scenario_results, fn {_indicator, result} ->
              assert result.expected_error, "Should raise error for missing fields"
            end)
        end
      end)
    end
  end

  describe "Data quality integration" do
    test "data quality validation integrates with indicators" do
      scenarios = IntegrationHelpers.create_integration_scenarios()
      
      quality_results = IntegrationHelpers.test_data_quality_integration(scenarios)
      
      # Normal data should pass quality checks and work with indicators
      assert quality_results.normal_data.data_quality == :ok
      assert quality_results.normal_data.indicator_responses.sma.success
      assert quality_results.normal_data.indicator_responses.rsi.success
      assert quality_results.normal_data.indicator_responses.bollinger.success
      
      # Small data should work but may have limitations
      if quality_results.small_data.data_quality == :ok do
        # If data quality is OK, indicators should work
        assert quality_results.small_data.indicator_responses.sma.success
      end
      
      # Invalid data should fail quality checks and indicator calculations
      assert match?({:error, _}, quality_results.missing_fields.data_quality)
      assert not quality_results.missing_fields.indicator_responses.sma.success
      
      assert match?({:error, _}, quality_results.invalid_ohlc.data_quality) 
      assert not quality_results.invalid_ohlc.indicator_responses.sma.success
    end
  end

  describe "Performance integration" do 
    @tag timeout: 120_000 # 2 minutes for performance tests
    test "indicators maintain performance at scale" do
      large_data = DataGenerator.sample_ohlcv_data(5_000)
      
      indicators = [
        {"SMA", fn data -> TradingIndicators.Trend.SMA.calculate(data, 14) end},
        {"EMA", fn data -> TradingIndicators.Trend.EMA.calculate(data, 14) end},
        {"RSI", fn data -> TradingIndicators.Momentum.RSI.calculate(data, 14) end},
        {"ATR", fn data -> TradingIndicators.Volatility.ATR.calculate(data, 14) end}
      ]
      
      # Performance should be reasonable for large datasets
      Enum.each(indicators, fn {name, indicator_fun} ->
        {result, time_microseconds} = :timer.tc(indicator_fun, [large_data])
        
        # Should complete within reasonable time (< 10 seconds)
        assert time_microseconds < 10_000_000, 
               "#{name} took too long: #{time_microseconds / 1_000_000} seconds"
        
        # Should produce valid results
        assert is_list(result)
        assert length(result) > 0
        
        # All results should be finite
        assert Enum.all?(result, fn val ->
          case val do
            %{} = map -> 
              map |> Map.values() |> List.flatten() |> Enum.all?(fn val -> not (Decimal.nan?(val) or Decimal.inf?(val)) end)
            val when is_list(val) ->
              Enum.all?(val, fn v -> not (Decimal.nan?(v) or Decimal.inf?(v)) end)  
            val ->
              not (Decimal.nan?(val) or Decimal.inf?(val))
          end
        end), "#{name} produced non-finite values"
      end)
    end
  end
end