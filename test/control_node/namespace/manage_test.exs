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

  describe "[event: :add_host] handle_event/4" do
    test "transitions to :initialize when a new host is added" do
      data = build_workflow_data("localhost2")
      new_host = build(:host_spec, host: "new_host")

      actions = [
        {:reply, :ignore, :ok},
        {:change_callback_module, ControlNode.Namespace.Initialize},
        {:next_event, :internal, {:load_namespace_state, "0.1.0"}}
      ]

      assert {:next_state, :initialize, data, next_actions} =
               Manage.handle_event({:call, :ignore}, {:add_host, new_host}, :ignore, data)

      assert next_actions == actions
      assert Enum.any?(data.namespace_spec.hosts, fn %{host: host} -> host == "new_host" end)
      assert length(data.namespace_state) == 2
      refute Enum.any?(data.namespace_state, fn %{host: %{host: host}} -> host == "new_host" end)
    end

    test "remains in state :manage when a new host already exists" do
      data = build_workflow_data("localhost2")
      new_host = build(:host_spec, host: "localhost2")

      next_actions = [{:reply, :ignore, {:error, :host_already_exists}}]

      assert {:keep_state_and_data, actions} =
               Manage.handle_event({:call, :ignore}, {:add_host, new_host}, :ignore, data)

      assert next_actions == actions
      assert length(data.namespace_state) == 2
      refute Enum.any?(data.namespace_spec.hosts, fn %{host: host} -> host == "new_host" end)
      refute Enum.any?(data.namespace_state, fn %{host: %{host: host}} -> host == "new_host" end)
    end
  end

  describe "[event: :remove_host] handle_event/4" do
    test "stops service and removes host from namespace" do
      data = build_workflow_data("localhost2")
      actions = [{:reply, :ignore, :ok}]

      with_mock Release, terminate_state: &mock_terminate_state_ok/2, stop: &mock_stop_ok/2 do
        assert {:keep_state, data, next_actions} =
                 Manage.handle_event(
                   {:call, :ignore},
                   {:remove_host, "localhost2"},
                   :ignore,
                   data
                 )

        assert next_actions == actions
        assert length(data.namespace_state) == 1
        refute Enum.any?(data.namespace_spec.hosts, fn %{host: host} -> host == "localhost2" end)

        refute Enum.any?(data.namespace_state, fn %{host: host_spec} ->
                 host_spec.host == "localhost2"
               end)
      end
    end

    test "return :ok when host doesn't exit in namespace" do
      data = build_workflow_data("localhost2")
      next_actions = [{:reply, :ignore, :ok}]

      assert {:keep_state, data, actions} =
               Manage.handle_event({:call, :ignore}, {:remove_host, "other_host"}, :ignore, data)

      assert next_actions == actions
      assert length(data.namespace_state) == 2
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

  describe "[event: :check_health] handle_event/4" do
    setup_with_mocks([
      {:erpc, [:unstick], [multicall: &erpc_multicall/4]}
    ]) do
      :ok
    end

    test "performs health check and keeps state when health check passes" do
      data = build_workflow_data("localhost2")

      assert {:keep_state, data, []} =
               Manage.handle_event(:internal, :check_health, :ignore, data)
    end

    test "perform health check and removes nodes which failed health check" do
      data = build_workflow_data("localhost3")

      actions = [
        {:change_callback_module, Namespace.Initialize},
        {:next_event, :internal, {:load_namespace_state, "0.1.0"}}
      ]

      assert {:next_state, :initialize, data, ^actions} =
               Manage.handle_event(:internal, :check_health, :ignore, data)

      assert [%Release.State{host: %{host: "localhost"}}] = data.namespace_state
    end

    test "[health_check.on_failure: :noop] when nodes fail health check does not reboot" do
      release_spec =
        build(:release_spec, health_check_spec: %Release.HealthCheckSpec{on_failure: :noop})

      data = %{build_workflow_data("localhost3") | release_spec: release_spec}

      assert {:keep_state, data, []} =
               Manage.handle_event(:internal, :check_health, :ignore, data)
    end
  end

  defp mock_terminate_state_ok(_release_spec, _release_state), do: :ok
  defp mock_stop_ok(_release_spec, _release_state), do: :ok

  defp build_workflow_data(another_host) do
    host1 = build(:host_spec, host: "localhost", hostname: "localhost")
    host2 = build(:host_spec, host: another_host, hostname: another_host)
    namespace_spec = build(:namespace_spec, hosts: [host1, host2])
    namespace_state = [build(:release_state, host: host1), build(:release_state, host: host2)]
    build(:workflow_data, namespace_spec: namespace_spec, namespace_state: namespace_state)
  end

  defp erpc_multicall([:service_app@localhost, :service_app@localhost3], _m, _f, _a) do
    [{:ok, :ok}, {:ok, :error}]
  end

  defp erpc_multicall(_nodes, _m, _f, _a) do
    [{:ok, :ok}, {:ok, :ok}]
  end
end
