defmodule ControlNode.ReleaseTest do
  use ExUnit.Case
  import Mock
  import ControlNode.TestUtils
  alias ControlNode.Host.SSH
  alias ControlNode.{Release, Host, Registry, Inet}

  setup do
    host_spec = ssh_fixture()
    release_spec = %Release.Spec{name: :service_app, base_path: "/app/service_app"}
    registry_spec = %Registry.Local{path: Path.join(File.cwd!(), "example")}
    cookie = :"YFWZXAOJGTABHNGIT6KVAC2X6TEHA6WCIRDKSLFD6JZWRC4YHMMA===="

    # start erlang distribution
    # net_kernel starts the erlang distribution which during its start process
    # registers with the epmd daemon. It is expected that there will be no
    # EPMD daemon running as it should be replaced with `ControlNode.Epmd`
    {:ok, _pid} = :net_kernel.start([:control_node_test, :shortnames])

    on_exit(fn -> :net_kernel.stop() end)

    %{
      host_spec: host_spec,
      release_spec: release_spec,
      registry_spec: registry_spec,
      cookie: cookie
    }
  end

  describe "deploy/4, connect/3" do
    test "uploads tar host, starts release and monitors it", %{
      release_spec: release_spec,
      host_spec: host_spec,
      registry_spec: registry_spec,
      cookie: cookie
    } do
      :ok = Release.deploy(release_spec, host_spec, registry_spec, "0.1.0")

      # ensure service is started
      ensure_started(release_spec, host_spec)

      # setup tunnel to the service
      {:ok, service_port} = setup_tunnel(release_spec, Host.connect(host_spec))
      {:ok, %Host.SSH{hostname: hostname} = host_spec} = Host.hostname(host_spec)

      # NOTE: Configure host config for inet
      # This config will be used by BEAM to resolve `hostname`
      Inet.add_alias_for_localhost(hostname)
      ControlNode.Epmd.register_release(release_spec.name, hostname, service_port)

      true = Release.connect(release_spec, host_spec, cookie)
      assert :pong == Node.ping(:"#{release_spec.name}@#{hostname}")

      Release.stop(release_spec, %Release.State{host: host_spec})
      ensure_stopped(release_spec, host_spec)

      assert {:error, :release_not_running} ==
               setup_tunnel(release_spec, Host.connect(host_spec))
    end
  end

  describe "initialize_state/3" do
    setup %{
      release_spec: release_spec,
      host_spec: host_spec,
      registry_spec: registry_spec,
      cookie: cookie
    } do
      :ok = Release.deploy(release_spec, host_spec, registry_spec, "0.1.0")

      # ensure service is started
      ensure_started(release_spec, host_spec)

      on_exit(fn ->
        ensure_stopped(release_spec, host_spec)

        assert %Release.State{version: nil, status: :not_running} =
                 Release.initialize_state(release_spec, host_spec, cookie)
      end)
    end

    test "Setup tunnel and return state of service on remote host", %{
      release_spec: release_spec,
      host_spec: host_spec,
      cookie: cookie
    } do
      assert %Release.State{
               host: host_spec,
               version: "0.1.0",
               status: :running,
               release_path: "/app/service_app/0.1.0"
             } = release_state = Release.initialize_state(release_spec, host_spec, cookie)

      assert :pong == Node.ping(:"#{release_spec.name}@#{host_spec.hostname}")
      Release.stop(release_spec, release_state)
    end

    test "Setup tunnel and return state of service with nil version", %{
      release_spec: release_spec,
      host_spec: host_spec,
      cookie: cookie
    } do
      mock_rpc_call = {:rpc, [:unstick], [call: &rpc_call/4]}

      with_mocks([mock_rpc_call]) do
        assert %Release.State{host: host_spec, version: "0.1.0", status: :running} =
                 Release.initialize_state(release_spec, host_spec, cookie)
      end

      refute [] == Node.list()

      exec_stop(release_spec, host_spec)
    end
  end

  describe "terminate" do
    setup %{release_spec: release_spec, host_spec: host_spec, registry_spec: registry_spec} do
      :ok = Release.deploy(release_spec, host_spec, registry_spec, "0.1.0")
      ensure_started(release_spec, host_spec)

      on_exit(fn ->
        SSH.exec(host_spec, "#{release_spec.base_path}/0.1.0/bin/#{release_spec.name} stop")
        ensure_stopped(release_spec, host_spec)
      end)
    end

    @tag capture_log: true
    test "terminate_state/2 demonitor node and close SSH connection", %{
      release_spec: release_spec,
      host_spec: host_spec,
      cookie: cookie
    } do
      # test `terminate_state` without node connect/monitor
      host_spec = Host.connect(host_spec)

      assert %Host.SSH{conn: nil} =
               Release.terminate_state(release_spec, %Release.State{host: host_spec})

      # test `terminate_state` with node connect/monitor
      %{host: host_spec} =
        release_state = Release.initialize_state(release_spec, host_spec, cookie)

      node = :"#{release_spec.name}@#{host_spec.hostname}"

      assert %Host.SSH{conn: nil} = Release.terminate_state(release_spec, release_state)
      refute_receive {:nodedown, ^node}
    end

    test "stop/2 stops node and close SSH connection", %{
      release_spec: release_spec,
      host_spec: host_spec,
      cookie: cookie
    } do
      %{host: host_spec} =
        release_state = Release.initialize_state(release_spec, host_spec, cookie)

      assert :ok = Release.stop(release_spec, release_state)

      node = :"#{release_spec.name}@#{host_spec.hostname}"
      refute_receive {:nodedown, ^node}
    end
  end

  defp rpc_call(_node, :application, :get_key, _args), do: :undefined

  defp rpc_call(_node, :code, :root_dir, _args), do: '/app/service_app/0.1.0'

  defp rpc_call(_node, :release_handler, :which_releases, _args) do
    [{'service_app', '0.1.0', [], :permanent}]
  end
end
