defmodule TradingIndicators.Momentum.StochasticTest do
  use ExUnit.Case
  alias TradingIndicators.Momentum.Stochastic
  require Decimal
  doctest Stochastic

  describe "calculate/2" do
    test "calculates Stochastic with sufficient data" do
      data = create_test_hlc_data(20)

      {:ok, results} = Stochastic.calculate(data, k_period: 14, d_period: 3)

      assert length(results) >= 1

      result = List.first(results)
      assert %{value: %{k: k_value, d: d_value}, timestamp: _timestamp, metadata: metadata} = result

      assert Decimal.is_decimal(k_value)
      assert Decimal.is_decimal(d_value)
      assert Decimal.gte?(k_value, Decimal.new("0"))
      assert Decimal.lte?(k_value, Decimal.new("100"))
      assert Decimal.gte?(d_value, Decimal.new("0"))
      assert Decimal.lte?(d_value, Decimal.new("100"))

      assert metadata.indicator == "Stochastic"
      assert metadata.k_period == 14
      assert metadata.d_period == 3
      assert metadata.k_signal in [:overbought, :oversold, :neutral]
      assert metadata.d_signal in [:overbought, :oversold, :neutral]
      assert metadata.crossover in [:bullish, :bearish, :neutral]
    end

    test "calculates Stochastic with custom parameters" do
      data = create_test_hlc_data(15)

      {:ok, results} =
        Stochastic.calculate(data,
          k_period: 10,
          d_period: 2,
          k_smoothing: 3,
          overbought: 85,
          oversold: 15
        )

      assert length(results) > 0

      result = List.first(results)
      assert result.metadata.k_period == 10
      assert result.metadata.d_period == 2
      assert result.metadata.k_smoothing == 3
      assert result.metadata.overbought == 85
      assert result.metadata.oversold == 15
    end

    test "returns error for insufficient data" do
      data = create_test_hlc_data(5)

      {:error, error} = Stochastic.calculate(data, k_period: 14, d_period: 3)

      assert %TradingIndicators.Errors.InsufficientData{} = error
      assert error.required == 16
      assert error.provided == 5
    end

    test "returns error for invalid data format" do
      invalid_data = [
        # Missing high and low
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      ]

      {:error, error} = Stochastic.calculate(invalid_data, k_period: 5, d_period: 3)

      assert %TradingIndicators.Errors.InvalidDataFormat{} = error
    end

    test "validates parameters" do
      data = create_test_hlc_data(20)

      # Invalid k_period
      {:error, error} = Stochastic.calculate(data, k_period: 0)
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.param == :k_period

      # Invalid d_period
      {:error, error} = Stochastic.calculate(data, d_period: 0)
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.param == :d_period

      # Invalid overbought level
      {:error, error} = Stochastic.calculate(data, overbought: 150)
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.param == :overbought

      # Invalid level relationship
      {:error, error} = Stochastic.calculate(data, overbought: 20, oversold: 80)
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.param == :levels
    end
  end

  describe "streaming functionality" do
    test "init_state/1 initializes proper state" do
      state = Stochastic.init_state(k_period: 14, d_period: 3, overbought: 85, oversold: 15)

      assert state.k_period == 14
      assert state.d_period == 3
      assert state.overbought == 85
      assert state.oversold == 15
      assert state.highs == []
      assert state.lows == []
      assert state.closes == []
      assert state.k_values == []
      assert state.count == 0
    end

    test "update_state/2 processes data points correctly" do
      state = Stochastic.init_state(k_period: 3, d_period: 2)

      data_points = [
        %{
          high: Decimal.new("105"),
          low: Decimal.new("95"),
          close: Decimal.new("100"),
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          high: Decimal.new("107"),
          low: Decimal.new("97"),
          close: Decimal.new("102"),
          timestamp: ~U[2024-01-01 09:31:00Z]
        },
        %{
          high: Decimal.new("106"),
          low: Decimal.new("96"),
          close: Decimal.new("101"),
          timestamp: ~U[2024-01-01 09:32:00Z]
        },
        %{
          high: Decimal.new("108"),
          low: Decimal.new("98"),
          close: Decimal.new("103"),
          timestamp: ~U[2024-01-01 09:33:00Z]
        },
        %{
          high: Decimal.new("109"),
          low: Decimal.new("99"),
          close: Decimal.new("104"),
          timestamp: ~U[2024-01-01 09:34:00Z]
        }
      ]

      {final_state, final_result} =
        Enum.reduce(data_points, {state, nil}, fn data_point, {acc_state, _} ->
          {:ok, new_state, result} = Stochastic.update_state(acc_state, data_point)
          {new_state, result}
        end)

      assert final_state.count == 5
      # Should have a result with k_period=3, d_period=2 after 4 points
      assert is_map(final_result)
      assert %{k: _k_value, d: _d_value} = final_result.value
      assert final_result.metadata.indicator == "Stochastic"
    end

    test "update_state/2 returns error for invalid data" do
      state = Stochastic.init_state(k_period: 14, d_period: 3)
      # Missing high and low
      invalid_data = %{close: Decimal.new("100")}

      {:error, error} = Stochastic.update_state(state, invalid_data)
      assert %TradingIndicators.Errors.StreamStateError{} = error
    end

    test "update_state/2 returns error for invalid state" do
      invalid_state = %{invalid: "state"}

      data_point = %{
        high: Decimal.new("105"),
        low: Decimal.new("95"),
        close: Decimal.new("100"),
        timestamp: ~U[2024-01-01 09:30:00Z]
      }

      {:error, error} = Stochastic.update_state(invalid_state, data_point)
      assert %TradingIndicators.Errors.StreamStateError{} = error
    end
  end

  describe "required_periods/0" do
    test "returns default required periods" do
      # k_period(14) + d_period(3) - 1
      assert Stochastic.required_periods() == 16
    end
  end

  describe "required_periods/1" do
    test "returns configured required periods" do
      assert Stochastic.required_periods(k_period: 10, d_period: 2) == 11
    end
  end

  describe "validate_params/1" do
    test "validates valid parameters" do
      assert :ok ==
               Stochastic.validate_params(k_period: 14, d_period: 3, overbought: 80, oversold: 20)
    end

    test "validates empty parameters" do
      assert :ok == Stochastic.validate_params([])
    end

    test "rejects invalid parameter types" do
      {:error, error} = Stochastic.validate_params("not a list")
      assert %TradingIndicators.Errors.InvalidParams{} = error
    end
  end

  describe "mathematical accuracy" do
    test "calculates correct %K value" do
      # Simple test case with known values
      data = [
        %{
          high: Decimal.new("110"),
          low: Decimal.new("90"),
          close: Decimal.new("100"),
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          high: Decimal.new("115"),
          low: Decimal.new("95"),
          close: Decimal.new("105"),
          timestamp: ~U[2024-01-01 09:31:00Z]
        },
        %{
          high: Decimal.new("112"),
          low: Decimal.new("92"),
          close: Decimal.new("102"),
          timestamp: ~U[2024-01-01 09:32:00Z]
        }
      ]

      {:ok, results} = Stochastic.calculate(data, k_period: 3, d_period: 1)

      assert length(results) == 1
      result = List.first(results)

      # For the last period:
      # Highest high = 115, Lowest low = 90, Current close = 102
      # %K = ((102 - 90) / (115 - 90)) * 100 = (12 / 25) * 100 = 48%
      expected_k = Decimal.new("48.00")
      assert Decimal.equal?(result.value.k, expected_k)
    end

    test "handles edge cases" do
      # Test case where high equals low (no price range)
      data = [
        %{
          high: Decimal.new("100"),
          low: Decimal.new("100"),
          close: Decimal.new("100"),
          timestamp: ~U[2024-01-01 09:30:00Z]
        },
        %{
          high: Decimal.new("100"),
          low: Decimal.new("100"),
          close: Decimal.new("100"),
          timestamp: ~U[2024-01-01 09:31:00Z]
        },
        %{
          high: Decimal.new("100"),
          low: Decimal.new("100"),
          close: Decimal.new("100"),
          timestamp: ~U[2024-01-01 09:32:00Z]
        }
      ]

      {:ok, results} = Stochastic.calculate(data, k_period: 3, d_period: 1)

      assert length(results) == 1
      result = List.first(results)

      # Should return neutral value (50%) when no price range
      expected_k = Decimal.new("50.0")
      assert Decimal.equal?(result.value.k, expected_k)
    end
  end

  # Helper function to create test HLC data
  defp create_test_hlc_data(count) do
    base_price = 100

    1..count
    |> Enum.map(fn i ->
      base = base_price + :rand.uniform(20) - 10
      high = base + :rand.uniform(5)
      low = base - :rand.uniform(5)
      close = (low + :rand.uniform(trunc(high - low))) |> max(low) |> min(high)

      %{
        high: Decimal.new(high),
        low: Decimal.new(low),
        close: Decimal.new(close),
        timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i * 60, :second)
      }
    end)
  end

  describe "parameter_metadata/0" do
    test "returns correct parameter metadata" do
      metadata = Stochastic.parameter_metadata()

      assert is_list(metadata)
      assert length(metadata) == 5

      # Verify k_period parameter
      k_period_param = Enum.find(metadata, fn p -> p.name == :k_period end)
      assert k_period_param != nil
      assert k_period_param.type == :integer
      assert k_period_param.default == 14
      assert k_period_param.required == false
      assert k_period_param.min == 1

      # Verify d_period parameter
      d_period_param = Enum.find(metadata, fn p -> p.name == :d_period end)
      assert d_period_param != nil
      assert d_period_param.type == :integer
      assert d_period_param.default == 3
      assert d_period_param.min == 1

      # Verify k_smoothing parameter
      k_smoothing_param = Enum.find(metadata, fn p -> p.name == :k_smoothing end)
      assert k_smoothing_param != nil
      assert k_smoothing_param.type == :integer
      assert k_smoothing_param.default == 1
      assert k_smoothing_param.min == 1

      # Verify overbought parameter
      overbought_param = Enum.find(metadata, fn p -> p.name == :overbought end)
      assert overbought_param != nil
      assert overbought_param.type == :integer
      assert overbought_param.default == 80
      assert overbought_param.min == 0
      assert overbought_param.max == 100

      # Verify oversold parameter
      oversold_param = Enum.find(metadata, fn p -> p.name == :oversold end)
      assert oversold_param != nil
      assert oversold_param.type == :integer
      assert oversold_param.default == 20
      assert oversold_param.min == 0
      assert oversold_param.max == 100
    end

    test "all metadata maps have required fields" do
      metadata = Stochastic.parameter_metadata()

      Enum.each(metadata, fn param ->
        assert Map.has_key?(param, :name)
        assert Map.has_key?(param, :type)
        assert Map.has_key?(param, :default)
        assert Map.has_key?(param, :required)
        assert Map.has_key?(param, :description)
      end)
    end
  end
end
