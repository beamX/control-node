defmodule ControlNode.Namespace.Deploy do
  @moduledoc false
  @state_name :deploy

  # `Deploy` state of the namespace FSM ensure that a given version of the release
  # is running in the namespace
  # NOTE:
  # - In case a release fails to starts it must be retried continuously with exponential backoff

  require Logger
  alias ControlNode.{Namespace, Release}
  alias Namespace.Workflow

  def callback_mode, do: :handle_event_function

  def handle_event(:internal, {:ensure_running, version}, _state, data) do
    %Workflow.Data{
      namespace_spec: %Namespace.Spec{registry_spec: registry_spec, control_mode: control_mode},
      release_spec: release_spec,
      namespace_state: namespace_state
    } = data

    namespace_state =
      Enum.map(namespace_state, fn
        %Release.State{status: :running, version: ^version} = release_state ->
          release_state

        release_state ->
          with {:error, {error, message}} <-
                 ensure_running(release_state, release_spec, registry_spec, version) do
            # Either an error occurred when stopping the release or when deploying it
            Logger.error(
              "Failed while deploying release #{release_spec.name} to #{release_state.host.host}",
              error: error,
              message: message,
              release_state: inspect(release_state)
            )
          end

          nil
      end)
      |> Enum.filter(fn e -> e end)

    data = %Workflow.Data{
      data
      | namespace_state: namespace_state,
        deploy_attempts: data.deploy_attempts + 1
    }

    {state, actions} = Namespace.Workflow.next(@state_name, :executed, {control_mode, version})
    {:next_state, state, data, actions}
  end

  def handle_event({_call, from}, _event, _state, _data),
    do: {:keep_state_and_data, [{:reply, from, :busy}]}

  def handle_event(_any, _event, _state, _data), do: {:keep_state_and_data, []}

  defp ensure_running(
         %Release.State{status: :running} = release_state,
         release_spec,
         registry_spec,
         version
       ) do
    with {:ok, host_spec} <- try_stop(release_state, release_spec) do
      try_deploy(release_spec, host_spec, registry_spec, version)
    end
  end

  defp ensure_running(
         %Release.State{host: host_spec, status: :not_running},
         release_spec,
         registry_spec,
         version
       ) do
    try_deploy(release_spec, host_spec, registry_spec, version)
  end

  defp try_stop(release_state, release_spec) do
    try do
      :ok = Release.stop(release_spec, release_state)
    catch
      error, message -> {:error, {error, message}}
    end
  end

  defp try_deploy(release_spec, host_spec, registry_spec, version) do
    try do
      :ok = Release.deploy(release_spec, host_spec, registry_spec, version)
    catch
      error, message -> {:error, {error, message}}
    end
  end
end
