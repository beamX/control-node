defmodule ControlNode.Namespace.Observe do
  @moduledoc false

  @state_name :observe
  require Logger
  alias ControlNode.Namespace.Workflow

  def callback_mode, do: :handle_event_function

  def handle_event({:call, from}, {:deploy, version}, _state, data) do
    {state, actions} = Workflow.next(@state_name, :trigger_deployment, version)
    actions = [{:reply, from, :ok} | actions]
    {:next_state, state, data, actions}
  end

  def handle_event(any, event, state, _data) do
    Logger.warn("Unexpected event #{inspect({any, event, state})}")
    {:keep_state_and_data, []}
  end
end
