defmodule ControlNode.Release do
  require Logger
  alias ControlNode.{Host, Registry, Epmd, Inet}

  defmodule HealthCheckSpec do
    @typedoc """
    Release.HealthCheckSpec defines health check configuration for the release.

    * `:function` : Health check function which will be evaluated in the release nodes.
    * `:interval` : Time interval after which health function shall be evaluated
      on release nodes.
    * `:on_failure` : Action to perform when node(s) failure is detected. Allowed values
    `:reboot | :noop`
    """

    @type t :: %__MODULE__{
            function: (() -> :ok | any),
            interval: pos_integer(),
            on_failure: atom
          }
    defstruct function: nil, interval: 5, on_failure: :reboot
  end

  defmodule Spec do
    @typedoc """
    Release.Spec defines configuration for the release to be deployed and monitored.

    * `:name` : Name of the release
    * `:base_path` : Path on remote host where the release should be uploaded
    """

    @type t :: %__MODULE__{
            name: atom,
            base_path: String.t(),
            health_check_spec: HealthCheckSpec.t()
          }
    defstruct name: nil, base_path: nil, health_check_spec: %HealthCheckSpec{}
  end

  defmodule State do
    @typedoc """
    `Release.State` defines the configuration for the release to be deployed and monitored.

    * `:host` : Spec of remote host where the release will be deployed and  where
    * `:version` : Version number of the release
    * `:status` : Status of the release, possible values `:running | :not_running`
    """

    @type t :: %__MODULE__{
            host: Host.SSH.t(),
            version: String.t(),
            status: atom,
            port: integer,
            tunnel_port: integer,
            release_path: list
          }
    defstruct host: nil, version: nil, status: nil, port: nil, tunnel_port: nil, release_path: nil
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

      @doc """
      Deploy a new version of the service to the given namespace.
      """
      def deploy(namespace_tag, version) do
        :gen_statem.call(name(namespace_tag), {:deploy, version})
      end

      @doc """
      Dynamically add a new host to a given namespace.
      NOTE: The Host should be added to NamespaceSpec to persist it across restarts
      """
      @spec add_host(atom, Host.SSH.t()) :: :ok | {:error, :host_already_exists}
      def add_host(namespace_tag, %Host.SSH{} = host) do
        :gen_statem.call(name(namespace_tag), {:add_host, host})
      end

      @doc """
      Dynamically remove a host from a given namespace.
      NOTE: The Host should be removed from NamespaceSpec to persist changes across restarts
      """
      @spec remove_host(atom, binary) :: :ok | {:error, :host_already_exists}
      def remove_host(namespace_tag, host) do
        :gen_statem.call(name(namespace_tag), {:remove_host, host})
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
        %Release.Spec{} = @release_spec

        data = %Namespace.Workflow.Data{
          release_spec: @release_spec,
          namespace_spec: namespace_spec,
          namespace_state: []
        }

        {state, actions} = Namespace.Workflow.init()
        {:ok, state, data, actions}
      end
    end
  end

  @doc """
  With the given `release_spec`, `host_spec` and `cookie` tries to connect to
  the release running on the remote host. In case the release is running on the
  host a SSH tunnel is established and control node connects to the release (via
  `Node.connect/1`) and starts monitoring the release node.
  """
  def initialize_state(release_spec, host_spec, cookie) do
    with {:ok, %Host.Info{services: services}} <-
           Host.info(host_spec) do
      case Map.get(services, release_spec.name) do
        nil ->
          %State{host: host_spec, status: :not_running}

        service_port ->
          with %Host.SSH{} = host_spec <- Host.connect(host_spec),
               {:ok, host_spec} <- Host.hostname(host_spec) do
            # Setup tunnel to release port on host
            # TODO/NOTE/WARN random local port should be used to avoid having a clash
            # if the releases use the same port on different hosts
            {:ok, local_port} = Host.tunnel_to_service(host_spec, service_port)

            # register node locally
            register_node(release_spec, host_spec, local_port)
            true = connect_and_monitor(release_spec, host_spec, cookie)

            release_state = %State{
              host: host_spec,
              status: :running,
              port: service_port,
              tunnel_port: local_port,
              release_path: release_path(release_spec, host_spec)
            }

            case get_version(release_spec, host_spec) do
              {:ok, version} ->
                %State{release_state | version: version}

              _ ->
                Logger.warn(
                  "No version found for release #{release_spec.name} on host #{host_spec.host}"
                )

                release_state
            end
          end
      end
    end
  end

  defp release_path(release_spec, host_spec) do
    with {:ok, node} <- to_node_name(release_spec, host_spec) do
      :rpc.call(node, :code, :root_dir, [])
      |> :erlang.list_to_binary()
    end
  end

  def schedule_health_check(nil), do: nil

  def schedule_health_check(%HealthCheckSpec{function: nil}), do: nil

  def schedule_health_check(%HealthCheckSpec{interval: interval}) do
    :erlang.send_after(interval * 1000, self(), :check_health)
  end

  @doc """
  Stops monitoring the remote release and closes the SSH tunnel to the remote host
  """
  @spec terminate_state(Spec.t(), State.t()) :: Host.SSH.t()
  def terminate_state(release_spec, %State{host: host_spec} = release_state) do
    try do
      # Since connection to host exists it might be the case that the release is running
      # and it monitored
      demonitor_node(release_spec, host_spec)
      Host.disconnect(host_spec)
    catch
      error, message ->
        Logger.error("Failed to terminate state #{inspect({error, message})}",
          release_state: release_state,
          error: error,
          message: message
        )
    end
  end

  @doc """
  Stops the release node on a given remote host
  """
  def stop(release_spec, %State{host: host_spec}) do
    with {:ok, node} <- to_node_name(release_spec, host_spec) do
      # demonitor node so that {:nodedown, node} message is not generated when
      # the node is stopped
      Node.monitor(node, false)
      :rpc.call(node, :init, :stop, [0])
    end

    true = check_until_stopped(release_spec, host_spec)

    :ok
  end

  defp demonitor_node(release_spec, host_spec) do
    with {:ok, node} <- to_node_name(release_spec, host_spec) do
      # demonitor node so that {:nodedown, node} message is not generated when the
      # node is stopped
      Node.monitor(node, false)
    else
      _other ->
        Logger.warn("Failed to demonitor node", release_spec: release_spec, host_spec: host_spec)
    end
  end

  defp check_until_stopped(release_spec, host_spec) do
    Enum.any?(1..50, fn _ ->
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

    case :rpc.call(node, :application, :get_key, [release_spec.name, :vsn]) do
      {:ok, vsn} ->
        {:ok, :erlang.list_to_binary(vsn)}

      :undefined ->
        # It could be the case the application is an umbrella application
        release_name = :erlang.atom_to_list(release_spec.name)

        with {_name, vsn, _, _} <- get_release_version(node, release_name) do
          {:ok, :erlang.list_to_binary(vsn)}
        end
    end
  end

  defp get_release_version(node, release_name) do
    case :rpc.call(node, :release_handler, :which_releases, []) do
      [_] = releases ->
        Enum.find(releases, {:error, :release_not_found}, fn {name, _vsn, _, _} ->
          name == release_name
        end)

      error ->
        {:error, error}
    end
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

  @spec start(Spec.t(), State.t()) :: term
  def start(release_spec, %State{host: host_spec, release_path: release_path}) do
    init_file = Path.join(release_path, "bin/#{release_spec.name}")
    Host.init_release(host_spec, init_file, :start)
  end

  defp connect_and_monitor(release_spec, host_spec, cookie) do
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

  def to_node_name(_release_spec, %Host.SSH{hostname: nil}), do: {:error, :hostname_not_found}

  def to_node_name(release_spec, host_spec),
    do: {:ok, :"#{release_spec.name}@#{host_spec.hostname}"}
end
