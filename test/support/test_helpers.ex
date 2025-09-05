defmodule TradingIndicators.TestSupport.TestHelpers do
  @moduledoc """
  Common test utilities and helper functions for comprehensive testing.
  """

  alias TradingIndicators.TestSupport.DataGenerator
  import ExUnit.Assertions

  @doc """
  Asserts that two decimal values are approximately equal within tolerance.
  """
  def assert_decimal_equal(actual, expected, tolerance \\ "0.0001") do
    tolerance_decimal = Decimal.new(tolerance)
    diff = Decimal.abs(Decimal.sub(actual, expected))

    if Decimal.gt?(diff, tolerance_decimal) do
      ExUnit.Assertions.flunk("""
      Values not equal within tolerance #{tolerance}
      Expected: #{expected}
      Actual:   #{actual}
      Diff:     #{diff}
      """)
    end
  end

  @doc """
  Asserts that a list of decimal values are approximately equal within tolerance.
  """
  def assert_decimal_list_equal(actual_list, expected_list, tolerance \\ "0.0001") do
    if length(actual_list) != length(expected_list) do
      ExUnit.Assertions.flunk("Lists have different lengths")
    end

    Enum.zip(actual_list, expected_list)
    |> Enum.with_index()
    |> Enum.each(fn {{actual, expected}, index} ->
      try do
        assert_decimal_equal(actual, expected, tolerance)
      rescue
        ExUnit.AssertionError ->
          ExUnit.Assertions.flunk("Lists differ at index #{index}: #{actual} != #{expected}")
      end
    end)
  end

  @doc """
  Asserts that a function raises a specific error with expected message.
  """
  def assert_error_raised(fun, expected_error, expected_message_pattern \\ nil) do
    try do
      fun.()
      ExUnit.Assertions.flunk("Expected #{expected_error} to be raised but nothing was raised")
    rescue
      error ->
        if error.__struct__ != expected_error do
          ExUnit.Assertions.flunk("Expected #{expected_error} but got #{error.__struct__}")
        end

        if expected_message_pattern &&
             !String.contains?(Exception.message(error), expected_message_pattern) do
          ExUnit.Assertions.flunk("""
          Expected error message to contain "#{expected_message_pattern}"
          Actual message: "#{Exception.message(error)}"
          """)
        end
    end
  end

  @doc """
  Asserts that all values in a list are finite decimals (not NaN or infinite).
  """
  def assert_all_finite(values) do
    Enum.each(values, fn value ->
      if Decimal.nan?(value) || Decimal.inf?(value) do
        ExUnit.Assertions.flunk("Expected finite value but got #{value}")
      end
    end)
  end

  @doc """
  Measures execution time of a function in microseconds.
  """
  def measure_execution_time(fun) do
    start_time = System.monotonic_time(:microsecond)
    result = fun.()
    end_time = System.monotonic_time(:microsecond)
    execution_time = end_time - start_time
    {result, execution_time}
  end

  @doc """
  Generates test data with specific patterns for edge case testing.
  """
  def edge_case_data do
    %{
      empty: [],
      single: [Decimal.new("100.0")],
      two_values: [Decimal.new("100.0"), Decimal.new("101.0")],
      constant: List.duplicate(Decimal.new("100.0"), 10),
      ascending: 1..10 |> Enum.map(&Decimal.new/1),
      descending: 10..1//-1 |> Enum.map(&Decimal.new/1),
      alternating: [100, 90, 110, 85, 115] |> Enum.map(&Decimal.new/1),
      with_zeros: [100, 0, 50, 0, 25] |> Enum.map(&Decimal.new/1),
      large_numbers: [1_000_000, 2_000_000, 3_000_000] |> Enum.map(&Decimal.new/1),
      small_numbers: ["0.001", "0.002", "0.003"] |> Enum.map(&Decimal.new/1)
    }
  end

  @doc """
  Validates that a result conforms to expected structure and constraints.
  """
  def validate_indicator_result(result, expected_length, value_constraints \\ []) do
    # Check structure
    assert is_list(result), "Result should be a list"

    assert length(result) == expected_length,
           "Expected length #{expected_length}, got #{length(result)}"

    # Check all values are valid decimals
    assert_all_finite(result)

    # Apply additional constraints
    Enum.each(value_constraints, fn
      {:min, min_val} ->
        Enum.each(result, fn val ->
          assert Decimal.gte?(val, Decimal.new(min_val)),
                 "Value #{val} should be >= #{min_val}"
        end)

      {:max, max_val} ->
        Enum.each(result, fn val ->
          assert Decimal.lte?(val, Decimal.new(max_val)),
                 "Value #{val} should be <= #{max_val}"
        end)

      {:positive} ->
        Enum.each(result, fn val ->
          assert Decimal.gt?(val, Decimal.new("0")),
                 "Value #{val} should be positive"
        end)

      {:non_negative} ->
        Enum.each(result, fn val ->
          assert Decimal.gte?(val, Decimal.new("0")),
                 "Value #{val} should be non-negative"
        end)
    end)
  end

  @doc """
  Creates test data with known statistical properties for validation.
  """
  def create_statistical_test_data do
    # Create data with known mean and standard deviation
    base_values = [100, 102, 98, 105, 95, 103, 97, 108, 92, 106]

    %{
      values: Enum.map(base_values, &Decimal.new/1),
      known_mean: Decimal.new("100.6"),
      # Approximate
      known_std: Decimal.new("5.46"),
      # Approximate
      known_variance: Decimal.new("29.84")
    }
  end

  @doc """
  Memory usage tracking utility for performance tests.
  """
  def measure_memory_usage(fun) do
    :erlang.garbage_collect()
    initial_memory = :erlang.process_info(self(), :memory) |> elem(1)

    result = fun.()

    :erlang.garbage_collect()
    final_memory = :erlang.process_info(self(), :memory) |> elem(1)

    memory_used = final_memory - initial_memory
    {result, memory_used}
  end

  @doc """
  Stress test helper that applies function to increasingly large datasets.
  """
  def stress_test_scaling(indicator_fun, max_size \\ 10_000, step \\ 1_000) do
    step..max_size//step
    |> Enum.map(fn size ->
      data = DataGenerator.sample_prices(size)
      {result, time} = measure_execution_time(fn -> indicator_fun.(data) end)
      {size, time, byte_size(:erlang.term_to_binary(result))}
    end)
  end

  @doc """
  Property test helper for validating mathematical properties.
  """
  def validate_mathematical_properties(values, result) when is_list(values) and is_list(result) do
    # Monotonicity check for appropriate indicators
    check_result_consistency(values, result)
  end

  defp check_result_consistency(values, result) do
    # Basic consistency checks
    assert length(result) <= length(values), "Result cannot be longer than input"
    assert_all_finite(result)

    # Check for reasonable bounds (indicator-specific)
    unless Enum.empty?(result) do
      min_input = Enum.min(values, Decimal)
      max_input = Enum.max(values, Decimal)
      min_result = Enum.min(result, Decimal)
      max_result = Enum.max(result, Decimal)

      # Most indicators should produce results within reasonable bounds of input
      input_range = Decimal.sub(max_input, min_input)
      acceptable_lower = Decimal.sub(min_input, input_range)
      acceptable_upper = Decimal.add(max_input, input_range)

      assert Decimal.gte?(min_result, acceptable_lower),
             "Minimum result #{min_result} outside acceptable range"

      assert Decimal.lte?(max_result, acceptable_upper),
             "Maximum result #{max_result} outside acceptable range"
    end
  end

  @doc """
  Checks if all values in a list are finite decimals.
  """
  def all_finite?(values) when is_list(values) do
    Enum.all?(values, fn value ->
      not (Decimal.nan?(value) || Decimal.inf?(value))
    end)
  end

  def all_finite?(_), do: false
end
