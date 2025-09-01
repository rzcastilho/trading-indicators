defmodule TradingIndicators.VolumeTest do
  use ExUnit.Case, async: true
  alias TradingIndicators.Volume
  alias TradingIndicators.Volume.{OBV, VWAP, AccumulationDistribution, ChaikinMoneyFlow}
  require Decimal

  doctest Volume

  @test_data [
    %{high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]},
    %{high: Decimal.new("107"), low: Decimal.new("102"), close: Decimal.new("106"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]},
    %{high: Decimal.new("108"), low: Decimal.new("104"), close: Decimal.new("105"), volume: 800, timestamp: ~U[2024-01-01 09:32:00Z]}
  ]

  describe "available_indicators/0" do
    test "returns all available volume indicators" do
      indicators = Volume.available_indicators()
      
      assert length(indicators) == 4
      assert OBV in indicators
      assert VWAP in indicators
      assert AccumulationDistribution in indicators
      assert ChaikinMoneyFlow in indicators
    end
  end

  describe "calculate/3" do
    test "calculates OBV indicator" do
      {:ok, results} = Volume.calculate(OBV, @test_data, [])
      
      assert length(results) == 3
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.new("1000.00"))
      assert Enum.at(results, 0).metadata.indicator == "OBV"
    end

    test "calculates VWAP indicator" do
      {:ok, results} = Volume.calculate(VWAP, @test_data, variant: :close)
      
      assert length(results) == 3
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.new("103.000000"))
      assert Enum.at(results, 0).metadata.indicator == "VWAP"
    end

    test "calculates AccumulationDistribution indicator" do
      {:ok, results} = Volume.calculate(AccumulationDistribution, @test_data, [])
      
      assert length(results) == 3
      assert Enum.at(results, 0).metadata.indicator == "AccumulationDistribution"
    end

    test "calculates ChaikinMoneyFlow indicator" do
      {:ok, results} = Volume.calculate(ChaikinMoneyFlow, @test_data, period: 2)
      
      assert length(results) == 2  # 3 - 2 + 1 = 2
      assert Enum.at(results, 0).metadata.indicator == "ChaikinMoneyFlow"
    end

    test "returns error for unknown indicator" do
      assert {:error, %TradingIndicators.Errors.InvalidParams{}} = 
        Volume.calculate(UnknownIndicator, @test_data, [])
    end

    test "passes through indicator-specific errors" do
      assert {:error, %TradingIndicators.Errors.InsufficientData{}} = 
        Volume.calculate(ChaikinMoneyFlow, [], period: 20)
    end
  end

  describe "convenience functions" do
    test "obv/2 calculates On-Balance Volume" do
      {:ok, results} = Volume.obv(@test_data, [])
      
      assert length(results) == 3
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.new("1000.00"))
    end

    test "vwap/2 calculates Volume Weighted Average Price" do
      {:ok, results} = Volume.vwap(@test_data, variant: :typical)
      
      assert length(results) == 3
      # First typical price = (105 + 99 + 103) / 3 = 102.333333
      expected_first = Decimal.div(Decimal.new("307"), Decimal.new("3"))
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.round(expected_first, 6))
    end

    test "accumulation_distribution/2 calculates A/D Line" do
      {:ok, results} = Volume.accumulation_distribution(@test_data, [])
      
      assert length(results) == 3
      expected_first = Decimal.div(Decimal.new("1000"), Decimal.new("3"))
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.round(expected_first, 6))
    end

    test "chaikin_money_flow/2 calculates Chaikin Money Flow" do
      {:ok, results} = Volume.chaikin_money_flow(@test_data, period: 2)
      
      assert length(results) == 2
      expected_first = Decimal.div(Decimal.new("1233.333333"), Decimal.new("2500"))
      assert Decimal.equal?(Enum.at(results, 0).value, Decimal.round(expected_first, 6))
    end
  end

  describe "streaming functionality" do
    test "init_stream/2 initializes state for OBV" do
      state = Volume.init_stream(OBV, [])
      
      assert state.obv_value == nil
      assert state.previous_close == nil
      assert state.count == 0
    end

    test "init_stream/2 initializes state for VWAP" do
      state = Volume.init_stream(VWAP, variant: :typical, session_reset: :daily)
      
      assert state.variant == :typical
      assert state.session_reset == :daily
      assert Decimal.equal?(state.cumulative_price_volume, Decimal.new("0"))
      assert Decimal.equal?(state.cumulative_volume, Decimal.new("0"))
    end

    test "init_stream/2 initializes state for AccumulationDistribution" do
      state = Volume.init_stream(AccumulationDistribution, [])
      
      assert state.ad_line_value == nil
      assert state.count == 0
    end

    test "init_stream/2 initializes state for ChaikinMoneyFlow" do
      state = Volume.init_stream(ChaikinMoneyFlow, period: 14)
      
      assert state.period == 14
      assert state.money_flow_volumes == []
      assert state.volumes == []
      assert state.count == 0
    end

    test "init_stream/2 raises error for unknown indicator" do
      assert_raise ArgumentError, ~r/Unknown volume indicator/, fn ->
        Volume.init_stream(UnknownIndicator, [])
      end
    end

    test "update_stream/2 handles OBV state" do
      state = %{
        obv_value: Decimal.new("1000"),
        previous_close: Decimal.new("100"),
        count: 1
      }
      
      data_point = %{close: Decimal.new("105"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]}
      {:ok, new_state, result} = Volume.update_stream(state, data_point)
      
      assert Decimal.equal?(new_state.obv_value, Decimal.new("2500"))
      assert Decimal.equal?(result.value, Decimal.new("2500.00"))
    end

    test "update_stream/2 handles VWAP state" do
      state = %{
        variant: :close,
        session_reset: :none,
        cumulative_price_volume: Decimal.new("100000"),
        cumulative_volume: Decimal.new("1000"),
        current_session_start: ~U[2024-01-01 00:00:00Z],
        count: 1
      }
      
      data_point = %{close: Decimal.new("102"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]}
      {:ok, new_state, result} = Volume.update_stream(state, data_point)
      
      assert Decimal.equal?(new_state.cumulative_price_volume, Decimal.new("253000"))
      assert Decimal.equal?(new_state.cumulative_volume, Decimal.new("2500"))
      assert Decimal.equal?(result.value, Decimal.new("101.200000"))
    end

    test "update_stream/2 handles AccumulationDistribution state" do
      state = %{
        ad_line_value: Decimal.new("1000"),
        count: 1
      }
      
      data_point = %{high: Decimal.new("107"), low: Decimal.new("102"), close: Decimal.new("106"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]}
      {:ok, new_state, result} = Volume.update_stream(state, data_point)
      
      expected_new = Decimal.add(Decimal.new("1000"), Decimal.new("900"))
      assert Decimal.equal?(new_state.ad_line_value, expected_new)
      assert Decimal.equal?(result.value, Decimal.round(expected_new, 6))
    end

    test "update_stream/2 handles ChaikinMoneyFlow state" do
      state = %{
        period: 2,
        money_flow_volumes: [Decimal.div(Decimal.new("1000"), Decimal.new("3"))],
        volumes: [Decimal.new("1000")],
        count: 1
      }
      
      data_point = %{high: Decimal.new("107"), low: Decimal.new("102"), close: Decimal.new("106"), volume: 1500, timestamp: ~U[2024-01-01 09:31:00Z]}
      {:ok, new_state, result} = Volume.update_stream(state, data_point)
      
      assert length(new_state.money_flow_volumes) == 2
      assert length(new_state.volumes) == 2
      assert new_state.count == 2
      assert result != nil
      expected_cmf = Decimal.div(Decimal.new("1233.333333"), Decimal.new("2500"))
      assert Decimal.equal?(result.value, Decimal.round(expected_cmf, 6))
    end

    test "update_stream/2 returns error for unrecognized state" do
      invalid_state = %{unknown: true}
      data_point = %{close: Decimal.new("100"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}
      
      assert {:error, %TradingIndicators.Errors.StreamStateError{}} = 
        Volume.update_stream(invalid_state, data_point)
    end
  end

  describe "indicator_info/1" do
    test "returns information for OBV" do
      info = Volume.indicator_info(OBV)
      
      assert info.module == OBV
      assert info.name == "OBV"
      assert info.required_periods == 1
      assert info.supports_streaming == true
    end

    test "returns information for VWAP" do
      info = Volume.indicator_info(VWAP)
      
      assert info.module == VWAP
      assert info.name == "VWAP"
      assert info.required_periods == 1
      assert info.supports_streaming == true
    end

    test "returns information for AccumulationDistribution" do
      info = Volume.indicator_info(AccumulationDistribution)
      
      assert info.module == AccumulationDistribution
      assert info.name == "AccumulationDistribution"
      assert info.required_periods == 1
      assert info.supports_streaming == true
    end

    test "returns information for ChaikinMoneyFlow" do
      info = Volume.indicator_info(ChaikinMoneyFlow)
      
      assert info.module == ChaikinMoneyFlow
      assert info.name == "ChaikinMoneyFlow"
      assert info.required_periods == 20
      assert info.supports_streaming == true
    end

    test "returns error for unknown indicator" do
      info = Volume.indicator_info(UnknownIndicator)
      
      assert info == %{error: "Unknown indicator"}
    end
  end

  describe "all_indicators_info/0" do
    test "returns information for all indicators" do
      all_info = Volume.all_indicators_info()
      
      assert length(all_info) == 4
      
      indicator_names = Enum.map(all_info, & &1.name)
      assert "OBV" in indicator_names
      assert "VWAP" in indicator_names
      assert "AccumulationDistribution" in indicator_names
      assert "ChaikinMoneyFlow" in indicator_names
      
      # All should support streaming
      Enum.each(all_info, fn info ->
        assert info.supports_streaming == true
      end)
    end
  end

  describe "integration with multiple volume indicators" do
    test "can calculate multiple indicators on same data" do
      # Test data with sufficient periods for all indicators
      data = generate_test_data(25)
      
      # Calculate all indicators
      {:ok, obv_results} = Volume.obv(data, [])
      {:ok, vwap_results} = Volume.vwap(data, variant: :close)
      {:ok, ad_results} = Volume.accumulation_distribution(data, [])
      {:ok, cmf_results} = Volume.chaikin_money_flow(data, period: 20)
      
      # All should return valid results
      assert length(obv_results) == 25
      assert length(vwap_results) == 25
      assert length(ad_results) == 25
      assert length(cmf_results) == 6  # 25 - 20 + 1
      
      # Results should be properly typed
      Enum.each([obv_results, vwap_results, ad_results, cmf_results], fn results ->
        Enum.each(results, fn result ->
          assert Map.has_key?(result, :value)
          assert Map.has_key?(result, :timestamp)
          assert Map.has_key?(result, :metadata)
          assert Decimal.is_decimal(result.value)
        end)
      end)
    end

    test "streaming states don't interfere with each other" do
      # Initialize multiple streaming states
      obv_state = Volume.init_stream(OBV, [])
      vwap_state = Volume.init_stream(VWAP, variant: :close)
      ad_state = Volume.init_stream(AccumulationDistribution, [])
      cmf_state = Volume.init_stream(ChaikinMoneyFlow, period: 3)
      
      data_point = %{high: Decimal.new("105"), low: Decimal.new("99"), close: Decimal.new("103"), volume: 1000, timestamp: ~U[2024-01-01 09:30:00Z]}
      
      # Update all states with the same data point
      {:ok, new_obv_state, obv_result} = Volume.update_stream(obv_state, data_point)
      {:ok, new_vwap_state, vwap_result} = Volume.update_stream(vwap_state, data_point)
      {:ok, new_ad_state, ad_result} = Volume.update_stream(ad_state, data_point)
      {:ok, new_cmf_state, cmf_result} = Volume.update_stream(cmf_state, data_point)
      
      # All should produce valid results or nil (for insufficient data)
      assert obv_result != nil
      assert vwap_result != nil
      assert ad_result != nil
      assert cmf_result == nil  # Insufficient data for period=3
      
      # States should be independent
      assert new_obv_state.count == 1
      assert new_vwap_state.count == 1
      assert new_ad_state.count == 1
      assert new_cmf_state.count == 1
      
      # Each state should maintain its specific structure
      assert Map.has_key?(new_obv_state, :obv_value)
      assert Map.has_key?(new_vwap_state, :cumulative_price_volume)
      assert Map.has_key?(new_ad_state, :ad_line_value)
      assert Map.has_key?(new_cmf_state, :money_flow_volumes)
    end
  end

  # Helper function to generate test data
  defp generate_test_data(count) do
    1..count
    |> Enum.map(fn i ->
      base = 100 + i
      %{
        high: Decimal.new("#{base + 2}"),
        low: Decimal.new("#{base - 2}"),
        close: Decimal.new("#{base}"),
        volume: 1000 + i * 10,
        timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i, :second)
      }
    end)
  end
end