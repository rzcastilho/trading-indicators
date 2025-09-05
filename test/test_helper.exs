ExUnit.start()

# Configuration for comprehensive testing
ExUnit.configure(
  exclude: [
    # Exclude integration tests by default (run with --include integration)
    :integration,
    # Exclude integration tests by default (run with --include performance)
    :performance,
    # Exclude property tests by default (run with --include property)
    :property
  ],
  # Increase timeout for comprehensive tests
  timeout: 60_000,
  # Optimize parallel execution
  max_cases: System.schedulers_online() * 2
)

# Test support modules are loaded from test/support/
