defmodule ControlNode.Namespace.InitializeTest do
  use ExUnit.Case, async: false
  import Mock
  import ControlNode.Factory
  alias ControlNode.{Release, Namespace}
  alias Namespace.Initialize

  @moduletag capture_log: true

  describe "handle_event/4" do
    test "transitions to :manage when release is running" do
      data = build_workflow_data("localhost2")

      actions = [
        {:change_callback_module, ControlNode.Namespace.Manage},
        {:next_event, :internal, :schedule_health_check}
      ]

      with_mock Release, initialize_state: &mock_initialize_state/3 do
        assert {:next_state, :manage, data, next_actions} =
                 Initialize.handle_event(:internal, :load_release_state, :initialize, data)

        assert next_actions == actions
      end
    end

    test "transitions to :manage when no release is running" do
      data = build_workflow_data("localhost3")

      actions = [{:change_callback_module, ControlNode.Namespace.Manage}]

      with_mock Release, initialize_state: &mock_initialize_state/3 do
        assert {:next_state, :manage, data, next_actions} =
                 Initialize.handle_event(:internal, :load_release_state, :initialize, data)

        assert next_actions == actions
      end
    end
  end

  describe "handle_event/4 {:load_release_state, version}" do
    setup_with_mocks([
      {Release, [],
       [
         initialize_state: &mock_initialize_state/3,
         terminate_state: &mock_terminate_state_ok/2
       ]}
    ]) do
      :ok
    end

    test "transitions to [state: :manage] when release with `version` is running" do
      data = build_workflow_data("localhost2")

      actions = [
        {:change_callback_module, ControlNode.Namespace.Manage},
        {:next_event, :internal, :schedule_health_check}
      ]

      assert {:next_state, :manage, data, next_actions} =
               Initialize.handle_event(
                 :internal,
                 {:load_release_state, "0.1.0"},
                 :initialize,
                 data
               )

      assert next_actions == actions
    end

    test "[event: {:load_release_state, version}] transitions to [state: :deploy]\
          when release with `version` is not running" do
      data = build_workflow_data("localhost3")

      assert {:next_state, :deploy, data, next_actions} =
               Initialize.handle_event(
                 :internal,
                 {:load_release_state, "0.1.0"},
                 :initialize,
                 data
               )

      assert next_actions == expected_actions("0.1.0")
    end

    test "[event: {:load_release_state, version}] transitions to [state: :deploy]\
          when different release versions are running" do
      data = build_workflow_data("localhost")

      assert {:next_state, :deploy, data, next_actions} =
               Initialize.handle_event(
                 :internal,
                 {:load_release_state, "0.2.0"},
                 :initialize,
                 data
               )

      assert next_actions == expected_actions("0.2.0")
    end

    test "[event: {:load_release_state, version}] transitions to [state: :deploy]\
          when release is not running" do
      data = build_workflow_data("localhost3")

      assert {:next_state, :deploy, data, next_actions} =
               Initialize.handle_event(
                 :internal,
                 {:load_release_state, "0.2.0"},
                 :initialize,
                 data
               )

      assert next_actions == expected_actions("0.2.0")
    end

    test "[event: {:load_release_state, version}] transitions to [state: :manage]\
          resets deploy_attempts" do
      data = %{build_workflow_data("localhost2") | deploy_attempts: 3}

      actions = [
        {:change_callback_module, Namespace.Manage},
        {:next_event, :internal, :schedule_health_check}
      ]

      assert {:next_state, :manage, %{deploy_attempts: attempts}, next_actions} =
               Initialize.handle_event(
                 :internal,
                 {:load_release_state, "0.1.0"},
                 :initialize,
                 data
               )

      assert next_actions == actions
      assert attempts == 0
    end

    test "[event: :observe_namespace_state] transitions to [state: :observe]" do
      data = build_workflow_data("localhost")

      assert {:next_state, :observe, data, next_actions} =
               Initialize.handle_event(:internal, :observe_release_state, :initialize, data)

      assert next_actions == [{:change_callback_module, Namespace.Observe}]
    end

    test "[event: :connect_namespace_state] transitions to [state: :connect]" do
      data = build_workflow_data("localhost")

      assert {:next_state, :connect, data, next_actions} =
               Initialize.handle_event(:internal, :connect_release_state, :initialize, data)

      assert next_actions == [{:change_callback_module, Namespace.Connect}]
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

  defp build_workflow_data(host) do
    host_spec = build(:host_spec, host: host)
    namespace_spec = build(:namespace_spec, hosts: [host_spec])
    release_state = Release.State.new(host_spec)
    build(:workflow_data, namespace_spec: namespace_spec, release_state: release_state)
  end

  defp expected_actions(version) do
    [
      {:change_callback_module, ControlNode.Namespace.Deploy},
      {:next_event, :internal, {:ensure_running, version}}
    ]
  end

  defp mock_terminate_state_ok(_release_spec, _release_state), do: :ok
end
