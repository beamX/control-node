defmodule ControlNode.ReleaseTest do
  use ExUnit.Case
  import ControlNode.TestUtils
  alias ControlNode.Host.SSH
  alias ControlNode.{Release, Host, Registry, Inet}

  setup do
    {:ok, ssh_config} = ssh_fixture()

    release_spec = %Release.Spec{
      name: :service_app,
      base_path: "/app/service_app",
      start_strategy: :restart
    }

    registry_spec = %Registry.Local{path: Path.join(File.cwd!(), "example")}

    %{ssh_config: ssh_config, release_spec: release_spec, registry_spec: registry_spec}
  end

  describe "deploy/4, connect/3" do
    test "uploads tar host, starts release and monitors it", %{
      release_spec: release_spec,
      ssh_config: ssh_config,
      registry_spec: registry_spec
    } do
      :ok = Release.deploy(release_spec, ssh_config, registry_spec, "0.1.0")

      # ensure service is started
      assert_until(fn ->
        {:ok, %SSH.ExecStatus{exit_status: exit_status}} =
          SSH.exec(ssh_config, "#{release_spec.base_path}/0.1.0/bin/#{release_spec.name} pid")

        exit_status == :success
      end)

      # setup tunnel to the service
      {:ok, service_port} = Release.setup_tunnel(release_spec, ssh_config, "0.1.0")
      {:ok, hostname} = Host.hostname(ssh_config)

      # NOTE: Configure host config for inet
      # This config will be used by BEAM to resolve `hostname`
      Inet.add_alias_for_localhost(hostname)

      ControlNode.Epmd.register_release(release_spec.name, hostname, service_port)

      # start erlang distribution
      # net_kernel starts the erlang distribution which during its start process
      # registers with the epmd daemon. It is expected that there will be no
      # EPMD daemon running as it should be replaced with `ControlNode.Epmd`
      {:ok, _pid} = :net_kernel.start([:control_node_test, :shortnames])

      cookie = :"YFWZXAOJGTABHNGIT6KVAC2X6TEHA6WCIRDKSLFD6JZWRC4YHMMA===="
      true = Release.connect(release_spec, hostname, cookie)
      assert :pong == Node.ping(:"#{release_spec.name}@#{hostname}")

      :net_kernel.stop()

      {:ok, %SSH.ExecStatus{exit_status: :success}} =
        SSH.exec(ssh_config, "#{release_spec.base_path}/0.1.0/bin/#{release_spec.name} stop")
    end
  end
end
