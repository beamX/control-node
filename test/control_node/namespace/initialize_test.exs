defmodule ControlNode.Namespace.InitializeTest do
  use ExUnit.Case, async: false
  import Mock
  import ControlNode.TestUtils
  alias ControlNode.{Release, Registry, Namespace}
  alias Namespace.Initialize

  setup do
    registry_spec = %Registry.Local{path: Path.join(File.cwd!(), "example")}
    release_spec = %Release.Spec{name: :service_app, base_path: "/app/service_app"}

    %{registry_spec: registry_spec, release_spec: release_spec}
  end

  describe "handle_event/4" do
    test "transitions to :deploy when release is running", %{
      registry_spec: registry_spec,
      release_spec: release_spec
    } do
      host_spec1 = ssh_fixture()
      host_spec2 = %{ssh_fixture() | host: "localhost2"}
      namespace_spec = gen_namespace_spec([host_spec1, host_spec2], registry_spec)
      data = %{release_spec: release_spec, namespace_spec: namespace_spec, namespace_state: nil}

      actions = [
        {:change_callback_module, ControlNode.Namespace.Deploy},
        {:next_event, :internal, {:ensure_running, "0.1.0"}}
      ]

      with_mock Release, initialize_state: &mock_initialize_state/3 do
        assert {:next_state, :deploy, data, ^actions} =
                 Initialize.handle_event(:internal, :load_namespace_state, :initialize, data)
      end
    end

    test "returns :version_conflict when running releases have differnt version", %{
      registry_spec: registry_spec,
      release_spec: release_spec
    } do
      host_spec1 = ssh_fixture()
      host_spec2 = %{ssh_fixture() | host: "localhost4"}
      namespace_spec = gen_namespace_spec([host_spec1, host_spec2], registry_spec)
      data = %{release_spec: release_spec, namespace_spec: namespace_spec, namespace_state: nil}

      with_mock Release, initialize_state: &mock_initialize_state/3 do
        assert {:next_state, :version_conflict, data} =
                 Initialize.handle_event(:internal, :load_namespace_state, :initialize, data)
      end
    end

    test "transitions to :manage when no release is running", %{
      registry_spec: registry_spec,
      release_spec: release_spec
    } do
      host_spec = %{ssh_fixture() | host: "localhost3"}
      namespace_spec = gen_namespace_spec([host_spec], registry_spec)
      data = %{release_spec: release_spec, namespace_spec: namespace_spec, namespace_state: nil}

      actions = [{:change_callback_module, ControlNode.Namespace.Manage}]

      with_mock Release, initialize_state: &mock_initialize_state/3 do
        assert {:next_state, :manage, data, ^actions} =
                 Initialize.handle_event(:internal, :load_namespace_state, :initialize, data)
      end
    end

    test "resolves version_conflict when {:resolve_version, version} event is sent", %{
      registry_spec: registry_spec,
      release_spec: release_spec
    } do
      namespace_spec = gen_namespace_spec([ssh_fixture()], registry_spec)
      data = %{release_spec: release_spec, namespace_spec: namespace_spec, namespace_state: nil}

      actions = [
        {:reply, :ignore, :ok},
        {:change_callback_module, ControlNode.Namespace.Deploy},
        {:next_event, :internal, {:ensure_running, "0.2.0"}}
      ]

      with_mock Release, initialize_state: &mock_initialize_state/3 do
        assert {:next_state, :deploy, data, ^actions} =
                 Initialize.handle_event(
                   {:call, :ignore},
                   {:resolve_version, "0.2.0"},
                   :version_confict,
                   data
                 )
      end
    end
  end

  defp mock_initialize_state(_release_spec, %{host: "localhost3"} = host_spec, _cookie) do
    %Release.State{host: host_spec, status: :not_running}
  end

  defp mock_initialize_state(_release_spec, %{host: "localhost4"} = host_spec, _cookie) do
    %Release.State{host: host_spec, version: "0.2.0", status: :running, port: 8989}
  end

  defp mock_initialize_state(_release_spec, host_spec, _cookie) do
    %Release.State{host: host_spec, version: "0.1.0", status: :running, port: 8989}
  end

  defp gen_namespace_spec(hosts, registry_spec) do
    %Namespace.Spec{
      tag: :testing,
      hosts: hosts,
      registry_spec: registry_spec,
      deployment_type: :incremental_replace,
      release_cookie: :"YFWZXAOJGTABHNGIT6KVAC2X6TEHA6WCIRDKSLFD6JZWRC4YHMMA===="
    }
  end
end
