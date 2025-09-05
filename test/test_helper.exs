ExUnit.start()

# Configuration for comprehensive testing
ExUnit.configure(
  exclude: [
    # Exclude integration tests by default (run with --include integration)
    :integration,
    # Exclude benchmark tests by default (run with --include benchmark)
    :benchmark,
    # Exclude property tests by default (run with --include property)
    :property,
    # Exclude stress tests by default (run with --include stress)
    :stress
  ],
  # Increase timeout for comprehensive tests
  timeout: 60_000,
  # Optimize parallel execution
  max_cases: System.schedulers_online() * 2
)

# Test support modules are loaded from test/support/
