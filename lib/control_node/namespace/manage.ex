defmodule ControlNode.Namespace.Manage do
  @moduledoc false

  @state_name :manage
  require Logger
  alias ControlNode.{Namespace, Namespace.Workflow}

  def callback_mode, do: :handle_event_function

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
end
