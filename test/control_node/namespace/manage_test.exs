defmodule ControlNode.Namespace.ManageTest do
  use ExUnit.Case, async: false
  import Mock
  import ControlNode.Factory
  alias ControlNode.{Release, Namespace}
  alias Namespace.Manage

  describe "handle_event/4" do
    @tag capture_log: true
    test "transitions to :initialize when release node goes down" do
      data = build_workflow_data("localhost2")

      actions = [
        {:change_callback_module, ControlNode.Namespace.Initialize},
        {:next_event, :internal, {:load_namespace_state, "0.1.0"}}
      ]

      with_mock Release, terminate_state: &mock_terminate_state_ok/2 do
        assert {:next_state, :initialize, data, next_actions} =
                 Manage.handle_event(:info, {:nodedown, :service_app@localhost2}, :ignore, data)

        assert next_actions == actions

        assert [%Release.State{host: %ControlNode.Host.SSH{host: "localhost"}, status: :running}] =
                 data.namespace_state
      end
    end

    @tag capture_log: true
    test "transitions to :initialize when release state termination fails" do
      data = build_workflow_data("localhost2")

      actions = [
        {:change_callback_module, ControlNode.Namespace.Initialize},
        {:next_event, :internal, {:load_namespace_state, "0.1.0"}}
      ]

      assert {:next_state, :initialize, data, next_actions} =
               Manage.handle_event(:info, {:nodedown, :service_app@localhost2}, :ignore, data)

      assert next_actions == actions

      assert [%Release.State{host: %ControlNode.Host.SSH{host: "localhost"}, status: :running}] =
               data.namespace_state
    end
  end

  defp mock_terminate_state_ok(_release_spec, _release_state), do: :ok

  defp build_workflow_data(another_host) do
    host1 = build(:host_spec, host: "localhost", hostname: "localhost")
    host2 = build(:host_spec, host: another_host, hostname: another_host)
    namespace_spec = build(:namespace_spec, hosts: [host1, host2])
    namespace_state = [build(:release_state, host: host1), build(:release_state, host: host2)]
    build(:workflow_data, namespace_spec: namespace_spec, namespace_state: namespace_state)
  end
end
