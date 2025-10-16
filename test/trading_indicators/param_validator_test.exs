defmodule TradingIndicators.ParamValidatorTest do
  use ExUnit.Case, async: true

  alias TradingIndicators.{ParamValidator, Types, Errors}

  describe "validate_params/2" do
    setup do
      metadata = [
        %Types.ParamMetadata{
          name: :period,
          type: :integer,
          default: 20,
          required: false,
          min: 1,
          max: 100,
          options: nil,
          description: "Number of periods"
        },
        %Types.ParamMetadata{
          name: :source,
          type: :atom,
          default: :close,
          required: false,
          min: nil,
          max: nil,
          options: [:open, :high, :low, :close],
          description: "Source price field"
        },
        %Types.ParamMetadata{
          name: :multiplier,
          type: :float,
          default: 2.0,
          required: false,
          min: 0.0,
          max: 10.0,
          options: nil,
          description: "Multiplier value"
        },
        %Types.ParamMetadata{
          name: :required_field,
          type: :integer,
          default: nil,
          required: true,
          min: nil,
          max: nil,
          options: nil,
          description: "Required parameter"
        }
      ]

      {:ok, metadata: metadata}
    end

    test "validates valid parameters successfully", %{metadata: metadata} do
      params = [period: 20, source: :close, multiplier: 2.5, required_field: 10]
      assert :ok = ParamValidator.validate_params(params, metadata)
    end

    test "validates parameters with only required fields", %{metadata: metadata} do
      params = [required_field: 5]
      assert :ok = ParamValidator.validate_params(params, metadata)
    end

    test "validates empty params when no required fields", _context do
      metadata = [
        %Types.ParamMetadata{
          name: :period,
          type: :integer,
          default: 20,
          required: false,
          min: 1,
          max: nil,
          options: nil,
          description: "Number of periods"
        }
      ]

      assert :ok = ParamValidator.validate_params([], metadata)
    end

    test "returns error for invalid integer type", %{metadata: metadata} do
      params = [period: "20", required_field: 1]

      assert {:error, %Errors.InvalidParams{param: :period, expected: "integer"}} =
               ParamValidator.validate_params(params, metadata)
    end

    test "returns error for invalid atom type", %{metadata: metadata} do
      params = [source: "close", required_field: 1]

      assert {:error, %Errors.InvalidParams{param: :source, expected: "atom"}} =
               ParamValidator.validate_params(params, metadata)
    end

    test "returns error for invalid float type", %{metadata: metadata} do
      params = [multiplier: "2.5", required_field: 1]

      assert {:error, %Errors.InvalidParams{param: :multiplier, expected: "float or number"}} =
               ParamValidator.validate_params(params, metadata)
    end

    test "accepts integer for float type", %{metadata: metadata} do
      params = [multiplier: 2, required_field: 1]
      assert :ok = ParamValidator.validate_params(params, metadata)
    end

    test "returns error for value below minimum", %{metadata: metadata} do
      params = [period: 0, required_field: 1]

      assert {:error, %Errors.InvalidParams{param: :period, expected: "value >= 1"}} =
               ParamValidator.validate_params(params, metadata)
    end

    test "returns error for value above maximum", %{metadata: metadata} do
      params = [period: 101, required_field: 1]

      assert {:error, %Errors.InvalidParams{param: :period, expected: "value <= 100"}} =
               ParamValidator.validate_params(params, metadata)
    end

    test "accepts value at minimum boundary", %{metadata: metadata} do
      params = [period: 1, required_field: 1]
      assert :ok = ParamValidator.validate_params(params, metadata)
    end

    test "accepts value at maximum boundary", %{metadata: metadata} do
      params = [period: 100, required_field: 1]
      assert :ok = ParamValidator.validate_params(params, metadata)
    end

    test "returns error for invalid option", %{metadata: metadata} do
      params = [source: :invalid, required_field: 1]

      assert {:error,
              %Errors.InvalidParams{
                param: :source,
                expected: "one of [:open, :high, :low, :close]"
              }} = ParamValidator.validate_params(params, metadata)
    end

    test "accepts valid option", %{metadata: metadata} do
      params = [source: :high, required_field: 1]
      assert :ok = ParamValidator.validate_params(params, metadata)
    end

    test "returns error for missing required parameter", %{metadata: metadata} do
      params = [period: 20, source: :close]

      assert {:error,
              %Errors.InvalidParams{
                param: :required_field,
                expected: "required parameter",
                message: message
              }} = ParamValidator.validate_params(params, metadata)

      assert message =~ "Required parameter 'required_field' is missing"
    end

    test "allows unknown parameters (permissive approach)", %{metadata: metadata} do
      params = [unknown_param: 123, required_field: 1]
      assert :ok = ParamValidator.validate_params(params, metadata)
    end

    test "validates parameters with no constraints", _context do
      metadata = [
        %Types.ParamMetadata{
          name: :value,
          type: :integer,
          default: 0,
          required: false,
          min: nil,
          max: nil,
          options: nil,
          description: "Value without constraints"
        }
      ]

      params = [value: 999_999]
      assert :ok = ParamValidator.validate_params(params, metadata)
    end

    test "returns error for non-keyword list params", %{metadata: metadata} do
      assert {:error, %Errors.InvalidParams{expected: "keyword list"}} =
               ParamValidator.validate_params(%{period: 20}, metadata)
    end
  end

  describe "validate_params/2 with string type" do
    test "validates string parameters" do
      metadata = [
        %Types.ParamMetadata{
          name: :label,
          type: :string,
          default: "default",
          required: false,
          min: nil,
          max: nil,
          options: nil,
          description: "Label string"
        }
      ]

      assert :ok = ParamValidator.validate_params([label: "test"], metadata)

      assert {:error, %Errors.InvalidParams{param: :label, expected: "string"}} =
               ParamValidator.validate_params([label: :atom], metadata)
    end

    test "validates string options" do
      metadata = [
        %Types.ParamMetadata{
          name: :mode,
          type: :string,
          default: "default",
          required: false,
          min: nil,
          max: nil,
          options: ["fast", "slow", "medium"],
          description: "Processing mode"
        }
      ]

      assert :ok = ParamValidator.validate_params([mode: "fast"], metadata)

      assert {:error, %Errors.InvalidParams{param: :mode}} =
               ParamValidator.validate_params([mode: "invalid"], metadata)
    end
  end

  describe "validate_params/2 with float range constraints" do
    test "validates float minimum constraint" do
      metadata = [
        %Types.ParamMetadata{
          name: :threshold,
          type: :float,
          default: 0.5,
          required: false,
          min: 0.0,
          max: nil,
          options: nil,
          description: "Threshold value"
        }
      ]

      assert :ok = ParamValidator.validate_params([threshold: 0.0], metadata)
      assert :ok = ParamValidator.validate_params([threshold: 1.5], metadata)

      assert {:error, %Errors.InvalidParams{param: :threshold, expected: "value >= 0.0"}} =
               ParamValidator.validate_params([threshold: -0.1], metadata)
    end

    test "validates float maximum constraint" do
      metadata = [
        %Types.ParamMetadata{
          name: :ratio,
          type: :float,
          default: 0.5,
          required: false,
          min: 0.0,
          max: 1.0,
          options: nil,
          description: "Ratio value"
        }
      ]

      assert :ok = ParamValidator.validate_params([ratio: 0.5], metadata)
      assert :ok = ParamValidator.validate_params([ratio: 1.0], metadata)

      assert {:error, %Errors.InvalidParams{param: :ratio, expected: "value <= 1.0"}} =
               ParamValidator.validate_params([ratio: 1.1], metadata)
    end
  end

  describe "validate_params/2 integration with actual indicators" do
    test "validates RSI parameters using actual metadata" do
      alias TradingIndicators.Momentum.RSI

      metadata = RSI.parameter_metadata()

      # Valid parameters
      assert :ok = ParamValidator.validate_params([period: 14, source: :close], metadata)

      # Invalid period (too low)
      assert {:error, %Errors.InvalidParams{param: :period}} =
               ParamValidator.validate_params([period: 0], metadata)

      # Invalid source option
      assert {:error, %Errors.InvalidParams{param: :source}} =
               ParamValidator.validate_params([source: :invalid], metadata)
    end

    test "validates SMA parameters using actual metadata" do
      alias TradingIndicators.Trend.SMA

      metadata = SMA.parameter_metadata()

      # Valid parameters
      assert :ok = ParamValidator.validate_params([period: 20, source: :close], metadata)

      # Invalid period type
      assert {:error, %Errors.InvalidParams{param: :period, expected: "integer"}} =
               ParamValidator.validate_params([period: "20"], metadata)
    end

    test "validates Bollinger Bands parameters using actual metadata" do
      alias TradingIndicators.Volatility.BollingerBands

      metadata = BollingerBands.parameter_metadata()

      # Valid parameters
      assert :ok =
               ParamValidator.validate_params([period: 20, multiplier: 2.0, source: :close],
                 metadata
               )

      # Invalid multiplier (negative)
      assert {:error, %Errors.InvalidParams{param: :multiplier}} =
               ParamValidator.validate_params([multiplier: -1.0], metadata)
    end

    test "validates indicators with no parameters (OBV)" do
      alias TradingIndicators.Volume.OBV

      metadata = OBV.parameter_metadata()

      # Empty metadata, empty params should validate
      assert :ok = ParamValidator.validate_params([], metadata)

      # Even unknown params should pass (permissive)
      assert :ok = ParamValidator.validate_params([unknown: 1], metadata)
    end

    test "validates VWAP parameters using actual metadata" do
      alias TradingIndicators.Volume.VWAP

      metadata = VWAP.parameter_metadata()

      # Valid parameters
      assert :ok = ParamValidator.validate_params([variant: :close, session_reset: :daily], metadata)

      # Invalid variant
      assert {:error, %Errors.InvalidParams{param: :variant}} =
               ParamValidator.validate_params([variant: :invalid], metadata)

      # Invalid session_reset
      assert {:error, %Errors.InvalidParams{param: :session_reset}} =
               ParamValidator.validate_params([session_reset: :yearly], metadata)
    end
  end

  describe "validate_params/2 error messages" do
    test "provides clear error message for type mismatch" do
      metadata = [
        %Types.ParamMetadata{
          name: :count,
          type: :integer,
          default: 10,
          required: false,
          min: nil,
          max: nil,
          options: nil,
          description: "Count value"
        }
      ]

      assert {:error, error} = ParamValidator.validate_params([count: "ten"], metadata)
      assert error.message =~ "must be an integer"
      assert error.message =~ "count"
    end

    test "provides clear error message for range violation" do
      metadata = [
        %Types.ParamMetadata{
          name: :size,
          type: :integer,
          default: 50,
          required: false,
          min: 10,
          max: 100,
          options: nil,
          description: "Size value"
        }
      ]

      assert {:error, error} = ParamValidator.validate_params([size: 5], metadata)
      assert error.message =~ "must be >= 10"
      assert error.message =~ "size"

      assert {:error, error} = ParamValidator.validate_params([size: 150], metadata)
      assert error.message =~ "must be <= 100"
    end

    test "provides clear error message for invalid option" do
      metadata = [
        %Types.ParamMetadata{
          name: :mode,
          type: :atom,
          default: :fast,
          required: false,
          min: nil,
          max: nil,
          options: [:fast, :slow],
          description: "Mode"
        }
      ]

      assert {:error, error} = ParamValidator.validate_params([mode: :medium], metadata)
      assert error.message =~ "must be one of [:fast, :slow]"
      assert error.message =~ "mode"
    end
  end
end
