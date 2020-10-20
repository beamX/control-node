defmodule ControlNode.Namespace.Observe do
  require Logger

  def callback_mode, do: :handle_event_function

  def handle_event(any, event, state, _data) do
    Logger.warn("Unexpected event #{inspect({any, event, state})}")
    {:keep_state_and_data, []}
  end
end
