defmodule ControlNode.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # Store (node, host, port) mappings used for connecting to remote nodes
    :control_node_epmd = :ets.new(:control_node_epmd, [:named_table, :public])

    ControlNode.Inet.configure_lookup()

    children = [
      # Starts a worker by calling: ControlNode.Worker.start_link(arg)
      # {ControlNode.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ControlNode.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
