# Control Node

[![github.com](https://github.com/beamX/control-node/workflows/ci-test/badge.svg)](https://github.com/beamX/control-node/actions)
[![hex.pm](https://img.shields.io/hexpm/v/control_node.svg)](https://hex.pm/packages/control_node)
[![hexdocs.pm](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/control_node/)
[![hex.pm](https://img.shields.io/hexpm/dt/control_node.svg)](https://hex.pm/packages/control_node)
[![hex.pm](https://img.shields.io/hexpm/l/control_node.svg)](https://hex.pm/packages/control_node)
[![github.com](https://img.shields.io/github/last-commit/beamX/control-node.svg)](https://github.com/beamX/control-node/commits/master)

🚀 **Continuous Delivery and Orchestration as code for Elixir**

## Installation

```elixir
def deps do
  [
    {:control_node, "~> 0.1.0"}
  ]
end
```

## TL;DR

`control_node` is an Elixir library which allows you to build your own deployment
and orchestration workflows i.e. given a release tar of an Elixir/Erlang project
`control_node` allows you to deploy the release to hosts VMs and monitor the same thereafter.

## Pre-requisites

In order to use `control_node` you must ensure the following,

- You are deploying to bare metal servers or virtual machines
- Your Erlang/Elixir project when started should run the EPMD (it runs by default if you don't change the config)

## Features

- [x] Support multiple namespaces for a release
- [x] Rollout releases to hosts via SSH
- [ ] Natively Monitor(health check)/restart nodes
- [ ] Support namespace environment variable configuration
- [ ] Hot upgrade your release config
- [ ] Dynamically scale up/down your release instances
- [ ] Rollback releases

## Quick example

This library ships with an example `service_app` under `example/` folder. You can try out this library
by trying to deploy the release using the following steps,

Clone the repo
```
$ git clone https://github.com/beamX/control-node
$ cd control-code/
```

Start an SSH server locally where the release will be deployed,
```
$ docker-compose up -d
```

Start `iex` and define `ServiceApp` module which will offer API to deploy `service_app`,
```elixir
$ iex -S mix
Erlang/OTP 23 [erts-11.0] [source] [64-bit] [smp:8:8] [ds:8:8:10] [async-threads:1] [hipe]

Interactive Elixir (1.10.4) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)> :net_kernel.start([:control_node_test, :shortnames])
iex(control_node_test@hostname)2> defmodule ServiceApp do
  use ControlNode.Release,
    spec: %ControlNode.Release.Spec{name: :service_app, base_path: "/app/service_app"}
end
```

Declare a `host_spec` which will hold the details of which host the release can be deployed to
```elixir
iex(control_node_test@hostname)3> host_spec = %ControlNode.Host.SSH{
  host: "localhost",
  port: 2222,
  user: "linuxserver.io",
  private_key_dir: Path.join([File.cwd!(), "test/fixture", "host-vm/.ssh"])
}
```

Declare a `namespace_spec` which define the namespace for a given release. Notice that the
namespace allows specifying a list of `hosts` and `registry`.
A registry module offers API to retrieve the release tar and here we use a `Local` registry
which will retrieve the release tar from the filesystem.

```elixir
iex(control_node_test@hostname)4> namespace_spec = %ControlNode.Namespace.Spec{
  tag: :testing,
  hosts: [host_spec],
  registry_spec: %ControlNode.Registry.Local{path: Path.join(File.cwd!(), "example")},
  deployment_type: :incremental_replace,
  release_cookie: :"YFWZXAOJGTABHNGIT6KVAC2X6TEHA6WCIRDKSLFD6JZWRC4YHMMA===="
}
```

Now we deploy the release to a given `namespace_spec` i.e. the release we be started on on
all the `hosts` specified in the namespace. Notice that once the deployment is finished
`control_node_test@hostname` automatically connects to release nodes,

```elixir
iex(control_node_test@hostname)5> ServiceApp.start_link(namespace_spec)
iex(control_node_test@hostname)6> ServiceApp.deploy(:testing, "0.1.0")
iex(control_node_test@hostname)7> Node.list()
```

### SSH server config to enable tunneling
In order to ensure that Control Node can connect to release node the SSH servers running
the release should allow tunneling,

```
...
AllowTcpForwarding yes
...
```

## Limitation

- Only short names for nodes are allowed
- Instances of same release (deployed to different) should have different
  hostname i.e. for eg. if node 1 has node name `service_app@host1` then another
  node of `service_app` should have a different node name.
- SSH client cannot read new format of RSA keys, should be converted to PEM format
