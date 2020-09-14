# Control Node

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `control_node` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:control_node, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/control_node](https://hexdocs.pm/control_node**.


# Developement

## Stage 1

**Assumptions**
- Elixir release tar.gz file is available

### TODO Support App definition config

```elixir
%ControlNode.Application{
  name: :my_production_app,
  deployment_strategy: :restart,
}
```

### TODO Support Namespace configuration

```elixir
%ControlNode.Namespace{
  name: :staging,
  deployment_hosts: ["host-1", "host-2"],
  applications: [%ControlNode.Application{}]
}
```
