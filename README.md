# Control Node

![ci-test](https://github.com/beamX/control-node/workflows/ci-test/badge.svg)

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
be found at [https://hexdocs.pm/control_node](https://hexdocs.pm/control_node)


## SSHD config to enable tunneling

```
AllowTcpForwarding yes
```

## Limiation

- Only shortnames are allowed for release nodes
- Instances of same release (deployed to different) should have different
  hostname i.e. for eg. if node 1 has node name `service_app@host1` then another
  node of `service_app` should have a different node name.
- SSH client cannot read new format of RSA keys, should be convered to PEM format
