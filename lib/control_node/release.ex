defmodule ControlNode.Release do
  require Logger
  alias ControlNode.{Host, Registry, Epmd, Inet}

  defmodule Spec do
    @type t :: %__MODULE__{name: atom, base_path: String.t()}
    defstruct name: nil, base_path: nil
  end

  defmodule State do
    @type t :: %__MODULE__{host: Host.SSH.t(), version: String.t(), status: atom, port: integer}
    defstruct host: nil, version: nil, status: nil, port: nil
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @release_name opts[:spec].name
      @release_spec opts[:spec]

      @behaviour :gen_statem
      alias ControlNode.Release
      alias ControlNode.Namespace

      def resolve_version(namespace_tag, version) do
        :gen_statem.call(name(namespace_tag), {:resolve_version, version})
      end

      defp name(tag), do: :"#{@release_name}_#{tag}"

      def start_link(namespace_spec) do
        name = {:local, name(namespace_spec.tag)}
        :gen_statem.start_link(name, __MODULE__, namespace_spec, [])
      end

      @impl :gen_statem
      def callback_mode, do: :handle_event_function

      @impl :gen_statem
      def init(namespace_spec) do
        data = %Namespace.Workflow.Data{
          release_spec: @release_spec,
          namespace_spec: namespace_spec,
          namespace_state: nil
        }

        {state, actions} = Namespace.Workflow.init()
        {:ok, state, data, actions}
      end
    end
  end

  def initialize_state(release_spec, host_spec, cookie) do
    with {:ok, %Host.Info{services: services}} <- Host.info(host_spec) do
      case Map.get(services, release_spec.name) do
        nil ->
          %State{host: host_spec, status: :not_running}

        service_port ->
          with %Host.SSH{} = host_spec <- Host.connect(host_spec),
               {:ok, host_spec} <- Host.hostname(host_spec) do
            # register node locally
            register_node(release_spec, host_spec, service_port)

            # Setup tunnel to release port on host
            :ok = Host.tunnel_to_service(host_spec, service_port)
            true = connect_and_monitor(release_spec, host_spec, cookie)

            {:ok, version} = get_version(release_spec, host_spec)

            %State{host: host_spec, version: version, status: :running, port: service_port}
          end
      end
    end
  end

  def terminate_state(%State{host: host_spec} = release_state) do
    try do
      Host.disconnect(host_spec)
    catch
      error, message ->
        Logger.error("Failed to terminate state",
          release_state: release_state,
          error: error,
          message: message
        )
    end
  end

  def terminate(release_spec, %State{host: host_spec}) do
    node = to_node_name(release_spec, host_spec)

    # demonitor node so that {:nodedown, node} message is not generated when the
    # node is stopped
    true = Node.monitor(node, false)

    # stop node
    :rpc.call(node, :init, :stop, [0])
    true = check_until_stopped(release_spec, host_spec)

    :ok
  end

  defp check_until_stopped(release_spec, host_spec) do
    Enum.any?(1..50, fn ->
      :timer.sleep(100)
      {:error, :release_not_running} == node_info(release_spec, host_spec)
    end)
  end

  defp node_info(release_spec, host_spec) do
    with {:ok, %Host.Info{services: services}} <- Host.info(host_spec) do
      case Map.get(services, release_spec.name) do
        nil ->
          {:error, :release_not_running}

        service_port when is_integer(service_port) ->
          {:ok, service_port}
      end
    end
  end

  defp register_node(release_spec, host_spec, service_port) do
    # NOTE: Configure host config for inet
    # This config will be used by BEAM to resolve `hostname`
    Inet.add_alias_for_localhost(host_spec.hostname)
    Epmd.register_release(release_spec.name, host_spec.hostname, service_port)
  end

  defp get_version(release_spec, host_spec) do
    {:ok, node} = to_node_name(release_spec, host_spec)
    {:ok, vsn} = :rpc.call(node, :application, :get_key, [release_spec.name, :vsn])
    {:ok, :erlang.list_to_binary(vsn)}
  end

  @doc """
  Deploys a release to the host specified by `host_spec`

  NOTE: Prior to calling this function it should be ensured that no release with
  name `release_spec.name` is running on host specified by `host_spec`
  """
  @spec deploy(Spec.t(), Host.SSH.t(), Registry.Local.t(), binary) ::
          :ok | {:error, Host.SSH.ExecStatus.t()}
  def deploy(%Spec{} = release_spec, host_spec, registry_spec, version) do
    # WARN: may not work if host OS is different from control-node OS
    host_release_dir = Path.join(release_spec.base_path, version)
    host_release_path = Path.join(host_release_dir, "#{release_spec.name}-#{version}.tar.gz")

    with {:ok, tar_file} <- Registry.fetch(registry_spec, release_spec.name, version),
         :ok <- Host.upload_file(host_spec, host_release_path, tar_file),
         :ok <- Host.extract_tar(host_spec, host_release_path, host_release_dir) do
      init_file = Path.join(host_release_dir, "bin/#{release_spec.name}")
      Host.init_release(host_spec, init_file, :start)
    end
  end

  @doc """
  Stops the release running on `host_spec`
  """
  @spec stop(Spec.t(), Host.SSH.t()) :: term | {:badrpc, term}
  def stop(%Spec{} = release_spec, host_spec) do
    with {:ok, node} <- to_node_name(release_spec, host_spec) do
      if is_connected?(node) do
        :rpc.call(node, :init, :stop, [0])
      else
        {:error, :node_not_connected}
      end
    end
  end

  defp is_connected?(node) do
    connected_nodes = :erlang.nodes(:connected)
    node in connected_nodes
  end

  @doc """
  Creates a SSH tunnel to remote service and forwards a local port to
  the remote service port.

  NOTE: remote service's port is the one registered with the EPMD service
  running on the remote host
  """
  @spec setup_tunnel(Spec.t(), Host.SSH.t()) ::
          {:ok, integer} | {:error, :release_not_running}
  def setup_tunnel(release_spec, host_spec) do
    with {:ok, %Host.Info{services: services}} <- Host.info(host_spec) do
      case Map.get(services, release_spec.name) do
        nil ->
          {:error, :release_not_running}

        service_port when is_integer(service_port) ->
          :ok = Host.tunnel_to_service(host_spec, service_port)
          {:ok, service_port}
      end
    end
  end

  def connect_and_monitor(release_spec, host_spec, cookie) do
    connect(release_spec, host_spec, cookie, true)
  end

  @doc """
  Connects to a remote release via `Node.connect/1`

  NOTE: Assumes that a SSH tunnel has been setup to the remote service
  """
  @spec connect(Spec.t(), Host.SSH.t(), atom) :: true | false
  def connect(release_spec, host_spec, cookie, monitor_node? \\ false) do
    with {:ok, node} <- to_node_name(release_spec, host_spec) do
      true = Node.set_cookie(node, cookie)
      true = Node.connect(node)

      if monitor_node? do
        Node.monitor(node, true)
      else
        true
      end
    end
  end

  defp to_node_name(_release_spec, %Host.SSH{hostname: nil}), do: {:error, :hostname_not_found}

  defp to_node_name(release_spec, host_spec),
    do: {:ok, :"#{release_spec.name}@#{host_spec.hostname}"}
end
