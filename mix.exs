defmodule Eqmi.MixProject do
  use Mix.Project

  @version "0.0.1"
  def project do
    [
      app: :eqmi,
      version: @version,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      docs: [extras: ["README.md"], main: "readme"],
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
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false},
      {:jason, "~> 1.2"},
      {:gen_state_machine, "~> 3.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp description() do
    "QMI (Qualcomm MSM Interface) client implementation in Elixir."
  end

  defp package() do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/nadsat/eqmi"}
    ]
  end
end
