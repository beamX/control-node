defmodule ControlNode.Release do
  require Logger
  alias ControlNode.{Host, Epmd, Inet}

  defmodule HealthCheckSpec do
    @typedoc """
    Release.HealthCheckSpec defines health check configuration for the release.

    * `:function` : Health check function which will be evaluated in the release nodes.
    * `:interval` : Time interval after which health function shall be evaluated
      on release nodes.
    * `:on_failure` : Action to perform when a node failure is detected. Allowed values
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
    * `:start_timeout` : Time (in seconds) to wait for a release to start, `default: 5`
    * `:health_check_spec` : Health check config
    """

    @type t :: %__MODULE__{
            name: atom,
            base_path: String.t(),
            start_timeout: integer,
            health_check_spec: HealthCheckSpec.t()
          }
    defstruct name: nil,
              base_path: nil,
              start_timeout: 5,
              health_check_spec: %HealthCheckSpec{}
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
            pid: list,
            tunnel_port: integer,
            release_path: list
          }
    defstruct host: nil,
              version: nil,
              status: :not_running,
              port: nil,
              pid: nil,
              tunnel_port: nil,
              release_path: nil

    def new(host_spec), do: %__MODULE__{host: host_spec, status: :not_running}

    def nodedown(%__MODULE__{} = state), do: %__MODULE__{state | status: :not_running}
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @release_name opts[:spec].name
      @release_spec opts[:spec]

      @behaviour :gen_statem
      require Logger
      alias ControlNode.Release
      alias ControlNode.Namespace

      @doc """
      Get current release version running on the host

      Returns:

        - `{:ok, binary()}` : return the current running version

        - `{:ok, nil}` : `nil` implies that release was not found registered with the EMPD or the EMPD was not running at all

        - `:busy` : implies that release process was initializing state or deploying a release
      """
      @spec current_version(Namespace.Spec.t(), ControlNode.Host.SSH.t()) ::
              {:ok, binary} | {:ok, nil} | {:ok, :busy}
      def current_version(%Namespace.Spec{} = namespace_spec, host_spec) do
        name(namespace_spec.tag, @release_name, host_spec.host)
        |> call(:current_version)
      end

      @doc """
      Deploy a new version of the service to the given host

      Returns:

        - `:ok` : Process has started deploying the new version on the given host

        - `:busy`: Process is busy deploying a release
      """
      @spec deploy(Namespace.Spec.t(), ControlNode.Host.SSH.t(), binary) :: :ok | :busy
      def deploy(%Namespace.Spec{} = namespace_spec, host_spec, version) do
        name(namespace_spec.tag, @release_name, host_spec.host)
        |> call({:deploy, version})
      end

      @doc """
      Stop the release version
      """
      def stop_release(%Namespace.Spec{} = namespace_spec, host_spec) do
        name(namespace_spec.tag, @release_name, host_spec.host)
        |> :gen_statem.call(:stop)
      end

      defp call(pid, msg) do
        try do
          :gen_statem.call(pid, msg, 1000)
        catch
          err, {:timeout, _} ->
            :busy

          other ->
            {:error, other}
        end
      end

      @doc """
      (Helper) Returns the name of the release handled by the process
      """
      def release_name, do: @release_name

      defp name(namespace_tag, release_name, hostname) do
        {:via, Registry, {ControlNode.ReleaseRegistry, {namespace_tag, release_name, hostname}}}
      end

      @doc false
      def start_link(%Namespace.Spec{} = namespace_spec, host_spec) do
        name = name(namespace_spec.tag, @release_name, host_spec.host)
        :gen_statem.start_link(name, __MODULE__, [namespace_spec, host_spec], [])
      end

      @impl :gen_statem
      def callback_mode, do: :handle_event_function

      @impl :gen_statem
      def init([%Namespace.Spec{control_mode: control_mode} = namespace_spec, host_spec]) do
        control_mode = System.get_env("CONTROL_MODE", nil) || control_mode
        namespace_spec = %Namespace.Spec{namespace_spec | control_mode: control_mode}

        %Release.Spec{name: release_name} = @release_spec

        data = %Namespace.Workflow.Data{
          namespace_spec: namespace_spec,
          release_spec: @release_spec,
          release_state: State.new(host_spec)
        }

        Logger.metadata(
          release_name: release_name,
          namespace: namespace_spec.tag,
          host: host_spec.host
        )

        {state, actions} = Namespace.Workflow.init(control_mode)
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
  @spec initialize_state(Release.Spec.t(), ControlNode.Host.SSH.t(), :atom) ::
          Release.State.t()
  def initialize_state(release_spec, host_spec, cookie) do
    with {:ok, %Host.Info{services: services}} <- Host.info(host_spec) do
      case Map.get(services, release_spec.name) do
        nil ->
          State.new(host_spec)

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

            release_pid = rpc(release_state, release_spec, &:os.getpid/0, [])

            case get_version(release_spec, host_spec) do
              {:ok, version} ->
                %State{release_state | version: version, pid: release_pid}

              _ ->
                Logger.warn(
                  "No version found for release #{release_spec.name} on host #{host_spec.host}"
                )

                release_state
            end
          end
      end
    else
      {:error, :no_data} ->
        # Since no data was received from EPMD, assume that the release is not running
        Logger.info("Failed to get node information from EPMD. Maybe EPMD is not running.")
        State.new(host_spec)
    end
  end

  defp release_path(release_spec, host_spec) do
    with {:ok, node} <- to_node_name(release_spec, host_spec) do
      :erpc.call(node, :code, :root_dir, [])
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
      :erpc.call(node, :init, :stop, [0])
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

  def is_running?(release_spec, host_spec) do
    case node_info(release_spec, host_spec) do
      {:ok, _} -> true
      _ -> false
    end
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

    case :erpc.call(node, :application, :get_key, [release_spec.name, :vsn]) do
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
    case :erpc.call(node, :release_handler, :which_releases, []) do
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
  @spec deploy(Spec.t(), Host.SSH.t(), ControlNode.Registry.Local.t(), binary) ::
          :ok | {:error, Host.SSH.ExecStatus.t()}
  def deploy(%Spec{} = release_spec, host_spec, registry_spec, version) do
    # WARN: may not work if host OS is different from control-node OS
    host_release_dir = Path.join(release_spec.base_path, version)
    host_release_path = Path.join(host_release_dir, "#{release_spec.name}-#{version}.tar.gz")

    with {:ok, tar_file} <- ControlNode.Registry.fetch(registry_spec, release_spec.name, version),
         :ok <- Host.upload_file(host_spec, host_release_path, tar_file),
         :ok <- Host.extract_tar(host_spec, host_release_path, host_release_dir) do
      init_file = Path.join(host_release_dir, "bin/#{release_spec.name}")
      Host.init_release(host_spec, init_file, :daemon)
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

  def rpc(release_state, release_spec, eval_fun, args) do
    case to_node_name(release_spec, release_state.host) do
      {:ok, node} ->
        :erpc.call(node, :erlang, :apply, [eval_fun, args])

      _ ->
        Logger.error("Error while getting node name")
        :error
    end
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
