defmodule ControlNode.Namespace.Manage do
  @moduledoc false

  @state_name :manage

  require Logger
  alias ControlNode.{Namespace.Workflow, Release}

  def callback_mode, do: :handle_event_function

  def handle_event({:call, from}, :stop, _state, data) do
    %Workflow.Data{
      release_spec: %Release.Spec{} = release_spec,
      release_state: %Release.State{} = release_state
    } = data

    try_stop_release(release_spec, release_state)

    {state, actions} = Workflow.next(@state_name, :release_stopped, nil)
    actions = [{:reply, from, :ok} | actions]
    {:next_state, state, data, actions}
  end

  # NOTE: deploy event is also handled in :observe state
  def handle_event({:call, from}, {:deploy, version}, _state, data) do
    {state, actions} = Workflow.next(@state_name, :trigger_deployment, version)
    actions = [{:reply, from, :ok} | actions]
    {:next_state, state, data, actions}
  end

  def handle_event(_from, :check_health, _state, data) do
    Logger.debug("Checking release health ...")

    %Workflow.Data{
      release_spec: %Release.Spec{health_check_spec: hc_spec} = release_spec,
      release_state: %Release.State{version: version} = release_state
    } = data

    if is_healthy?(release_state, release_spec, hc_spec) do
      Logger.info("Release is healthy")

      timer_ref = Release.schedule_health_check(hc_spec)
      data = %Workflow.Data{data | health_check_timer: timer_ref}
      {:keep_state, data, []}
    else
      Logger.warn("Release health check failed")

      # TODO: respect max failure count before rebooting the release
      if hc_spec.on_failure == :reboot do
        # TODO| in case the node is not responding we might need to kill the process
        # TODO| stop nodes with failed health checks
        # Remove nodes which failed health check from namespace_state
        Logger.info("Stopping release")

        # Ensure that release is stopped
        try_stop_release(release_spec, release_state)
        release_state = Release.State.nodedown(release_state)
        data = %Workflow.Data{data | release_state: release_state}
        {state, actions} = Workflow.next(@state_name, :nodedown, version)

        Logger.info("Restarting release")
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

  # When a node goes down on a given host, the release state is updated
  # with status: not_running and FSM transitions to :initialize phase
  def handle_event(_any, {:nodedown, _node}, _state, data) do
    Logger.error("Release nodedown")
    %Workflow.Data{release_state: %Release.State{version: version} = release_state} = data

    # TODO: ensure that the release pid is not running
    release_state = Release.State.nodedown(release_state)

    data = %Workflow.Data{data | release_state: release_state}
    {state, actions} = Workflow.next(@state_name, :nodedown, version)

    {:next_state, state, data, actions}
  end

  def handle_event(any, event, state, _data) do
    Logger.warn("Unexpected event #{inspect({any, event, state})}")
    {:keep_state_and_data, []}
  end

  defp is_healthy?(release_state, %Release.Spec{} = release_spec, %Release.HealthCheckSpec{
         function: eval_fun
       }) do
    case Release.rpc(release_state, release_spec, eval_fun, []) do
      {:ok, :ok} -> true
      _ -> false
    end
  end

  defp try_stop_release(%Release.Spec{} = release_spec, %Release.State{} = release_state) do
    try do
      Release.stop(release_spec, release_state)
    catch
      e, m ->
        Logger.error("Failed to stop release, #{inspect({e, m})}")
    end
  end
end
