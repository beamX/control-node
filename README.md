# Control Node

[![github.com](https://github.com/beamX/control-node/workflows/ci-test/badge.svg)](https://github.com/beamX/control-node/actions)
[![hex.pm](https://img.shields.io/hexpm/v/control_node.svg)](https://hex.pm/packages/control_node)
[![hexdocs.pm](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/control_node/)

🚀 **Continuous Delivery and Orchestration as code for Elixir**

## Installation

```elixir
def deps do
  [
    {:control_node, "~> 0.7.0"}
  ]
end
```

## Introduction

`control_node` is a Elixir library that enables building custom continous
delivery and orchestration service. It offers APIs to store release tars and
deploy them to remote hosts (via **SSH**), monitor and manage deployed
service nodes.

## Pre-requisites

In order to build with `control_node` you must ensure the following,

- **Control node should have SSH access to all host machines where releases will be deployed**
- **Deployed Elixir services should register with EPMD** (this happens by default when an Elixir
  release is started if you don't change the config)

## Features

- [x] Support multiple namespaces for a release
- [x] Rollout releases to hosts via SSH
- [x] Native node monitoring and restart on failover
- [x] Dynamically scale up/down your release instances
- [x] Native service monitoring/health check
- [x] Blue-Green deployment
- [x] Support failover via [heart](http://erlang.org/doc/man/heart.html)
- [x] Rollback releases
- [x] Support namespace environment variable configuration
- [ ] Support package registries other than local file system

## Quick example

Control node ships with an example `service_app` under `example/` folder which
can be used to create an example service deployment. Below are the details,


Clone the repo and start a remote docker SSH server where the release will be
deployed,

```
$ git clone https://github.com/beamX/control-node
$ cd control-code/
$ docker-compose up -d  # start a SSH server
```

Start `iex` with distribution turned on

```elixir
$ iex -S mix
Erlang/OTP 23 [erts-11.0] [source] [64-bit] [smp:8:8] [ds:8:8:10] [async-threads:1] [hipe]

Interactive Elixir (1.10.4) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)> :net_kernel.start([:control_node_test, :shortnames])
iex(control_node_test@hostname)2> 
```

### Define the release

```elixir
defmodule ServiceApp do
  use ControlNode.Release,
    spec: %ControlNode.Release.Spec{name: :service_app, base_path: "/app/service_app"}
end
```
- `ServiceApp` module exposes APIs to deploy the release


### Define a host to deploy to

```elixir
host_spec = %ControlNode.Host.SSH{
  host: "localhost",
  port: 2222,
  user: "linuxserver.io",
  private_key_dir: Path.join([File.cwd!(), "test/fixture", "host-vm/.ssh"])
}
```

- `host_spec` host the configuration of a single host the release can be deployed to


### Declare a namespace 

- This defines the environment for a given release

```elixir
namespace_spec = %ControlNode.Namespace.Spec{
  tag: :testing,
  hosts: [host_spec],
  registry_spec: %ControlNode.Registry.Local{path: Path.join(File.cwd!(), "example")},
  deployment_type: :incremental_replace,
  release_cookie: :"YFWZXAOJGTABHNGIT6KVAC2X6TEHA6WCIRDKSLFD6JZWRC4YHMMA===="
}
```

- `registry` defines where to download the release tarball from
  - `%ControlNode.Registry.Local{}` defines that release tarball will be fetched from local filesystem
- `hosts` defines a list of servers where the release will be deployed


### Deploy the release

```elixir
{:ok, namespace_manager} = ControlNode.Namespace.start_link(namespace_spec, ServiceApp)
ControlNode.Namespace.deploy(namespace_manager, "0.1.0")
Node.list()
```

- The above deploys the release to `namespace_spec` environment i.e. the release
  we be started on all the `hosts` specified in the `namespace_spec`. 
  - NOTE that once the deployment is finished `control_node_test@hostname`
    automatically connects to release nodes,


### Connect and observe with observer

Once `Node.list()` shows that the control node is connected to the release nodes
then `observer` can be used to observe and inspect the remote nodes,

```elixir
l(:observer)
:observer.start()
```

## Real world example

https://github.com/kansi/cnops (a bit outdated)


## Can control node be used to deploy non Elixir/Erlang project?

Yes! The general idea would be to compile target project into a command and run
and monitor that command from an elixir service. This maybe more work but you
have the option of avoiding multiple deploy tools

https://github.com/kansi/cnops deploys a Golang service `hello_go`

NOTE: The above is old but still valid inspiration


## Under the hood

<img src="./assets/how_it_works.png" alt="How it works" width="700"/>

- Upon starting, `control_node` will try to connect to EMPD process for each
  specified host and gather info regarding running services on each host
- In case a service managed by control is already running on a given node
  control node will retrieve the current running version and start monitoring
  the release
- In case no service is found running on a given host, `control_node` will
  establish a connection to the host and wait for a deployment command to be
  issued
- If any of the monitored service nodes goes down control node will attempt
  (max. 5) to restart the node

### SSH server config to enable tunneling

In order to ensure that Control Node can connect to release node the SSH servers
running the release should allow tunneling,

```
...
AllowTcpForwarding yes
...
```

## SSH key rotation

A general good security practice is to routinely rotate your SSH keys. Control
node expose APIs via `ControlNode.Host.SSH` module which can be leveraged to
perform this rotation. Below is an example,

``` elixir
host_spec = %ControlNode.Host.SSH{
  host: "localhost",
  port: 2222,
  user: "linuxserver.io",
  private_key_dir: "/path/to/ssh_dir"
}

authorized_keys = """
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDg+KMD7QAU+qtH3duwTHmBaJE/WUdiOwC87cqP5cL21 control-node@email.com
"""

host_state = ControlNode.Host.SSH.connect(host_spec)
ControlNode.Host.SSH.exec(host_state, "echo '#{authorized_key}' > /user/.ssh/authorized_keys")
```

## Limitations

- **SSH client only supports `ed25519` keys**. Other keys types are supported
  only via SSH agent
- Only short names for nodes are allowed ie. `sevice_app@hostname` is support
  and **not** `sevice_app@host1.server.com`
- Nodes of a given release (deployed to different) should have different
  hostname for eg. if node 1 has node name `service_app@host1` then another node
  of `service_app` should have a different node name.
