defmodule ControlNode.Release do
  alias ControlNode.{Host, Registry}

  defmodule Spec do
    @type t :: %__MODULE__{name: atom, base_path: String.t(), start_strategy: atom}
    defstruct name: nil, base_path: nil, start_strategy: :restart
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

  @doc """
  Connects to a remote release via `Node.connect/1`

  NOTE: Assumes that a SSH tunnel has been setup to the remote service
  """
  @spec connect(Spec.t(), Host.SSH.t(), atom) :: true | false
  def connect(release_spec, host_spec, cookie) do
    with {:ok, node} <- to_node_name(release_spec, host_spec) do
      true = Node.set_cookie(node, cookie)
      Node.connect(node)
    end
  end

  defp to_node_name(_release_spec, %Host.SSH{hostname: nil}), do: {:error, :hostname_not_found}

  defp to_node_name(release_spec, host_spec),
    do: {:ok, :"#{release_spec.name}@#{host_spec.hostname}"}
end
