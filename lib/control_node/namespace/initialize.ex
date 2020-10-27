defmodule ControlNode.Namespace.Initialize do
  @moduledoc false
  @state_name :initialize

  # `Initialize` is the first state of the namespace FSM
  # The name is can be in one of the following states,
  # 1. Release is running on some or all hosts with same version
  # 2. Release is not running any host
  # 3. TODO Release is running on some or all hosts with different version

  require Logger
  alias ControlNode.{Release, Namespace}
  alias Namespace.Workflow

  def callback_mode, do: :handle_event_function

  def handle_event(:internal, :observe_namespace_state, :initialize, data) do
    %Workflow.Data{namespace_spec: namespace_spec, release_spec: release_spec} = data

    namespace_state =
      Enum.map(namespace_spec.hosts, fn host_spec ->
        Release.initialize_state(release_spec, host_spec, namespace_spec.release_cookie)
      end)

    data = %Workflow.Data{data | namespace_state: namespace_state}
    {state, actions} = Namespace.Workflow.next(@state_name, :observe_namespace_state, nil)
    {:next_state, state, data, actions}
  end

  def handle_event(:internal, :load_namespace_state, :initialize, data) do
    %Workflow.Data{namespace_spec: namespace_spec, release_spec: release_spec} = data

    namespace_state =
      Enum.map(namespace_spec.hosts, fn host_spec ->
        Release.initialize_state(release_spec, host_spec, namespace_spec.release_cookie)
      end)

    data = %Workflow.Data{data | namespace_state: namespace_state}

    if is_running?(namespace_state) do
      # TODO: switch to deploy only when a host doesn't have a release running
      case has_unique_version?(namespace_state) do
        {true, version} ->
          Logger.info(
            "Release #{release_spec.name} with version #{version} running in namespace #{
              namespace_spec.tag
            }"
          )

          {state, actions} = Namespace.Workflow.next(@state_name, :partially_running, version)
          {:next_state, state, data, actions}

        false ->
          Logger.warn(
            "Release #{release_spec.name} running different versions in namespace #{
              namespace_spec.tag
            }"
          )

          {:next_state, :version_conflict, data}
      end
    else
      Logger.info("Release #{release_spec.name} not running in namespace #{namespace_spec.tag}")
      {state, actions} = Namespace.Workflow.next(@state_name, :not_running, :ignore)
      {:next_state, state, data, actions}
    end
  end

  def handle_event(
        :internal,
        {:load_namespace_state, _version},
        :initialize,
        %Workflow.Data{
          deploy_attempts: deploy_attempts
        } = data
      )
      when deploy_attempts >= 5 do
    {:next_state, :failed_deployment, data}
  end

  def handle_event(:internal, {:load_namespace_state, version}, :initialize, data) do
    %Workflow.Data{namespace_spec: namespace_spec, release_spec: release_spec} = data

    namespace_state =
      Enum.map(namespace_spec.hosts, fn host_spec ->
        Release.initialize_state(release_spec, host_spec, namespace_spec.release_cookie)
      end)

    {namespace_status, new_deploy_attempts} =
      if is_current_version?(namespace_state, version) do
        Logger.info(
          "Release #{release_spec.name} with version #{version} running in namespace #{
            namespace_spec.tag
          }"
        )

        {:running, 0}
      else
        Logger.info(
          "Release #{release_spec.name} with version #{version} partially running in namespace #{
            namespace_spec.tag
          }"
        )

        {:partially_running, data.deploy_attempts}
      end

    data = %Workflow.Data{
      data
      | namespace_state: namespace_state,
        deploy_attempts: new_deploy_attempts
    }

    {state, actions} = Namespace.Workflow.next(@state_name, namespace_status, version)
    {:next_state, state, data, actions}
  end

  def handle_event({:call, from}, {:resolve_version, version}, :version_confict, data) do
    {state, actions} = Namespace.Workflow.next(@state_name, :partially_running, version)
    actions = [{:reply, from, :ok} | actions]
    {:next_state, state, data, actions}
  end

  def handle_event({_call, from}, _event, _state, _data),
    do: {:keep_state_and_data, [{:reply, from, :busy}]}

  def handle_event(_any, _event, _state, _data), do: {:keep_state_and_data, []}

  defp is_current_version?(namespace_state, new_version) do
    Enum.all?(namespace_state, fn %{version: version} -> version == new_version end)
  end

  defp has_unique_version?(namespace_state) do
    namespace_state
    |> Enum.filter(fn %{status: status} -> status == :running end)
    |> Enum.uniq_by(fn %{version: version} -> version end)
    |> case do
      [%{version: version}] -> {true, version}
      [_ | _] -> false
    end
  end

  defp is_running?(namespace_state) do
    Enum.any?(namespace_state, fn %{status: status} -> status == :running end)
  end
end
