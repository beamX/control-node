defmodule ControlNode.Host do
  alias ControlNode.Host.SSH

  defmodule Info do
    @type t :: %__MODULE__{epmd_port: integer, services: map}
    defstruct epmd_port: nil, services: %{}
  end

  def upload_file(%SSH{} = host_spec, path, file), do: SSH.upload_file(host_spec, path, file)

  def extract_tar(%SSH{} = host_spec, release_path, release_dir) do
    with {:ok, %SSH.ExecStatus{exit_code: 0}} <-
           SSH.exec(host_spec, "tar -xf #{release_path} -C #{release_dir}") do
      :ok
    end
  end

  def init_release(%SSH{} = host_spec, init_file, command) do
    with {:ok, %SSH.ExecStatus{exit_code: 0}} <-
           SSH.exec(host_spec, "nohup #{init_file} #{command} &", true) do
      :ok
    end
  end

  @spec info(SSH.t(), binary) ::
          {:ok, Info.t()} | {:error, :epmd_not_running | :unexpected_return_value}
  def info(%SSH{} = host_spec, epmd_path) do
    with {:ok, %SSH.ExecStatus{exit_code: 0, message: message}} <-
           SSH.exec(host_spec, "#{epmd_path} -names", true) do
      extract_info(message)
    end
  end

  defp extract_info(["epmd: up and running on port" <> _ = message]) do
    info =
      message
      |> String.split("\n")
      |> Enum.filter(fn i -> i != "" end)
      |> Enum.reduce(%Info{}, fn m, acc_info -> do_extract_info(m, acc_info) end)

    {:ok, info}
  end

  defp extract_info(["epmd: Cannot connect to local epmd\n"]), do: {:error, :epmd_not_running}
  defp extract_info(_), do: {:error, :unexpected_return_value}

  defp do_extract_info("epmd: up and running on port" <> msg, info) do
    epmd_port =
      msg
      |> String.trim()
      |> String.split()
      |> List.first()
      |> String.to_integer()

    %{info | epmd_port: epmd_port}
  end

  defp do_extract_info("name " <> _ = msg, %Info{services: services} = info) do
    msg
    |> String.trim()
    |> String.split()
    |> case do
      ["name", service_name, "at", "port", service_port] ->
        service_name = String.to_atom(service_name)
        service_port = String.to_integer(service_port)

        %{info | services: Map.put(services, service_name, service_port)}
    end
  end
end
