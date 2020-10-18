defmodule ControlNode.Namespace.DeployTest do
  use ExUnit.Case, async: false
  import Mock
  import ControlNode.Factory
  alias ControlNode.{Release, Namespace}

  describe "handle_event/4 [:ensure_running, version]" do
    setup_with_mocks([
      {Release, [],
       [
         terminate: &mock_terminate/2,
         terminate_state: &mock_terminate_state/2,
         deploy: &mock_deploy/4
       ]}
    ]) do
      :ok
    end

    test "transitions to [state: :initialize] when release `version` is already running" do
      data = build_workflow_data("0.2.0")

      assert {:next_state, :initialize, data, next_actions} =
               Namespace.Deploy.handle_event(:internal, {:ensure_running, "0.2.0"}, :ignore, data)

      assert next_actions == expected_actions("0.2.0")
    end

    test "transitions to [state: :initialize] after starting new deployment" do
      data = build_workflow_data("0.2.0")

      assert {:next_state, :initialize, data, next_actions} =
               Namespace.Deploy.handle_event(:internal, {:ensure_running, "0.4.0"}, :ignore, data)

      assert next_actions == expected_actions("0.4.0")
    end

    @tag capture_log: true
    test "transitions to [state: :initialize] after failing to terminate deployment" do
      data = build_workflow_data("0.1.0")

      assert {:next_state, :initialize, data, next_actions} =
               Namespace.Deploy.handle_event(:internal, {:ensure_running, "0.2.0"}, :ignore, data)

      assert next_actions == expected_actions("0.2.0")
    end

    @tag capture_log: true
    test "transitions to [state: :initialize] after failing to start deployment" do
      data = build_workflow_data("0.2.0")

      assert {:next_state, :initialize, data, next_actions} =
               Namespace.Deploy.handle_event(:internal, {:ensure_running, "0.3.0"}, :ignore, data)

      assert next_actions == expected_actions("0.3.0")
    end
  end

  defp mock_terminate(_release_spec, %Release.State{version: "0.1.0"}) do
    throw("Some exception")
  end

  defp mock_terminate(_release_spec, _release_state), do: :ok

  defp mock_deploy(_release_spec, %Release.State{version: "0.3.0"}, _registry_spec, _version) do
    throw("Some exception")
  end

  defp mock_deploy(_release_spec, _release_state, _registry_spec, _version), do: :ok

  defp mock_terminate_state(_, _), do: :ok

  defp build_workflow_data(version) do
    host = build(:host_spec)
    namespace_state = [build(:release_state, host: host, version: version)]
    namespace_spec = build(:namespace_spec, hosts: [host])
    build(:workflow_data, namespace_spec: namespace_spec, namespace_state: namespace_state)
  end

  defp expected_actions(version) do
    [
      {:change_callback_module, ControlNode.Namespace.Initialize},
      {:next_event, :internal, {:load_namespace_state, version}}
    ]
  end
end
