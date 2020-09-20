defmodule ControlNode.Host.SSH do
  @enforce_keys [:host, :port, :user, :private_key_dir]
  defstruct host: nil, port: 22, user: nil, private_key_dir: nil

  @type t :: %__MODULE__{host: binary, port: integer, user: binary, private_key_dir: binary}
  @timeout :infinity

  defmodule ExecStatus do
    @type t :: %__MODULE__{exit_status: atom, exit_code: integer, message: list}
    defstruct exit_status: nil, exit_code: nil, message: []
  end

  @doc """
  Creates SSH connection to remote host
  """
  @spec connect_host(t) :: {:ok, :ssh.connection_ref()} | {:error, term()}
  def connect_host(ssh_config) do
    ssh_options = [
      {:user, to_list(ssh_config.user)},
      {:user_dir, to_list(ssh_config.private_key_dir)},
      {:user_interaction, false},
      {:silently_accept_hosts, true},
      {:auth_methods, 'publickey'}
    ]

    ssh_config.host
    |> to_list()
    |> :ssh.connect(ssh_config.port, ssh_options)
  end

  @doc """
  Execute a given list of command or a bash script on the host vm
  """
  @spec exec(t, list | binary) :: ExecStatus.t() | :failure | {:error, any}
  def exec(ssh_config, commands) when is_list(commands) do
    exec(ssh_config, Enum.join(commands, "; "))
  end

  def exec(ssh_config, script) when is_binary(script) do
    with {:ok, conn} <- connect_host(ssh_config),
         {:ok, channel_id} <- :ssh_connection.session_channel(conn, @timeout),
         :success <- :ssh_connection.exec(conn, channel_id, to_list(script), @timeout) do
      status = get_exec_status(conn, %ExecStatus{})

      :ssh_connection.close(conn, channel_id)
      :ssh.close(conn)

      {:ok, status}
    end
  end

  defp get_exec_status(conn, status) do
    receive do
      {:ssh_cm, ^conn, {:closed, _channel_id}} ->
        %{status | message: Enum.reverse(status.message)}

      {:ssh_cm, ^conn, {:data, _channel_id, 0, success_msg}} ->
        get_exec_status(conn, %{status | message: [success_msg | status.message]})

      {:ssh_cm, ^conn, {:data, _channel_id, 1, error_msg}} ->
        get_exec_status(conn, %{status | message: [error_msg | status.message]})

      {:ssh_cm, ^conn, {:exit_status, _channel_id, 0}} ->
        get_exec_status(conn, %{status | exit_status: :success, exit_code: 0})

      {:ssh_cm, ^conn, {:exit_status, _channel_id, status_code}} ->
        get_exec_status(conn, %{status | exit_status: :failure, exit_code: status_code})

      {:ssh_cm, ^conn, {:eof, 0}} ->
        get_exec_status(conn, status)
    end
  end

  @doc """
  Uploads `tar_file` to the `host` server via SSH and stores it at `file_path`
  on the remote server.

  `file_path` should be absolute path on the remote server

  ## Example

  iex> ssh_config = %SSH{host: "remote-host.com", port: 22, user: "username", private_key_dir: "/home/local_user/.ssh"}
  iex> ControlNode.Host.SSH.upload_file(ssh_config, "/opt/remote/server/directory", "file_contexts_binary")
  :ok
  """
  @spec upload_file(t, binary, binary) :: :ok
  def upload_file(%__MODULE__{port: port} = ssh_config, file_path, tar_file)
      when is_integer(port) do
    with :ok <- is_absolute_path?(file_path) do
      do_upload_file(ssh_config, file_path, tar_file)

      :ok
    end
  end

  defp do_upload_file(ssh_config, file_path, tar_file) do
    filename = :binary.bin_to_list(file_path)
    path = Path.dirname(file_path)

    # ensure path exists
    with {:ok, conn} <- connect_host(ssh_config),
         {:ok, channel_pid} = :ssh_sftp.start_channel(conn) do
      ^path = do_make_path(channel_pid, path)
      :ssh.close(conn)
    end

    # upload file
    with {:ok, conn} <- connect_host(ssh_config),
         {:ok, channel_pid} = :ssh_sftp.start_channel(conn) do
      :ok = :ssh_sftp.write_file(channel_pid, filename, tar_file)
      :ssh.close(conn)
    end
  end

  defp is_absolute_path?(path) do
    case Path.type(path) do
      :absolute -> :ok
      _ -> {:error, :absolute_path_not_provided}
    end
  end

  defp do_make_path(channel_pid, path) do
    Path.relative_to(path, "/")
    |> Path.split()
    |> Enum.reduce("/", fn dir, base_path ->
      new_base_path = Path.join(base_path, dir)

      # ensure directory path uptil now is created
      :ssh_sftp.opendir(channel_pid, to_list(new_base_path))
      |> case do
        {:ok, _} ->
          :ok

        {:error, :no_such_file} ->
          :ok = :ssh_sftp.make_dir(channel_pid, to_list(new_base_path))
      end

      new_base_path
    end)
  end

  defp to_list(bin), do: :binary.bin_to_list(bin)
end
