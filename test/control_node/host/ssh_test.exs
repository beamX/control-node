defmodule ControlNode.Host.SSHTest do
  use ExUnit.Case
  require Logger
  import ExUnit.CaptureLog
  import ControlNode.TestUtils
  alias ControlNode.Host.SSH

  setup do
    %{ssh_config: ssh_fixture()}
  end

  describe "upload_file/2" do
    setup do
      base_path = "/tmp/control-node"

      on_exit(fn -> System.cmd("rm", ["-rf", base_path]) end)
      %{base_path: base_path}
    end

    test "connects and uploads files to remote ssh server", %{
      ssh_config: ssh_config,
      base_path: base_path
    } do
      application_path = Path.join(base_path, "/namespace/application.txt")

      SSH.upload_file(ssh_config, application_path, "hello world")

      assert {:ok, "hello world"} = File.read(application_path)
    end
  end

  describe "exec/3" do
    setup do
      on_exit(fn -> System.cmd("rm", ["-rf", "/tmp/config.txt"]) end)
    end

    # NOTE: in order to have ENV vars the ssh server config has to be updated
    # so we just assert that the correct command was sent to the server
    test "run list of commands on remote SSH server", %{ssh_config: ssh_config} do
      ssh_config = %SSH{ssh_config | env_vars: %{"ENV_TEST" => "hello world"}}

      assert capture_log(fn ->
        assert {:ok, %SSH.ExecStatus{exit_status: :success}} = SSH.exec(ssh_config, ["echo $ENV_TEST > /tmp/config.txt"])
      end) =~ "ENV_TEST='hello world' echo $ENV_TEST > /tmp/config.txt"
    end

    test "runs script on remote SSH server", %{ssh_config: ssh_config} do
      script = """
      #!/bin/sh

      export ENV_TEST="hello world"
      echo $ENV_TEST > /tmp/config.txt
      """

      assert {:ok, %SSH.ExecStatus{exit_status: :success}} = SSH.exec(ssh_config, script)
      assert {:ok, "hello world\n"} = File.read("/tmp/config.txt")
    end

    test "return error when unknown command is provided", %{ssh_config: ssh_config} do
      script = """
      #!/bin/sh

      unknown /tmp
      """

      {:ok, %SSH.ExecStatus{exit_status: :failure}} = SSH.exec(ssh_config, script)
    end
  end

  describe "tunnel_port_to_server/3" do
    setup %{ssh_config: ssh_config} do
      ssh_config = SSH.connect(ssh_config)
      on_exit(fn -> SSH.disconnect(ssh_config) end)

      %{ssh_config: ssh_config}
    end

    test "successfully forwards packets from local port to remote port", %{ssh_config: ssh_config} do
      pid = spawn(fn -> SSH.exec(ssh_config, ["nc -l -p 8787 > /tmp/tunnel_output.txt &"]) end)
      ensure_nc_server_up(ssh_config)

      {:ok, local_port} = SSH.tunnel_port_to_server(ssh_config, 0, 8787)
      tcp_local_send('hello world', local_port)

      assert_until(fn ->
        {:ok, "hello world"} == File.read("/tmp/tunnel_output.txt")
      end)

      # clean up
      Process.exit(pid, :kill)
      SSH.exec(ssh_config, ["pkill nc"])
      File.rm_rf!("/tmp/tunnel_output.txt")
    end

    test "returns error if ssh connection is not passed with %SSH{}", %{ssh_config: ssh_config} do
      assert {:error, :not_connected} ==
               SSH.tunnel_port_to_server(%{ssh_config | conn: nil}, 8989)
    end
  end

  defp tcp_local_send(message, port) do
    {:ok, socket} = :gen_tcp.connect('127.0.0.1', port, [:binary, {:packet, 0}])
    :ok = :gen_tcp.send(socket, message)
    :ok = :gen_tcp.close(socket)
  end

  defp ensure_nc_server_up(ssh_config) do
    case SSH.exec(ssh_config, ["pgrep nc"]) do
      {:ok, %{exit_status: :success, message: []}} ->
        :timer.sleep(500)
        ensure_nc_server_up(ssh_config)

      {:ok, _} ->
        :ok
    end
  end
end
