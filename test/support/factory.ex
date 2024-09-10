defmodule ControlNode.Factory do
  use ExMachina
  alias ControlNode.{Namespace, Registry, Release, Host}

  def host_spec_factory do
    private_key_dir = with_fixture_path('host-vm/.ssh') |> :erlang.list_to_binary()
    # on CI the env var SSH_HOST is set to openssh-server to connect
    # to the service container running SSH server
    host = System.get_env("SSH_HOST", "localhost")

    %Host.SSH{
      host: host,
      port: 2222,
      user: "linuxserver.io",
      private_key_dir: private_key_dir
    }
  end

  defp with_fixture_path(path) do
    Path.join([File.cwd!(), "test/fixture", path]) |> Kernel.to_charlist()
  end

  def namespace_spec_factory do
    %Namespace.Spec{
      tag: :testing,
      hosts: nil,
      registry_spec: registry_spec_factory(),
      deployment_type: :incremental_replace,
      release_cookie: :"YFWZXAOJGTABHNGIT6KVAC2X6TEHA6WCIRDKSLFD6JZWRC4YHMMA===="
    }
  end

  def workflow_data_factory do
    %Namespace.Workflow.Data{
      namespace_spec: nil,
      release_spec: release_spec_factory(),
      release_state: nil
    }
  end

  def release_state_factory do
    %Release.State{
      host: host_spec_factory(),
      version: "0.1.0",
      status: :running,
      port: 9090
    }
  end

  def release_spec_factory do
    %Release.Spec{name: :service_app, base_path: "/app/service_app"}
  end

  def registry_spec_factory do
    %Registry.Local{path: Path.join(File.cwd!(), "example")}
  end
end
