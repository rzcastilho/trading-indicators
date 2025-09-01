defmodule TradingIndicators.MixProject do
  use Mix.Project

  def project do
    [
      app: :trading_indicators,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "TradingIndicators",
      source_url: "https://github.com/rzcastilho/trading_indicators",
      docs: [
        main: "TradingIndicators",
        extras: ["README.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {TradingIndicators.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:decimal, "~> 2.0"},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.1", only: :dev},
      {:stream_data, "~> 0.6", only: :test}
    ]
  end

  defp description do
    "A comprehensive Elixir library for trading indicators with consistent APIs, proper error handling, and extensible architecture."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/rzcastilho/trading_indicators"},
      maintainers: ["castilho"]
    ]
  end
end
