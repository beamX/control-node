# Control Node

![ci-test](https://github.com/beamX/control-node/workflows/ci-test/badge.svg)

🚀 **Continuous Delivery and Orchestration as code for Elixir**

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

## TL;DR

`control_node` is an Elixir library which allows you to build your own deployment
and orchestration workflows i.e. given a release tar of an Elixir/Erlang project
`control_node` allows you to deploy the release to hosts VMs and monitor the same thereafter.

## Pre-requesites

In oder to use `control_node` you must ensure the following,

- You are deploying to bare metal servers or virtual machines
- Your Erlang/Elixir project when started should run the EPMD (it runs by default if you don't change the config)


## Features

- [x] Support multiple namespaces for a release
- [x] Rollout releases to hosts via SSH
- [ ] Support namespace environment variable configuration
- [ ] Natively Monitor(health check)/restart nodes
- [ ] Hot upgrade your release config
- [ ] Dynamically scale up/down your release instances
- [ ] Rollback releases


## Quick example

TODO

### SSH server config to enable tunneling
In order to ensure that Control Node can connect to release node the SSH servers running
the release should allow tunneling,

```
...
AllowTcpForwarding yes
...
```

## Limiation

- Only shortnames for nodes are allowed
- Instances of same release (deployed to different) should have different
  hostname i.e. for eg. if node 1 has node name `service_app@host1` then another
  node of `service_app` should have a different node name.
- SSH client cannot read new format of RSA keys, should be convered to PEM format
