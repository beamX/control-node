defmodule ControlNode.Namespace.Initialize do
  @moduledoc false
  @state_name :initialize

  # `Initialize` is the first state of the namespace FSM

  require Logger
  alias ControlNode.{Release, Namespace}
  alias Namespace.Workflow

  def callback_mode, do: :handle_event_function

  def handle_event(:internal, current_state, :initialize, data)
      when current_state in [:observe_release_state, :connect_release_state] do
    %Workflow.Data{
      namespace_spec: namespace_spec,
      release_spec: release_spec,
      release_state: release_state
    } = data

    release_state =
      Release.initialize_state(
        release_spec,
        release_state.host,
        namespace_spec.release_cookie
      )

    data = %Workflow.Data{data | release_state: release_state}
    {next_state, actions} = Namespace.Workflow.next(@state_name, current_state, nil)
    {:next_state, next_state, data, actions}
  end

  def handle_event(:internal, :load_release_state, :initialize, data) do
    Logger.info("Loading release state")

    %Workflow.Data{namespace_spec: namespace_spec, release_spec: release_spec} = data

    %Release.State{} =
      release_state =
      Release.initialize_state(
        release_spec,
        data.release_state.host,
        namespace_spec.release_cookie
      )

    Logger.info("Loaded release state", release_state: inspect(release_state))

    data = %Workflow.Data{data | release_state: release_state}

    if is_running?(release_state) do
      %Release.State{version: version} = release_state
      Logger.info("Release version #{version} running")
      {state, actions} = Namespace.Workflow.next(@state_name, :running, version)
      {:next_state, state, data, actions}
    else
      Logger.info("Release not running")
      {state, actions} = Namespace.Workflow.next(@state_name, :not_running, :ignore)
      {:next_state, state, data, actions}
    end
  end

  def handle_event(
        :internal,
        {:load_release_state, version},
        :initialize,
        %Workflow.Data{deploy_attempts: deploy_attempts} = data
      )
      when deploy_attempts >= 5 do
    Logger.error("Depoyment attempts exhausted, failed to deploy release version #{version}")
    {state, actions} = Namespace.Workflow.next(@state_name, :not_running, :ignore)
    data = %Workflow.Data{data | deploy_attempts: 0}

    {:next_state, state, data, actions}
  end

  def handle_event(:internal, {:load_release_state, version}, :initialize, data) do
    Logger.info("Loading release state, expected version #{version}")

    %Workflow.Data{
      namespace_spec: %Namespace.Spec{release_cookie: cookie},
      release_spec: release_spec,
      release_state: %Release.State{host: host_spec} = curr_release_state
    } = data

    # Flush the current release state
    Release.terminate_state(release_spec, curr_release_state)

    # Build a new release state view
    %Release.State{version: current_version} =
      release_state = Release.initialize_state(release_spec, host_spec, cookie)

    {namespace_status, new_deploy_attempts} =
      if is_current_version?(release_state, version) do
        Logger.info("Release state loaded, current version #{version}")

        {:running, 0}
      else
        Logger.warn("Release state loaded, expected version #{version} found #{current_version}")

        {:partially_running, data.deploy_attempts}
      end

    data = %Workflow.Data{
      data
      | release_state: release_state,
        deploy_attempts: new_deploy_attempts
    }

    {state, actions} = Namespace.Workflow.next(@state_name, namespace_status, version)
    {:next_state, state, data, actions}
  end

  def handle_event({_call, from}, _event, _state, _data),
    do: {:keep_state_and_data, [{:reply, from, :busy}]}

  def handle_event(_any, _event, _state, _data), do: {:keep_state_and_data, []}

  defp is_current_version?(%Release.State{version: version}, new_version) do
    version == new_version
  end

  defp is_running?(%Release.State{status: status}) do
    status == :running
  end
end
