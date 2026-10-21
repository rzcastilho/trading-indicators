defmodule TradingIndicators.Momentum.RSITest do
  use ExUnit.Case
  alias TradingIndicators.Momentum.RSI
  require Decimal
  doctest RSI

  describe "calculate/2" do
    test "calculates RSI with sufficient data" do
      # Using known RSI test data
      data = [
        %{close: Decimal.new("44.34"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("44.09"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("44.15"), timestamp: ~U[2024-01-01 09:32:00Z]},
        %{close: Decimal.new("43.61"), timestamp: ~U[2024-01-01 09:33:00Z]},
        %{close: Decimal.new("44.33"), timestamp: ~U[2024-01-01 09:34:00Z]},
        %{close: Decimal.new("44.83"), timestamp: ~U[2024-01-01 09:35:00Z]},
        %{close: Decimal.new("45.85"), timestamp: ~U[2024-01-01 09:36:00Z]},
        %{close: Decimal.new("46.08"), timestamp: ~U[2024-01-01 09:37:00Z]},
        %{close: Decimal.new("45.89"), timestamp: ~U[2024-01-01 09:38:00Z]},
        %{close: Decimal.new("46.03"), timestamp: ~U[2024-01-01 09:39:00Z]},
        %{close: Decimal.new("46.83"), timestamp: ~U[2024-01-01 09:40:00Z]},
        %{close: Decimal.new("47.69"), timestamp: ~U[2024-01-01 09:41:00Z]},
        %{close: Decimal.new("46.55"), timestamp: ~U[2024-01-01 09:42:00Z]},
        %{close: Decimal.new("46.50"), timestamp: ~U[2024-01-01 09:43:00Z]},
        %{close: Decimal.new("46.75"), timestamp: ~U[2024-01-01 09:44:00Z]}
      ]

      {:ok, results} = RSI.calculate(data, period: 14)

      assert length(results) == 1

      result = List.first(results)
      assert %{value: rsi_value, timestamp: _timestamp, metadata: metadata} = result

      assert Decimal.is_decimal(rsi_value)
      assert Decimal.gt?(rsi_value, Decimal.new("0"))
      assert Decimal.lt?(rsi_value, Decimal.new("100"))

      assert metadata.indicator == "RSI"
      assert metadata.period == 14
      assert metadata.overbought == 70
      assert metadata.oversold == 30
      assert metadata.signal in [:overbought, :oversold, :neutral]
    end

    # Worked RSI(14) example published by StockCharts, with Wilder's smoothing.
    @wilder_closes ~w(44.3389 44.0902 44.1497 43.6124 44.2779 44.8264 45.0955 45.4245 45.8433
                      46.0826 45.8931 46.0328 45.6140 46.2820 46.2820 46.0028 46.0328 46.4116
                      46.2222 45.6439 46.2122 46.2521 45.7137 46.4515 45.7835 45.3548 44.0288
                      44.1783 44.2181 44.5672 43.4205 42.6628 43.1314)
    @wilder_rsi ~w(70.53 66.32 66.55 69.41 66.36 57.97 62.93 63.26 56.06 62.38 54.71 50.42
                   39.99 41.46 41.87 45.46 37.30 33.08 37.77)

    defp wilder_data do
      @wilder_closes
      |> Enum.with_index()
      |> Enum.map(fn {close, i} ->
        %{close: Decimal.new(close), timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i * 60)}
      end)
    end

    defp rounded(values), do: Enum.map(values, &Decimal.to_string(Decimal.round(&1, 2)))

    test "matches the published Wilder RSI(14) values" do
      {:ok, results} = RSI.calculate(wilder_data(), period: 14)

      assert results |> Enum.map(& &1.value) |> rounded() == @wilder_rsi
    end

    test "Wilder smoothing uses the latest change, not a lagged window" do
      {:ok, results} = RSI.calculate(wilder_data(), period: 14)
      values = Enum.map(results, & &1.value)

      # a window lagging `period` changes behind repeats the first value
      assert values |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [a, b] -> a != b end)
    end

    test "batch and streaming give the same values" do
      data = wilder_data()
      {:ok, batch} = RSI.calculate(data, period: 14)

      {_state, streamed} =
        Enum.reduce(data, {RSI.init_state(period: 14), []}, fn point, {state, acc} ->
          {:ok, state, result} = RSI.update_state(state, point)
          {state, if(result, do: [result.value | acc], else: acc)}
        end)

      assert Enum.reverse(streamed) == Enum.map(batch, & &1.value)
    end

    test "calculates RSI with custom parameters" do
      data = create_test_data(20)

      {:ok, results} =
        RSI.calculate(data, period: 10, overbought: 80, oversold: 20, smoothing: :sma)

      assert length(results) > 0

      result = List.first(results)
      assert result.metadata.period == 10
      assert result.metadata.overbought == 80
      assert result.metadata.oversold == 20
      assert result.metadata.smoothing == :sma
    end

    test "works with price series input" do
      prices = [
        Decimal.new("100"),
        Decimal.new("102"),
        Decimal.new("101"),
        Decimal.new("103"),
        Decimal.new("105"),
        Decimal.new("104"),
        Decimal.new("106"),
        Decimal.new("108"),
        Decimal.new("107"),
        Decimal.new("109"),
        Decimal.new("111"),
        Decimal.new("110"),
        Decimal.new("112"),
        Decimal.new("114"),
        Decimal.new("113")
      ]

      {:ok, results} = RSI.calculate(prices, period: 14)

      assert length(results) == 1
      assert Decimal.is_decimal(List.first(results).value)
    end

    test "returns error for insufficient data" do
      data = create_test_data(5)

      {:error, error} = RSI.calculate(data, period: 14)

      assert %TradingIndicators.Errors.InsufficientData{} = error
      assert error.required == 15
      assert error.provided == 5
    end

    test "validates parameters" do
      data = create_test_data(20)

      # Invalid period
      {:error, error} = RSI.calculate(data, period: 0)
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.param == :period

      # Invalid source
      {:error, error} = RSI.calculate(data, source: :invalid)
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.param == :source

      # Invalid smoothing
      {:error, error} = RSI.calculate(data, smoothing: :invalid)
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.param == :smoothing

      # Invalid overbought level
      {:error, error} = RSI.calculate(data, overbought: 150)
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.param == :overbought

      # Invalid level relationship
      {:error, error} = RSI.calculate(data, overbought: 30, oversold: 70)
      assert %TradingIndicators.Errors.InvalidParams{} = error
      assert error.param == :levels
    end
  end

  describe "streaming functionality" do
    test "init_state/1 initializes proper state" do
      state = RSI.init_state(period: 14, overbought: 80, oversold: 20)

      assert state.period == 14
      assert state.source == :close
      assert state.overbought == 80
      assert state.oversold == 20
      assert state.gains == []
      assert state.losses == []
      assert is_nil(state.avg_gain)
      assert is_nil(state.avg_loss)
      assert state.count == 0
    end

    test "update_state/2 processes data points correctly" do
      state = RSI.init_state(period: 4)

      # First data point
      data_point1 = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}
      {:ok, state1, result1} = RSI.update_state(state, data_point1)

      assert state1.count == 1
      assert is_nil(state1.previous_close) == false
      # Not enough data yet
      assert is_nil(result1)

      # Add more data points
      data_points = [
        %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("101"), timestamp: ~U[2024-01-01 09:32:00Z]},
        %{close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:33:00Z]},
        %{close: Decimal.new("105"), timestamp: ~U[2024-01-01 09:34:00Z]}
      ]

      {final_state, final_result} =
        Enum.reduce(data_points, {state1, nil}, fn data_point, {acc_state, _} ->
          {:ok, new_state, result} = RSI.update_state(acc_state, data_point)
          {new_state, result}
        end)

      assert final_state.count == 5
      # Should have a result now
      assert is_map(final_result)
      assert final_result.metadata.indicator == "RSI"
      assert Decimal.is_decimal(final_result.value)
    end

    test "update_state/2 works with price series" do
      # RSI streaming requires OHLCV data points, not raw prices
      # This test shows that raw Decimal values should be handled properly
      state = RSI.init_state(period: 3, source: :close)

      # Create proper data points
      data_points = [
        %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]},
        %{close: Decimal.new("102"), timestamp: ~U[2024-01-01 09:31:00Z]},
        %{close: Decimal.new("101"), timestamp: ~U[2024-01-01 09:32:00Z]},
        %{close: Decimal.new("103"), timestamp: ~U[2024-01-01 09:33:00Z]}
      ]

      {_final_state, final_result} =
        Enum.reduce(data_points, {state, nil}, fn data_point, {acc_state, _} ->
          {:ok, new_state, result} = RSI.update_state(acc_state, data_point)
          {new_state, result}
        end)

      assert is_map(final_result)
      assert Decimal.is_decimal(final_result.value)
    end

    test "update_state/2 returns error for invalid state" do
      invalid_state = %{invalid: "state"}
      data_point = %{close: Decimal.new("100"), timestamp: ~U[2024-01-01 09:30:00Z]}

      {:error, error} = RSI.update_state(invalid_state, data_point)
      assert %TradingIndicators.Errors.StreamStateError{} = error
    end
  end

  describe "required_periods/0" do
    test "returns default required periods" do
      assert RSI.required_periods() == 15
    end
  end

  describe "required_periods/1" do
    test "returns configured required periods" do
      assert RSI.required_periods(period: 10) == 11
    end
  end

  describe "validate_params/1" do
    test "validates valid parameters" do
      assert :ok == RSI.validate_params(period: 14, source: :close, overbought: 70, oversold: 30)
    end

    test "validates empty parameters" do
      assert :ok == RSI.validate_params([])
    end

    test "rejects invalid parameter types" do
      {:error, error} = RSI.validate_params("not a list")
      assert %TradingIndicators.Errors.InvalidParams{} = error
    end
  end

  # Helper function to create test data
  defp create_test_data(count) do
    base_price = 100

    1..count
    |> Enum.map(fn i ->
      price = base_price + :rand.uniform(20) - 10

      %{
        close: Decimal.new(price),
        timestamp: DateTime.add(~U[2024-01-01 09:30:00Z], i * 60, :second)
      }
    end)
  end

  describe "parameter_metadata/0" do
    test "returns correct parameter metadata" do
      metadata = RSI.parameter_metadata()

      assert is_list(metadata)
      assert length(metadata) == 5

      # Verify period parameter
      period_param = Enum.find(metadata, fn p -> p.name == :period end)
      assert period_param != nil
      assert period_param.type == :integer
      assert period_param.default == 14
      assert period_param.required == false
      assert period_param.min == 1
      assert period_param.max == nil

      # Verify source parameter
      source_param = Enum.find(metadata, fn p -> p.name == :source end)
      assert source_param != nil
      assert source_param.type == :atom
      assert source_param.default == :close
      assert source_param.options == [:open, :high, :low, :close]

      # Verify overbought parameter
      overbought_param = Enum.find(metadata, fn p -> p.name == :overbought end)
      assert overbought_param != nil
      assert overbought_param.type == :integer
      assert overbought_param.default == 70
      assert overbought_param.min == 0
      assert overbought_param.max == 100

      # Verify oversold parameter
      oversold_param = Enum.find(metadata, fn p -> p.name == :oversold end)
      assert oversold_param != nil
      assert oversold_param.type == :integer
      assert oversold_param.default == 30
      assert oversold_param.min == 0
      assert oversold_param.max == 100

      # Verify smoothing parameter
      smoothing_param = Enum.find(metadata, fn p -> p.name == :smoothing end)
      assert smoothing_param != nil
      assert smoothing_param.type == :atom
      assert smoothing_param.default == :wilder
      assert smoothing_param.options == [:wilder, :sma]
    end

    test "all metadata maps have required fields" do
      metadata = RSI.parameter_metadata()

      Enum.each(metadata, fn param ->
        assert Map.has_key?(param, :name)
        assert Map.has_key?(param, :type)
        assert Map.has_key?(param, :default)
        assert Map.has_key?(param, :required)
        assert Map.has_key?(param, :min)
        assert Map.has_key?(param, :max)
        assert Map.has_key?(param, :options)
        assert Map.has_key?(param, :description)
      end)
    end
  end

  describe "output_fields_metadata/0" do
    test "returns correct metadata for single-value indicator" do
      metadata = RSI.output_fields_metadata()

      assert metadata.type == :single_value
      assert is_binary(metadata.description)
      assert is_binary(metadata.example)
      assert metadata.fields == nil
    end

    test "metadata has all required fields" do
      metadata = RSI.output_fields_metadata()

      assert Map.has_key?(metadata, :type)
      assert Map.has_key?(metadata, :description)
      assert Map.has_key?(metadata, :example)
      assert Map.has_key?(metadata, :fields)
    end
  end
end
