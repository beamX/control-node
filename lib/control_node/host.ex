defmodule ControlNode.Host do
  @moduledoc false

  require Logger
  alias ControlNode.Host.SSH
  @epmd_names 110
  @int16_1 [0, 1]

  defmodule Info do
    @moduledoc false

    @type t :: %__MODULE__{epmd_port: integer, services: map}
    defstruct epmd_port: nil, services: %{}
  end

  @spec connect(SSH.t()) :: SSH.t()
  def connect(host_spec), do: SSH.connect(host_spec)

  @spec disconnect(SSH.t()) :: SSH.t()
  def disconnect(host_spec), do: SSH.disconnect(host_spec)

  @spec upload_file(SSH.t(), binary, binary) :: :ok
  def upload_file(%SSH{} = host_spec, path, file) do
    Logger.debug("Copying release to remote host")
    SSH.upload_file(host_spec, path, file)
  end

  @spec extract_tar(SSH.t(), binary, binary) :: :ok | :failure | {:error, any}
  def extract_tar(%SSH{} = host_spec, release_path, release_dir) do
    Logger.debug("Extracting release on remove host")

    with {:ok, %SSH.ExecStatus{exit_code: 0}} <-
           SSH.exec(host_spec, "tar -xf #{release_path} -C #{release_dir}") do
      :ok
    end
  end

  @spec init_release(SSH.t(), binary, atom) :: :ok | :failure | {:error, any}
  def init_release(%SSH{} = host_spec, init_file, command) do
    with {:ok, %SSH.ExecStatus{exit_code: 0}} <-
           SSH.exec(host_spec, "#{init_file} #{command}", true) do
      :ok
    end
  end

  @spec stop_release(SSH.t(), binary) :: :ok | :failure | {:error, any}
  def stop_release(%SSH{} = host_spec, cmd) do
    with {:ok, %SSH.ExecStatus{exit_code: 0}} <- SSH.exec(host_spec, "nohup #{cmd} stop") do
      :ok
    end
  end

  @spec tunnel_to_service(SSH.t(), integer) :: {:ok, integer}
  def tunnel_to_service(%SSH{} = host_spec, service_port) do
    SSH.tunnel_port_to_server(host_spec, 0, service_port)
  end

  @spec hostname(SSH.t()) :: {:ok, binary}
  def hostname(%SSH{} = host_spec) do
    with {:ok, %SSH.ExecStatus{exit_status: :success, message: [hostname]}} <-
           SSH.exec(host_spec, "hostname") do
      {:ok, %SSH{host_spec | hostname: String.trim(hostname)}}
    end
  end

  @spec info(SSH.t()) :: {:ok, Info.t()} | {:error, :address | :no_data}
  def info(host_spec) do
    host_spec = connect(%{host_spec | conn: nil})

    with {:ok, info} <- epmd_list_names(host_spec) do
      disconnect(host_spec)
      {:ok, info}
    end
  end

  # def info(host_spec), do: epmd_list_names(host_spec)

  defp epmd_list_names(%SSH{} = host_spec) do
    with {:ok, local_port} <- SSH.tunnel_port_to_server(host_spec, 0, host_spec.epmd_port) do
      {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, local_port, [:inet])

      :gen_tcp.send(socket, [@int16_1, @epmd_names])
      |> case do
        :ok ->
          receive do
            {:tcp, socket, [_p0, _p1, _p2, _p3 | t]} ->
              services =
                receive_names(socket, t)
                |> scan_names()

              {:ok, %Info{services: services}}

            {:tcp_closed, _socket} ->
              {:error, :no_data}
          end

        _ ->
          {:error, :address}
      end
    end
  end

  defp receive_names(socket, acc) do
    receive do
      {:tcp, ^socket, data} ->
        receive_names(socket, acc ++ data)

      {:tcp_closed, ^socket} ->
        {:ok, acc}
    end
  end

  defp scan_names({:ok, response}) do
    response
    |> :erlang.list_to_binary()
    |> String.split("\n")
    |> Enum.filter(fn x -> x != "" end)
    |> Enum.map(&scan_name/1)
    |> Enum.filter(fn x -> x != nil end)
    |> :maps.from_list()
  end

  defp scan_name(info) do
    case String.split(info) do
      ["name", service_name, "at", "port", service_port] ->
        {:erlang.binary_to_atom(service_name, :utf8), :erlang.binary_to_integer(service_port)}

      _ ->
        nil
    end
  end
end
