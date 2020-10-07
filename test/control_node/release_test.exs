defmodule ControlNode.ReleaseTest do
  use ExUnit.Case
  import ControlNode.TestUtils
  alias ControlNode.Host.SSH
  alias ControlNode.{Release, Host, Registry, Inet}

  setup do
    {:ok, host_spec} = ssh_fixture()

    release_spec = %Release.Spec{
      name: :service_app,
      base_path: "/app/service_app",
      start_strategy: :restart
    }

    registry_spec = %Registry.Local{path: Path.join(File.cwd!(), "example")}

    %{host_spec: host_spec, release_spec: release_spec, registry_spec: registry_spec}
  end

  describe "deploy/4, connect/3, setup_tunnel/3" do
    test "uploads tar host, starts release and monitors it", %{
      release_spec: release_spec,
      host_spec: host_spec,
      registry_spec: registry_spec
    } do
      :ok = Release.deploy(release_spec, host_spec, registry_spec, "0.1.0")

      # ensure service is started
      ensure_started(release_spec, host_spec)

      # setup tunnel to the service
      {:ok, service_port} = Release.setup_tunnel(release_spec, host_spec)
      {:ok, %Host.SSH{hostname: hostname} = host_spec} = Host.hostname(host_spec)

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
      true = Release.connect(release_spec, host_spec, cookie)
      assert :pong == Node.ping(:"#{release_spec.name}@#{hostname}")

      Release.stop(release_spec, host_spec)

      ensure_stopped(release_spec, host_spec)

      assert {:error, :release_not_running} ==
               Release.setup_tunnel(release_spec, host_spec)

      :net_kernel.stop()
    end
  end

  describe "stop/2" do
    test "return error when node is not connected", %{
      release_spec: release_spec,
      host_spec: host_spec
    } do
      host_spec = %SSH{host_spec | hostname: :service_app@somehost}
      assert {:error, :node_not_connected} == Release.stop(release_spec, host_spec)
    end

    test "return error hostname is nil", %{
      release_spec: release_spec,
      host_spec: host_spec
    } do
      assert {:error, :hostname_not_found} == Release.stop(release_spec, host_spec)
    end
  end

  defp ensure_started(release_spec, host_spec) do
    assert_until(fn ->
      {:ok, %SSH.ExecStatus{exit_status: exit_status}} =
        SSH.exec(host_spec, "#{release_spec.base_path}/0.1.0/bin/#{release_spec.name} pid")

      exit_status == :success
    end)
  end

  defp ensure_stopped(release_spec, host_spec) do
    assert_until(fn ->
      {:ok, %SSH.ExecStatus{message: message}} =
        SSH.exec(host_spec, "#{release_spec.base_path}/0.1.0/bin/#{release_spec.name} pid")

      message == ["--rpc-eval : RPC failed with reason :nodedown\n"]
    end)
  end
end
