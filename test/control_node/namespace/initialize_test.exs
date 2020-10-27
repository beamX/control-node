defmodule ControlNode.Namespace.InitializeTest do
  use ExUnit.Case, async: false
  import Mock
  import ControlNode.Factory
  alias ControlNode.{Release, Namespace}
  alias Namespace.Initialize

  @moduletag capture_log: true

  describe "handle_event/4" do
    test "transitions to :deploy when release is running" do
      data = build_workflow_data("localhost2")

      actions = [
        {:change_callback_module, ControlNode.Namespace.Deploy},
        {:next_event, :internal, {:ensure_running, "0.1.0"}}
      ]

      with_mock Release, initialize_state: &mock_initialize_state/3 do
        assert {:next_state, :deploy, data, next_actions} =
                 Initialize.handle_event(:internal, :load_namespace_state, :initialize, data)

        assert next_actions == actions
      end
    end

    test "returns :version_conflict when running releases which have different version" do
      data = build_workflow_data("localhost4")

      with_mock Release, initialize_state: &mock_initialize_state/3 do
        assert {:next_state, :version_conflict, data} =
                 Initialize.handle_event(:internal, :load_namespace_state, :initialize, data)
      end
    end

    test "transitions to :manage when no release is running" do
      namespace_spec = build(:namespace_spec, hosts: [build(:host_spec, host: "localhost3")])
      data = build(:workflow_data, namespace_spec: namespace_spec)
      actions = [{:change_callback_module, ControlNode.Namespace.Manage}]

      with_mock Release, initialize_state: &mock_initialize_state/3 do
        assert {:next_state, :manage, data, next_actions} =
                 Initialize.handle_event(:internal, :load_namespace_state, :initialize, data)

        assert next_actions == actions
      end
    end

    test "resolves version_conflict when {:resolve_version, version} event is sent" do
      namespace_spec = build(:namespace_spec, hosts: [build(:host_spec)])
      data = build(:workflow_data, namespace_spec: namespace_spec)

      actions = [
        {:reply, :ignore, :ok},
        {:change_callback_module, ControlNode.Namespace.Deploy},
        {:next_event, :internal, {:ensure_running, "0.2.0"}}
      ]

      with_mock Release, initialize_state: &mock_initialize_state/3 do
        assert {:next_state, :deploy, data, next_actions} =
                 Initialize.handle_event(
                   {:call, :ignore},
                   {:resolve_version, "0.2.0"},
                   :version_confict,
                   data
                 )

        assert next_actions == actions
      end
    end

    test "on [event: {:load_namespace_state, version}] transitions to [state: :manage]\
    when release with `version` is running" do
      data = build_workflow_data("localhost2")
      actions = [change_callback_module: ControlNode.Namespace.Manage]

      with_mock Release, initialize_state: &mock_initialize_state/3 do
        assert {:next_state, :manage, data, next_actions} =
                 Initialize.handle_event(
                   :internal,
                   {:load_namespace_state, "0.1.0"},
                   :initialize,
                   data
                 )

        assert next_actions == actions
      end
    end

    test "[event: {:load_namespace_state, version}] transitions to [state: :deploy]\
    when release with `version` is partially running" do
      data = build_workflow_data("localhost3")

      with_mock Release, initialize_state: &mock_initialize_state/3 do
        assert {:next_state, :deploy, data, next_actions} =
                 Initialize.handle_event(
                   :internal,
                   {:load_namespace_state, "0.1.0"},
                   :initialize,
                   data
                 )

        assert next_actions == expected_actions("0.1.0")
      end
    end

    test "[event: {:load_namespace_state, version}] transitions to [state: :deploy]\
    when different release versions are running" do
      data = build_workflow_data("localhost4")

      with_mock Release, initialize_state: &mock_initialize_state/3 do
        assert {:next_state, :deploy, data, next_actions} =
                 Initialize.handle_event(
                   :internal,
                   {:load_namespace_state, "0.2.0"},
                   :initialize,
                   data
                 )

        assert next_actions == expected_actions("0.2.0")
      end
    end

    test "[event: {:load_namespace_state, version}] transitions to [state: :deploy]\
    when release is not running" do
      hosts = [build(:host_spec, host: "localhost3")]
      namespace_spec = build(:namespace_spec, hosts: hosts)
      data = build(:workflow_data, namespace_spec: namespace_spec)

      with_mock Release, initialize_state: &mock_initialize_state/3 do
        assert {:next_state, :deploy, data, next_actions} =
                 Initialize.handle_event(
                   :internal,
                   {:load_namespace_state, "0.2.0"},
                   :initialize,
                   data
                 )

        assert next_actions == expected_actions("0.2.0")
      end
    end

    test "[event: {:load_namespace_state, version}] transitions to [state: :manage]\
    resets deploy_attempts" do
      data = %{build_workflow_data("localhost2") | deploy_attempts: 3}
      actions = [change_callback_module: Namespace.Manage]

      with_mock Release, initialize_state: &mock_initialize_state/3 do
        assert {:next_state, :manage, %{deploy_attempts: attempts}, next_actions} =
                 Initialize.handle_event(
                   :internal,
                   {:load_namespace_state, "0.1.0"},
                   :initialize,
                   data
                 )

        assert next_actions == actions
        assert attempts == 0
      end
    end

    test "[event: :observe_namespace_state] transitions to [state: :observe]" do
      namespace_spec = build(:namespace_spec, hosts: [build(:host_spec)])
      data = build(:workflow_data, namespace_spec: namespace_spec)

      with_mock Release, initialize_state: &mock_initialize_state/3 do
        assert {:next_state, :observe, data, next_actions} =
                 Initialize.handle_event(
                   :internal,
                   :observe_namespace_state,
                   :initialize,
                   data
                 )

        assert next_actions == [{:change_callback_module, Namespace.Observe}]
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

  defp build_workflow_data(another_host) do
    hosts = [build(:host_spec), build(:host_spec, host: another_host)]
    namespace_spec = build(:namespace_spec, hosts: hosts)
    build(:workflow_data, namespace_spec: namespace_spec)
  end

  defp expected_actions(version) do
    [
      {:change_callback_module, ControlNode.Namespace.Deploy},
      {:next_event, :internal, {:ensure_running, version}}
    ]
  end
end
