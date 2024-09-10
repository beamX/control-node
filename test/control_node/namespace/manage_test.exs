defmodule ControlNode.Namespace.ManageTest do
  use ExUnit.Case, async: false
  import Mock
  import ControlNode.Factory
  alias ControlNode.{Release, Namespace}
  alias Namespace.Manage

  @moduletag capture_log: true

  describe "handle_event/4" do
    test "transitions to :initialize when release node goes down" do
      data = build_workflow_data("localhost2")

      actions = [
        {:change_callback_module, ControlNode.Namespace.Initialize},
        {:next_event, :internal, {:load_release_state, "0.1.0"}}
      ]

      with_mock Release, terminate_state: &mock_terminate_state_ok/2 do
        assert {:next_state, :initialize, data, next_actions} =
                 Manage.handle_event(:info, {:nodedown, :service_app@localhost2}, :ignore, data)

        assert next_actions == actions

        assert %Release.State{
                 host: %ControlNode.Host.SSH{host: "localhost2"},
                 status: :not_running
               } = data.release_state
      end
    end

    test "transitions to :initialize when release state termination fails" do
      data = build_workflow_data("localhost2")

      actions = [
        {:change_callback_module, ControlNode.Namespace.Initialize},
        {:next_event, :internal, {:load_release_state, "0.1.0"}}
      ]

      assert {:next_state, :initialize, data, next_actions} =
               Manage.handle_event(:info, {:nodedown, :service_app@localhost2}, :ignore, data)

      assert next_actions == actions

      assert %Release.State{host: %ControlNode.Host.SSH{host: "localhost2"}, status: :not_running} =
               data.release_state
    end
  end

  describe "[event: :schedule_health_check] handle_event/4" do
    test "initializes health check" do
      release_spec =
        build(:release_spec, health_check_spec: %Release.HealthCheckSpec{function: fn -> :ok end})

      data = %{build_workflow_data("localhost2") | release_spec: release_spec}

      assert {:keep_state, data, []} =
               Manage.handle_event(:internal, :schedule_health_check, :ignore, data)

      assert is_reference(data.health_check_timer)
    end
  end

  describe "[event: :stop] handle_event/4" do
    setup_with_mocks([
      {:erpc, [:unstick], [call: &erpc_call/4]}
    ]) do
      :ok
    end

    test "stops release node on remote host" do
      data = build_workflow_data("localhost1")

      action = [{:reply, :sender_pid, :ok}]

      assert {:next_state, :manage, _data, ^action} =
               Manage.handle_event({:call, :sender_pid}, :stop, :ignore, data)
    end
  end

  describe "[event: :current_version] handle_event/4" do
    test "return current running version of release" do
      data = build_workflow_data("localhost1")

      response = {:keep_state_and_data, [{:reply, :sender_pid, {:ok, "0.1.0"}}]}

      assert response ==
               Manage.handle_event({:call, :sender_pid}, :current_version, :ignore, data)
    end
  end

  describe "[event: :check_health] handle_event/4" do
    setup_with_mocks([
      {:erpc, [:unstick], [call: &erpc_call/4]}
    ]) do
      :ok
    end

    test "performs health check and keeps state when health check passes" do
      data = build_workflow_data("localhost2")

      assert {:keep_state, _data, []} =
               Manage.handle_event(:internal, :check_health, :ignore, data)
    end

    test "perform health check and removes nodes which failed health check" do
      data = build_workflow_data("localhost3")

      actions = [
        {:change_callback_module, Namespace.Initialize},
        {:next_event, :internal, {:load_release_state, "0.1.0"}}
      ]

      assert {:next_state, :initialize, data, ^actions} =
               Manage.handle_event(:internal, :check_health, :ignore, data)

      assert %Release.State{host: %{host: "localhost3"}, status: :not_running} =
               data.release_state
    end

    test "[health_check.on_failure: :noop] when nodes fail health check does not reboot" do
      release_spec =
        build(:release_spec, health_check_spec: %Release.HealthCheckSpec{on_failure: :noop})

      data = %{build_workflow_data("localhost3") | release_spec: release_spec}

      assert {:keep_state, _data, []} =
               Manage.handle_event(:internal, :check_health, :ignore, data)
    end
  end

  defp mock_terminate_state_ok(_release_spec, _release_state), do: :ok

  defp build_workflow_data(host) do
    host = build(:host_spec, host: host, hostname: host)
    namespace_spec = build(:namespace_spec, hosts: [host])
    release_state = build(:release_state, host: host)
    build(:workflow_data, namespace_spec: namespace_spec, release_state: release_state)
  end

  defp erpc_call(:service_app@localhost, _m, _f, _a), do: {:ok, :ok}
  defp erpc_call(:service_app@localhost3, _m, _f, _a), do: {:ok, :error}
  defp erpc_call(_nodes, _m, _f, _a), do: {:ok, :ok}
end
