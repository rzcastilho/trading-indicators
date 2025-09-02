ExUnit.start()

# Configuration for comprehensive testing
ExUnit.configure(
  exclude: [
    :integration,    # Exclude integration tests by default (run with --include integration)
    :benchmark,      # Exclude benchmark tests by default (run with --include benchmark)
    :property,       # Exclude property tests by default (run with --include property)
    :stress         # Exclude stress tests by default (run with --include stress)
  ],
  timeout: 60_000,   # Increase timeout for comprehensive tests
  max_cases: System.schedulers_online() * 2 # Optimize parallel execution
)

# Test support modules are loaded from test/support/
