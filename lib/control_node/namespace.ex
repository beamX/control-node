defmodule ControlNode.Namespace do
  @moduledoc false

  alias ControlNode.{Release, Host, Registry}

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

  def add_host(%Spec{hosts: hosts} = namespace_spec, %Host.SSH{host: new_host} = host_spec) do
    current_hosts = Enum.map(hosts, fn %Host.SSH{host: host} -> host end)

    if new_host in current_hosts do
      {:error, :host_already_exists}
    else
      {:ok, %Spec{namespace_spec | hosts: [host_spec | hosts]}}
    end
  end

  def remove_host(
        %Spec{hosts: hosts} = namespace_spec,
        namespace_state,
        %Release.Spec{} = release_spec,
        host
      ) do
    Enum.find(namespace_state, fn %Release.State{host: host_spec} -> host_spec.host == host end)
    |> case do
      nil ->
        {:ok, namespace_spec, namespace_state}

      %Release.State{} = release_state ->
        :ok = Release.stop(release_spec, release_state)
        Release.terminate_state(release_spec, release_state)

        new_namespace_state =
          Enum.filter(namespace_state, fn %Release.State{host: host_spec} ->
            host_spec.host != host
          end)

        new_hosts = Enum.filter(hosts, fn %Host.SSH{} = host_spec -> host_spec.host != host end)

        new_namespace_spec = %Spec{namespace_spec | hosts: new_hosts}

        {:ok, new_namespace_spec, new_namespace_state}
    end
  end

  def get_current_version(namespace_state) do
    Enum.map(namespace_state, fn %Release.State{version: version} -> version end)
    |> Enum.uniq()
    |> case do
      [version] -> {:ok, version}
      versions -> {:error, {:multiple_version_running, versions}}
    end
  end

  # Disconnect from the host where the node went down and remove the node from
  # namespace_state
  def drop_release_state(namespace_state, release_spec, hostname) do
    {namespace_state, version} =
      Enum.map_reduce(namespace_state, nil, fn release_state, version ->
        if release_state.host.hostname == hostname do
          Release.terminate_state(release_spec, release_state)
          {nil, release_state.version}
        else
          {release_state, version}
        end
      end)

    {Enum.filter(namespace_state, fn e -> e end), version}
  end

  def rpc(namespace_state, release_spec, eval_fun, args) do
    nodes =
      Enum.map(namespace_state, fn %Release.State{} = release_state ->
        case Release.to_node_name(release_spec, release_state.host) do
          {:ok, node} -> node
          _ -> "no_node_name@no_host"
        end
      end)

    :erpc.multicall(nodes, :erlang, :apply, [eval_fun, args])
    |> Enum.zip(nodes)
  end
end
