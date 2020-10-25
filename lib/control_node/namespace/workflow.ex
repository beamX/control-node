defmodule ControlNode.Namespace.Workflow do
  @moduledoc false

  alias ControlNode.{Namespace, Release}

  defmodule Data do
    @moduledoc false

    @type t :: %__MODULE__{
            namespace_spec: Namespace.Spec.t(),
            release_spec: Release.Spec.t(),
            namespace_state: [Release.State.t()]
          }
    defstruct namespace_spec: nil, release_spec: nil, namespace_state: nil, deploy_attempts: 0
  end

  def init() do
    init(System.get_env("CONTROL_MODE", "MANAGE"))
  end

  defp init("MANAGE") do
    actions = [
      {:change_callback_module, ControlNode.Namespace.Initialize},
      {:next_event, :internal, :load_namespace_state}
    ]

    {:initialize, actions}
  end

  defp init("OBSERVE") do
    actions = [
      {:change_callback_module, ControlNode.Namespace.Initialize},
      {:next_event, :internal, :observe_namespace_state}
    ]

    {:initialize, actions}
  end

  @doc """
  When there is no release running on any host for a given namespace, the workflow
  switches to managing the namespace and wait request for new deployment
  """
  def next(:initialize, :not_running, _) do
    actions = [{:change_callback_module, Namespace.Manage}]

    {:manage, actions}
  end

  def next(:initialize, :partially_running, version) do
    actions = [
      {:change_callback_module, Namespace.Deploy},
      {:next_event, :internal, {:ensure_running, version}}
    ]

    {:deploy, actions}
  end

  def next(:initialize, :running, _version) do
    actions = [{:change_callback_module, Namespace.Manage}]

    {:manage, actions}
  end

  def next(:initialize, :observe_namespace_state, _version) do
    actions = [{:change_callback_module, Namespace.Observe}]

    {:observe, actions}
  end

  def next(:deploy, :executed, version) do
    actions = [
      {:change_callback_module, Namespace.Initialize},
      {:next_event, :internal, {:load_namespace_state, version}}
    ]

    {:initialize, actions}
  end

  def next(:manage, :trigger_deployment, version) do
    actions = [
      {:change_callback_module, Namespace.Deploy},
      {:next_event, :internal, {:ensure_running, version}}
    ]

    {:deploy, actions}
  end
end
