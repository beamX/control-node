defmodule ControlNode.MixProject do
  use Mix.Project

  @source_url "https://github.com/beamX/control-node"

  def project do
    [
      name: "Control Node",
      app: :control_node,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: true],
      package: package(),
      deps: deps(),
      description: description(),
      docs: docs()
    ]
  end

  defp description do
    """
    Continuous Delivery and Orchestration as code for Elixir/Erlang
    """
  end

  defp package do
    [
      files: ["lib", "priv", "mix.exs", "README.md", "LICENSE", ".formatter.exs"],
      maintainers: ["Vanshdeep Singh"],
      licenses: ["MIT"],
      links: %{
        Changelog: "#{@source_url}/blob/master/CHANGELOG.md",
        GitHub: @source_url
      }
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :ssh],
      mod: {ControlNode.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:mock, "~> 0.3.0", only: :test},
      {:ex_machina, "~> 2.4", only: :test},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.22", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extras: [
        "CHANGELOG.md",
        "README.md",
        "TESTING.md"
      ]
    ]
  end
end
