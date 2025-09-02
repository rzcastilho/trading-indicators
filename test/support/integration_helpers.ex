defmodule TradingIndicators.TestSupport.IntegrationHelpers do
  @moduledoc """
  Integration testing support for cross-module functionality testing.
  """

  alias TradingIndicators.TestSupport.{DataGenerator, TestHelpers}

  # @doc """
  # Tests pipeline integration with multiple indicators.
  # """
  # def test_indicator_pipeline(data, indicators) do
    
  #   # Test each indicator individually
  #   individual_results = Enum.reduce(indicators, %{}, fn {name, {module, fun, args}}, acc ->
  #     try do
  #       result = apply(module, fun, [data | args])
  #       Map.put(acc, name, %{result: result, success: true})
  #     rescue
  #       error ->
  #         Map.put(acc, name, %{error: error, success: false})
  #     end
  #   end)
    
  #   # Test pipeline execution
  #   pipeline_result = try do
  #     pipeline = TradingIndicators.Pipeline.new()
      
  #     pipeline_with_indicators = Enum.reduce(indicators, pipeline, fn {name, {module, fun, args}}, pipe ->
  #       TradingIndicators.Pipeline.add_indicator(pipe, name, {module, fun, args})
  #     end)
      
  #     pipeline_results = TradingIndicators.Pipeline.run(pipeline_with_indicators, data)
  #     %{results: pipeline_results, success: true}
  #   rescue
  #     error ->
  #       %{error: error, success: false}
  #   end
    
  #   %{
  #     individual: individual_results,
  #     pipeline: pipeline_result,
  #     data_size: length(data)
  #   }
  # end

  # @doc """
  # Tests streaming integration with multiple indicators.
  # """
  # def test_streaming_integration(initial_data, additional_data, indicators) do
    
  #   # Initialize streaming contexts
  #   streaming_contexts = Enum.reduce(indicators, %{}, fn {name, {module, fun, args}}, acc ->
  #     try do
  #       context = TradingIndicators.Streaming.initialize(module, fun, args)
  #       Map.put(acc, name, %{context: context, success: true})
  #     rescue
  #       error ->
  #         Map.put(acc, name, %{error: error, success: false})
  #     end
  #   end)
    
  #   # Process initial data
  #   initial_results = Enum.reduce(streaming_contexts, %{}, fn {name, ctx_data}, acc ->
  #     if ctx_data.success do
  #       try do
  #         {updated_context, results} = Enum.reduce(initial_data, {ctx_data.context, []}, fn data_point, {context, acc_results} ->
  #           {new_context, result} = TradingIndicators.Streaming.update(context, data_point)
  #           {new_context, [result | acc_results]}
  #         end)
          
  #         Map.put(acc, name, %{
  #           context: updated_context,
  #           results: Enum.reverse(results),
  #           success: true
  #         })
  #       rescue
  #         error ->
  #           Map.put(acc, name, %{error: error, success: false})
  #       end
  #     else
  #       Map.put(acc, name, ctx_data)
  #     end
  #   end)
    
  #   # Process additional data
  #   final_results = Enum.reduce(initial_results, %{}, fn {name, result_data}, acc ->
  #     if result_data.success do
  #       try do
  #         {_final_context, additional_results} = Enum.reduce(additional_data, {result_data.context, []}, fn data_point, {context, acc_results} ->
  #           {new_context, result} = TradingIndicators.Streaming.update(context, data_point)
  #           {new_context, [result | acc_results]}
  #         end)
          
  #         Map.put(acc, name, %{
  #           initial_results: result_data.results,
  #           additional_results: Enum.reverse(additional_results),
  #           total_results: result_data.results ++ Enum.reverse(additional_results),
  #           success: true
  #         })
  #       rescue
  #         error ->
  #           Map.put(acc, name, %{error: error, success: false})
  #       end
  #     else
  #       Map.put(acc, name, result_data)
  #     end
  #   end)
    
  #   %{
  #     streaming: final_results,
  #     data_sizes: %{
  #       initial: length(initial_data),
  #       additional: length(additional_data),
  #       total: length(initial_data) + length(additional_data)
  #     }
  #   }
  # end

  @doc """
  Tests indicator combinations and correlations.
  """
  def test_indicator_correlations(data, correlations) do
    # Calculate all required indicators
    indicator_results = Enum.reduce(correlations, %{}, fn {combo_name, indicators}, acc ->
      combo_results = Enum.reduce(indicators, %{}, fn {ind_name, {module, fun, args}}, combo_acc ->
        try do
          result = apply(module, fun, [data | args])
          Map.put(combo_acc, ind_name, result)
        rescue
          error ->
          Map.put(combo_acc, ind_name, {:error, error})
        end
      end)
      
      Map.put(acc, combo_name, combo_results)
    end)
    
    # Analyze correlations
    correlation_analysis = Enum.reduce(indicator_results, %{}, fn {combo_name, combo_results}, acc ->
      # Check if all indicators succeeded
      all_successful = Enum.all?(combo_results, fn {_name, result} ->
        is_list(result) and not match?({:error, _}, result)
      end)
      
      analysis = if all_successful do
        analyze_indicator_correlation(combo_results)
      else
        %{error: "One or more indicators failed", success: false}
      end
      
      Map.put(acc, combo_name, analysis)
    end)
    
    %{
      indicator_results: indicator_results,
      correlations: correlation_analysis,
      data_size: length(data)
    }
  end

  @doc """
  Tests error handling across modules.
  """
  def test_error_propagation(invalid_data_scenarios, indicators) do
    Enum.reduce(invalid_data_scenarios, %{}, fn {scenario_name, invalid_data}, acc ->
      scenario_results = Enum.reduce(indicators, %{}, fn {ind_name, {module, fun, args}}, ind_acc ->
        try do
          _result = apply(module, fun, [invalid_data | args])
          # If we get here, the indicator didn't raise an error (which might be unexpected)
          Map.put(ind_acc, ind_name, %{
            result: :no_error_raised,
            expected_error: false,
            success: true
          })
        rescue
          error ->
            Map.put(ind_acc, ind_name, %{
              error: error,
              error_type: error.__struct__,
              expected_error: true,
              success: true
            })
        catch
          :exit, reason ->
            Map.put(ind_acc, ind_name, %{
              exit_reason: reason,
              expected_error: true,
              success: true
            })
        end
      end)
      
      Map.put(acc, scenario_name, scenario_results)
    end)
  end

  # @doc """
  # Tests data quality validation across modules.
  # """
  # def test_data_quality_integration(data_scenarios) do
  #   Enum.reduce(data_scenarios, %{}, fn {scenario_name, data}, acc ->
  #     # Test data quality validation
  #     quality_check = try do
  #       TradingIndicators.DataQuality.validate_ohlcv_data(data)
  #     rescue
  #       error ->
  #         {:error, error}
  #     end
      
  #     # Test with various indicators to see consistency
  #     indicator_tests = %{
  #       sma: test_with_indicator(data, TradingIndicators.Trend.SMA, :calculate, [14]),
  #       rsi: test_with_indicator(data, TradingIndicators.Momentum.RSI, :calculate, [14]),
  #       bollinger: test_with_indicator(data, TradingIndicators.Volatility.BollingerBands, :calculate, [period: 20, multiplier: Decimal.new("2.0")])
  #     }
      
  #     Map.put(acc, scenario_name, %{
  #       data_quality: quality_check,
  #       indicator_responses: indicator_tests,
  #       data_size: length(data)
  #     })
  #   end)
  # end

  @doc """
  Creates comprehensive integration test scenarios.
  """
  def create_integration_scenarios do
    %{
      normal_data: DataGenerator.sample_ohlcv_data(100),
      small_data: DataGenerator.sample_ohlcv_data(5),
      large_data: DataGenerator.sample_ohlcv_data(1_000),
      
      # Edge cases
      empty_data: [],
      single_point: DataGenerator.sample_ohlcv_data(1),
      two_points: DataGenerator.sample_ohlcv_data(2),
      
      # Quality issues
      missing_fields: [
        %{open: Decimal.new("100"), high: Decimal.new("105"), low: Decimal.new("95")}, # missing close
      ],
      invalid_ohlc: [
        %{
          open: Decimal.new("100"),
          high: Decimal.new("90"), # high < open (invalid)
          low: Decimal.new("105"),  # low > open (invalid)
          close: Decimal.new("95"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        }
      ],
      zero_volume: [
        %{
          open: Decimal.new("100"),
          high: Decimal.new("105"),
          low: Decimal.new("95"),
          close: Decimal.new("102"),
          volume: 0, # zero volume
          timestamp: ~U[2024-01-01 09:30:00Z]
        }
      ],
      
      # Extreme values
      extreme_prices: [
        %{
          open: Decimal.new("0.00001"),
          high: Decimal.new("999999.99"),
          low: Decimal.new("0.00001"),
          close: Decimal.new("500000"),
          volume: 1000000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        }
      ]
    }
  end

  @doc """
  Validates cross-indicator consistency.
  """
  def validate_cross_indicator_consistency(data) do
    # Test related indicators for logical consistency
    
    # Moving averages should have logical relationships
    sma_10 = TradingIndicators.Trend.SMA.calculate(data, 10)
    sma_20 = TradingIndicators.Trend.SMA.calculate(data, 20)
    ema_10 = TradingIndicators.Trend.EMA.calculate(data, 10)
    
    # Volatility indicators consistency
    atr = TradingIndicators.Volatility.ATR.calculate(data, 14)
    bb = TradingIndicators.Volatility.BollingerBands.calculate(data, period: 20, multiplier: Decimal.new("2.0"))
    
    # Volume indicators consistency
    obv = TradingIndicators.Volume.OBV.calculate(data)
    vwap = TradingIndicators.Volume.VWAP.calculate(data)
    
    # Perform consistency checks
    consistency_checks = %{
      moving_averages: check_moving_average_consistency(sma_10, sma_20, ema_10),
      volatility_indicators: check_volatility_consistency(atr, bb),
      volume_indicators: check_volume_consistency(obv, vwap),
      all_finite: check_all_results_finite([sma_10, sma_20, ema_10, atr, obv, vwap])
    }
    
    %{
      individual_results: %{
        sma_10: sma_10,
        sma_20: sma_20,
        ema_10: ema_10,
        atr: atr,
        bollinger_bands: bb,
        obv: obv,
        vwap: vwap
      },
      consistency_checks: consistency_checks,
      overall_consistent: Enum.all?(consistency_checks, fn {_key, result} -> result end)
    }
  end

  # Private helper functions

  defp analyze_indicator_correlation(results) do
    # Simple correlation analysis between indicator results
    result_pairs = for {name1, result1} <- results,
                      {name2, result2} <- results,
                      name1 < name2,
                      is_list(result1),
                      is_list(result2) do
      
      # Only correlate if both have same length and sufficient data
      min_length = min(length(result1), length(result2))
      
      if min_length > 5 do
        trimmed1 = Enum.take(result1, min_length)
        trimmed2 = Enum.take(result2, min_length)
        correlation = calculate_correlation(trimmed1, trimmed2)
        
        %{
          indicators: "#{name1} vs #{name2}",
          correlation: correlation,
          data_length: min_length,
          strong_correlation: abs(correlation) > 0.7
        }
      else
        %{
          indicators: "#{name1} vs #{name2}",
          error: "Insufficient data for correlation",
          data_length: min_length
        }
      end
    end
    
    %{
      correlations: result_pairs,
      success: true
    }
  end

  defp calculate_correlation(list1, list2) do
    n = length(list1)
    
    if n < 2 do
      0.0
    else
      # Convert decimals to floats for correlation calculation
      float1 = Enum.map(list1, &Decimal.to_float/1)
      float2 = Enum.map(list2, &Decimal.to_float/1)
      
      mean1 = Enum.sum(float1) / n
      mean2 = Enum.sum(float2) / n
      
      numerator = Enum.zip(float1, float2)
                  |> Enum.map(fn {x, y} -> (x - mean1) * (y - mean2) end)
                  |> Enum.sum()
      
      var1 = Enum.map(float1, fn x -> :math.pow(x - mean1, 2) end) |> Enum.sum()
      var2 = Enum.map(float2, fn y -> :math.pow(y - mean2, 2) end) |> Enum.sum()
      
      denominator = :math.sqrt(var1 * var2)
      
      if denominator == 0, do: 0.0, else: numerator / denominator
    end
  end

  defp test_with_indicator(data, module, function, args) do
    try do
      result = apply(module, function, [data | args])
      %{result: result, success: true, result_length: length(result)}
    rescue
      error ->
        %{error: error, success: false, error_type: error.__struct__}
    end
  end

  defp check_moving_average_consistency(sma_10, sma_20, ema_10) do
    # For trending data, shorter period MA should be more responsive
    # This is a simplified check
    all_finite = TestHelpers.all_finite?([sma_10, sma_20, ema_10])
    reasonable_lengths = length(sma_10) >= length(sma_20) # Shorter period should have more values
    
    all_finite && reasonable_lengths
  end

  defp check_volatility_consistency(atr, bb) do
    # ATR and Bollinger Bands should both reflect market volatility
    # Higher ATR periods should correlate with wider Bollinger Bands
    
    case bb do
      %{upper: upper, lower: lower} when is_list(upper) and is_list(lower) ->
        # Calculate average band width
        band_widths = Enum.zip(upper, lower)
                     |> Enum.map(fn {u, l} -> Decimal.sub(u, l) end)
        
        # Check if both ATR and band widths are reasonable
        atr_finite = TestHelpers.all_finite?(atr)
        bb_finite = TestHelpers.all_finite?(band_widths)
        
        atr_finite && bb_finite
      _ ->
        false
    end
  end

  defp check_volume_consistency(_obv, vwap) do
    # Basic check - VWAP should produce reasonable price-like values
    if is_list(vwap) do
      TestHelpers.all_finite?(vwap)
    else
      false
    end
  end

  defp check_all_results_finite(results) do
    Enum.all?(results, fn result ->
      case result do
        list when is_list(list) -> TestHelpers.all_finite?(list)
        %{} = map -> 
          map
          |> Map.values()
          |> Enum.all?(fn val -> 
            if is_list(val), do: TestHelpers.all_finite?(val), else: true
          end)
        _ -> true
      end
    end)
  end
end

