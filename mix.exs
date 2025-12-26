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
      {:req, "~> 0.5"},
      {:joken, "~> 2.0"},
      {:jason, "~> 1.4"},
      {:uuid, "~> 1.1"},
      {:x509, "~> 0.9"},
      {:timex, "~> 3.7"}
    ]
  end
end
