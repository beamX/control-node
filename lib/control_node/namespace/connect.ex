defmodule ControlNode.Namespace.Connect do
  @moduledoc false

  # @state_name :connect
  require Logger

  def callback_mode, do: :handle_event_function

  def handle_event(any, event, state, _data) do
    Logger.warn("Unexpected event #{inspect({any, event, state})}")
    {:keep_state_and_data, []}
  end
end
