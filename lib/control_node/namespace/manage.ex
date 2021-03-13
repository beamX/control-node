defmodule ControlNode.Namespace.Manage do
  @moduledoc false

  @state_name :manage

  require Logger
  alias ControlNode.{Namespace, Namespace.Workflow, Release}

  def callback_mode, do: :handle_event_function

  # NOTE: deploy event is also handled in :observe state
  def handle_event({:call, from}, {:deploy, version}, _state, data) do
    {state, actions} = Workflow.next(@state_name, :trigger_deployment, version)
    actions = [{:reply, from, :ok} | actions]
    {:next_state, state, data, actions}
  end

  def handle_event({:call, from}, {:remove_host, host}, _state, data) do
    {:ok, namespace_spec, namespace_state} =
      Namespace.remove_host(data.namespace_spec, data.namespace_state, data.release_spec, host)

    data = %Workflow.Data{data | namespace_spec: namespace_spec, namespace_state: namespace_state}
    actions = [{:reply, from, :ok}]
    {:keep_state, data, actions}
  end

  def handle_event({:call, from}, {:add_host, host_spec}, _state, data) do
    %Workflow.Data{namespace_spec: namespace_spec, namespace_state: namespace_state} = data

    with {:ok, namespace_spec} <- Namespace.add_host(namespace_spec, host_spec),
         {:ok, version} <- Namespace.get_current_version(namespace_state) do
      data = %Workflow.Data{data | namespace_spec: namespace_spec}
      {state, actions} = Workflow.next(@state_name, :new_host, version)
      actions = [{:reply, from, :ok} | actions]
      {:next_state, state, data, actions}
    else
      error ->
        Logger.error("Error while adding new host #{inspect(error)}")
        actions = [{:reply, from, error}]
        {:keep_state_and_data, actions}
    end
  end

  def handle_event(_from, :check_health, _state, data) do
    %Workflow.Data{
      release_spec: %Release.Spec{health_check_spec: hc_spec} = release_spec,
      namespace_state: ns_state
    } = data

    failed_health_checks = check_health(ns_state, release_spec, hc_spec)

    if failed_health_checks == [] do
      Logger.debug("Nodes healthy")

      timer_ref = Release.schedule_health_check(hc_spec)
      data = %Workflow.Data{data | health_check_timer: timer_ref}
      {:keep_state, data, []}
    else
      Logger.info("Health check failed for #{inspect(failed_health_checks)}")

      if hc_spec.on_failure == :reboot do
        # TODO| in case the node is not responding we might need to kill the process
        # TODO| stop nodes with failed health checks
        # Remove nodes which failed health check from namespace_state
        {ns_state_new, [release_version | _] = vsn_list} =
          process_failed_health_checks(ns_state, release_spec, failed_health_checks)

        # All nodes should have the same running version
        if length(Enum.uniq(vsn_list)) != 1 do
          Logger.error("Multiple version found #{inspect(vsn_list)}")
        end

        data = %Workflow.Data{data | namespace_state: ns_state_new}
        {state, actions} = Workflow.next(@state_name, :nodedown, release_version)

        Logger.info(
          "Re-initializing nodes with failed health check #{inspect(failed_health_checks)}"
        )

        {:next_state, state, data, actions}
      else
        timer_ref = Release.schedule_health_check(hc_spec)
        data = %Workflow.Data{data | health_check_timer: timer_ref}
        {:keep_state, data, []}
      end
    end
  end

  def handle_event(:internal, :schedule_health_check, _state, data) do
    %Workflow.Data{
      release_spec: %Release.Spec{health_check_spec: health_check_spec},
      health_check_timer: health_check_timer
    } = data

    if health_check_timer != nil do
      :erlang.cancel_timer(health_check_timer)
    end

    timer_ref = Release.schedule_health_check(health_check_spec)
    data = %Workflow.Data{data | health_check_timer: timer_ref}
    {:keep_state, data, []}
  end

  # When a node goes down on a given host we disconnect from that host remove
  # the node from `namespace_state` and transition to initialization phase to
  # ensure the given version is running on all hosts in the namespace
  def handle_event(_any, {:nodedown, node}, _state, data) do
    Logger.warn("Node down #{node}")
    hostname = to_hostname(node)
    %Workflow.Data{namespace_state: ns_state, release_spec: release_spec} = data
    # `release_version` is the version of the release running on `hostname`
    {namespace_state, release_version} =
      Namespace.drop_release_state(ns_state, release_spec, hostname)

    data = %Workflow.Data{data | namespace_state: namespace_state}
    {state, actions} = Workflow.next(@state_name, :nodedown, release_version)

    Logger.info("Re-initializing #{node} with version #{release_version}")
    {:next_state, state, data, actions}
  end

  def handle_event(any, event, state, _data) do
    Logger.warn("Unexpected event #{inspect({any, event, state})}")
    {:keep_state_and_data, []}
  end

  defp to_hostname(node) do
    [_node_name, hostname] = node |> :erlang.atom_to_binary() |> String.split("@")
    hostname
  end

  defp check_health(namespace_state, %Release.Spec{} = release_spec, %Release.HealthCheckSpec{
         function: eval_fun
       }) do
    Namespace.rpc(namespace_state, release_spec, eval_fun, [])
    |> Enum.map(fn
      {{:ok, :ok}, node} -> {:ok, node}
      {_error, node} -> {:error, node}
    end)
    |> Enum.zip(namespace_state)
    |> Enum.filter(fn
      {{:ok, _node}, _release_state} -> false
      {{:error, _node}, _release_state} -> true
    end)
    |> Enum.map(fn {{:error, node}, release_state} -> {node, release_state} end)
  end

  defp process_failed_health_checks(
         ns_state,
         %Release.Spec{} = release_spec,
         failed_health_checks
       ) do
    Enum.reduce(failed_health_checks, {ns_state, []}, fn {node, release_state},
                                                         {ns_state_acc, vsn_acc} ->
      Logger.info("Stopping release node #{node}")
      try_stop_release(release_spec, release_state)

      {ns_state_acc, current_vsn} =
        Namespace.drop_release_state(ns_state_acc, release_spec, to_hostname(node))

      {ns_state_acc, [current_vsn | vsn_acc]}
    end)
  end

  defp try_stop_release(%Release.Spec{} = release_spec, %Release.State{host: host}) do
    try do
      Release.stop(release_spec, host)
    catch
      e, m ->
        Logger.error("Failed stop release on #{host.hostname} with error #{inspect({e, m})}")
    end
  end
end
