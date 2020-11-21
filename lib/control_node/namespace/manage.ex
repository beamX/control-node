defmodule ControlNode.Namespace.Manage do
  @moduledoc false

  @state_name :manage
  require Logger
  alias ControlNode.Release
  alias ControlNode.Namespace.Workflow

  def callback_mode, do: :handle_event_function

  def handle_event({:call, from}, {:deploy, version}, _state, data) do
    {state, actions} = Workflow.next(@state_name, :trigger_deployment, version)
    actions = [{:reply, from, :ok} | actions]
    {:next_state, state, data, actions}
  end

  # When a node goes down on a given host we disconnect from that host name
  # remove the node from `namespace_state` and transition to initialization
  # phase to ensure the given version is running on all hosts in the namespace
  def handle_event(_any, {:nodedown, node}, _state, data) do
    Logger.warn("Node down #{node}")
    hostname = to_hostname(node)
    %Workflow.Data{namespace_state: ns_state, release_spec: release_spec} = data
    # `release_version` is the version of the release running on `hostname`
    {namespace_state, release_version} = drop_release_state(ns_state, release_spec, hostname)
    data = %Workflow.Data{data | namespace_state: namespace_state}
    {state, actions} = Workflow.next(@state_name, :nodedown, release_version)

    Logger.info("Re-initializing #{node} with version #{release_version}")
    {:next_state, state, data, actions}
  end

  def handle_event(any, event, state, _data) do
    Logger.warn("Unexpected event #{inspect({any, event, state})}")
    {:keep_state_and_data, []}
  end

  # Disconnect from the host where the node went down and remove the node from
  # namespace_state
  defp drop_release_state(namespace_state, release_spec, hostname) do
    {namespace_state, version} =
      Enum.map_reduce(namespace_state, nil, fn release_state, version ->
        if release_state.host.hostname == hostname do
          Release.terminate_state(release_spec, release_state)
          {nil, release_state.version}
        else
          {release_state, version}
        end
      end)

    {Enum.filter(namespace_state, fn e -> e end), version}
  end

  defp to_hostname(node) do
    [_node_name, hostname] = node |> :erlang.atom_to_binary() |> String.split("@")
    hostname
  end
end
