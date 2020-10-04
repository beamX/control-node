defmodule ControlNode.Host.SSH do
  @enforce_keys [:host, :port, :user, :private_key_dir]
  defstruct host: nil, port: 22, user: nil, private_key_dir: nil, conn: nil, hostname: nil

  @type t :: %__MODULE__{
          host: binary,
          port: integer,
          user: binary,
          private_key_dir: binary,
          conn: :ssh.connection_ref(),
          hostname: binary
        }
  @timeout :infinity

  defmodule ExecStatus do
    @type t :: %__MODULE__{exit_status: atom, exit_code: integer, message: list}
    defstruct exit_status: nil, exit_code: nil, message: []
  end

  @spec connect(t) :: t
  def connect(ssh_spec) do
    with {:ok, connection_ref} <- connect_host(ssh_spec) do
      %{ssh_spec | conn: connection_ref}
    end
  end

  @spec connect_host(t) :: {:ok, :ssh.connection_ref()} | {:error, term()}
  defp connect_host(ssh_config) do
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

  def tunnel_port_to_server(ssh_config, port) do
    with {:ok, conn} <- connect_host(ssh_config) do
      :ssh.tcpip_tunnel_to_server(conn, '127.0.0.1', port, '127.0.0.1', port)
    end
  end

  @doc """
  Execute a given list of command or a bash script on the host vm

  `skip_eof` : For commands which start long running processes `skip_eof` should
  be set to `true`. This enable `exec` to return `ExecStatus` while the command
  is left running on host.
  """
  @spec exec(t, list | binary) :: {:ok, ExecStatus.t()} | :failure | {:error, any}
  def exec(ssh_config, commands, skip_eof \\ false) do
    do_exec(ssh_config, commands, skip_eof)
  end

  defp do_exec(ssh_config, commands, skip_eof) when is_list(commands) do
    do_exec(ssh_config, Enum.join(commands, "; "), skip_eof)
  end

  defp do_exec(ssh_config, script, skip_eof) when is_binary(script) do
    with {:ok, conn} <- connect_host(ssh_config),
         {:ok, channel_id} <- :ssh_connection.session_channel(conn, @timeout),
         :success <- :ssh_connection.exec(conn, channel_id, to_list(script), @timeout) do
      status = get_exec_status(conn, %ExecStatus{}, skip_eof)

      :ssh_connection.close(conn, channel_id)
      :ssh.close(conn)

      {:ok, status}
    end
  end

  defp get_exec_status(conn, status, skip_eof) do
    receive do
      {:ssh_cm, ^conn, {:closed, _channel_id}} ->
        %{status | message: Enum.reverse(status.message)}

      {:ssh_cm, ^conn, {:data, _channel_id, 0, success_msg}} ->
        get_exec_status(conn, %{status | message: [success_msg | status.message]}, skip_eof)

      {:ssh_cm, ^conn, {:data, _channel_id, 1, error_msg}} ->
        get_exec_status(conn, %{status | message: [error_msg | status.message]}, skip_eof)

      {:ssh_cm, ^conn, {:exit_status, _channel_id, 0}} ->
        if skip_eof do
          %{status | exit_status: :success, exit_code: 0}
        else
          get_exec_status(conn, %{status | exit_status: :success, exit_code: 0}, skip_eof)
        end

      {:ssh_cm, ^conn, {:exit_status, _channel_id, status_code}} ->
        get_exec_status(conn, %{status | exit_status: :failure, exit_code: status_code}, skip_eof)

      {:ssh_cm, ^conn, {:eof, _channel_id}} ->
        get_exec_status(conn, status, skip_eof)
    end
  end

  @doc """
  Uploads `tar_file` to the `host` server via SSH and stores it at `file_path`
  on the remote server.

  `file_path` should be absolute path on the remote server.
  `file_path` is created recursively in case it doesn't exist.

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
