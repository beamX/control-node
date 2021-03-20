defmodule ControlNode.Namespace.Workflow do
  @moduledoc false

  alias ControlNode.{Namespace, Release}

  defmodule Data do
    @moduledoc false

    @type t :: %__MODULE__{
            namespace_spec: Namespace.Spec.t(),
            release_spec: Release.Spec.t(),
            release_state: Release.State.t(),
            health_check_timer: reference()
          }
    defstruct namespace_spec: nil,
              release_spec: nil,
              release_state: nil,
              deploy_attempts: 0,
              health_check_timer: nil
  end

  def init("CONNECT") do
    actions = [
      {:change_callback_module, ControlNode.Namespace.Initialize},
      {:next_event, :internal, :connect_release_state}
    ]

    {:initialize, actions}
  end

  def init("OBSERVE") do
    actions = [
      {:change_callback_module, ControlNode.Namespace.Initialize},
      {:next_event, :internal, :observe_release_state}
    ]

    {:initialize, actions}
  end

  def init("MANAGE") do
    actions = [
      {:change_callback_module, ControlNode.Namespace.Initialize},
      {:next_event, :internal, :load_release_state}
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
    actions = [
      {:change_callback_module, Namespace.Manage},
      {:next_event, :internal, :schedule_health_check}
    ]

    {:manage, actions}
  end

  def next(:initialize, :connect_release_state, _) do
    actions = [{:change_callback_module, Namespace.Connect}]

    {:connect, actions}
  end

  def next(:initialize, :observe_release_state, _) do
    actions = [{:change_callback_module, Namespace.Observe}]

    {:observe, actions}
  end

  def next(:deploy, :executed, {"OBSERVE", _version}) do
    actions = [
      {:change_callback_module, Namespace.Initialize},
      {:next_event, :internal, :observe_release_state}
    ]

    {:initialize, actions}
  end

  def next(:deploy, :executed, {"MANAGE", version}), do: initialize_with_version(version)

  def next(state_name, :trigger_deployment, version) when state_name in [:observe, :manage] do
    actions = [
      {:change_callback_module, Namespace.Deploy},
      {:next_event, :internal, {:ensure_running, version}}
    ]

    {:deploy, actions}
  end

  def next(:manage, :nodedown, version), do: initialize_with_version(version)

  defp initialize_with_version(version) do
    actions = [
      {:change_callback_module, Namespace.Initialize},
      {:next_event, :internal, {:load_release_state, version}}
    ]

    {:initialize, actions}
  end
end
