defmodule ControlNode.Namespace.Workflow do
  def init() do
    actions = [
      {:change_callback_module, ControlNode.Namespace.Initialize},
      {:next_event, :internal, :load_namespace_state}
    ]

    {:initialize, actions}
  end

  @doc """
  When there is no release running on any host for a given namespace, the workflow
  switches to managing the namespace and wait request for new deployment
  """
  def next(:initialize, :not_running, _) do
    actions = [{:change_callback_module, ControlNode.Namespace.Manage}]

    {:manage, actions}
  end

  def next(:initialize, :running, version) do
    actions = [
      {:change_callback_module, ControlNode.Namespace.Deploy},
      {:next_event, :internal, {:ensure_running, version}}
    ]

    {:deploy, actions}
  end
end
