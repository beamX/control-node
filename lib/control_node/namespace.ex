defmodule ControlNode.Namespace do
  @moduledoc false
  @supervisor ControlNode.ReleaseSupervisor

  use GenServer
  require Logger
  alias ControlNode.{Host, Registry}

  defmodule Spec do
    @typedoc """
    `Namespace.Spec` defines a spec with the following attributes,

    * `:tag` : Tag for the namespace (eg: `:testing`)
    * `:hosts` : List of hosts where the release will be deployed.
    * `:registry_spec` : Defines the registry from where there release tar will
      be retireved for rolling out deployment in this namepsace
    * `:release_cookie` : Release cookie used by the release in this given
      namespace. This cookie will be used by control node to connect to the
      release nodes
     * `:control_mode` : Configures mode for the given namespace, default
       `"MANAGE"` . Other possible value is `"OBSERVE" | "CONNECT"` . In
       `"OBSERVE"` mode user will only be allowed to deploy and observe a
       release i.e. no failover mechanism are avaiable. In `"CONNECT"` mode the
       control will just connect to release nodes and no other operation (like
       deploy or failover) are executed.
    """

    @type t :: %__MODULE__{
            tag: atom,
            hosts: [Host.SSH.t()],
            registry_spec: Registry.Local.t(),
            deployment_type: atom,
            release_cookie: atom
          }
    defstruct tag: nil,
              hosts: nil,
              registry_spec: nil,
              deployment_type: :incremental_replace,
              release_management: :replica,
              release_cookie: nil,
              control_mode: "MANAGE"
  end

  def deploy(namespace_pid, version) do
    GenServer.cast(namespace_pid, {:deploy, version})
  end

  def current_version(namespace_pid) do
    GenServer.call(namespace_pid, :current_version)
  end

  def start_link(namespace_spec, release_mod) do
    name = :"#{namespace_spec.tag}_#{release_mod.release_name}"
    Logger.debug("Starting namespace with name #{name}")
    GenServer.start_link(__MODULE__, [namespace_spec, release_mod], name: name)
  end

  @impl true
  def init([namespace_spec, release_mod]) do
    Logger.metadata(namespace: namespace_spec.tag, release: release_mod.release_name())
    state = %{spec: namespace_spec, release_mod: release_mod}
    {:ok, state, {:continue, :start_release_fsm}}
  end

  @impl true
  def handle_continue(:start_release_fsm, state) do
    Logger.info("Initializing namespace manager")
    %{spec: namespace_spec, release_mod: release_mod} = state
    ensure_started_releases(namespace_spec, release_mod)
    {:noreply, state}
  end

  @impl true
  def handle_call(
        :current_version,
        _from,
        %{spec: namespace_spec, release_mod: release_mod} = state
      ) do
    version_list =
      Enum.map(namespace_spec.hosts, fn host_spec ->
        with {:ok, vsn} <- release_mod.current_version(namespace_spec, host_spec) do
          %{host: host_spec.host, version: vsn}
        end
      end)

    {:reply, {:ok, version_list}, state}
  end

  @impl true
  def handle_cast({:deploy, version}, %{spec: namespace_spec, release_mod: release_mod} = state) do
    Enum.map(namespace_spec.hosts, fn host_spec ->
      release_mod.deploy(namespace_spec, host_spec, version)
    end)

    {:noreply, state}
  end

  defp ensure_started_releases(namespace_spec, release_mod) do
    Enum.map(namespace_spec.hosts, fn host_spec ->
      start_release(release_mod, namespace_spec, host_spec)
    end)
  end

  defp start_release(release_mod, namespace_spec, host_spec) do
    spec = child_spec(release_mod, namespace_spec, host_spec)

    case DynamicSupervisor.start_child(@supervisor, spec) do
      {:ok, _pid} ->
        :ok

      {:ok, _pid, _info} ->
        :ok

      {:error, {:already_started, _pid}} ->
        Logger.info("Release already running")
        {:error, :already_running}

      error ->
        Logger.error(
          "Failed to release with args: #{inspect(host_spec)}, error: #{inspect(error)}"
        )

        {:error, error}
    end
  end

  defp child_spec(release_mod, namespace_spec, host_spec) do
    %{id: release_mod, start: {release_mod, :start_link, [namespace_spec, host_spec]}}
  end
end
