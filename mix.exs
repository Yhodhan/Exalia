defmodule Exalia.MixProject do
  use Mix.Project

  def project do
    [
      app: :exalia,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      config_path: "config/config.exs"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {Exalia.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bencoder, github: "Yhodhan/Bencoder", branch: "master"}
    ]
  end
end
