defmodule ExMicrosoftAzureUtils.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_microsoft_azure_utils,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ibrowse, "~> 4.4"},
      {:joken, "~> 1.5"},
      {:tesla, "~> 0.8"},
      {:poison, ">= 1.0.0"},
      {:uuid, "~> 1.1"},
      {:x509, "~> 0.1.1"},
      {:timex, "~> 3.7"}
    ]
  end
end
