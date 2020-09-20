defmodule ControlNode.Host.SSHTest do
  use ExUnit.Case
  alias ControlNode.Host.SSH

  setup do
    private_key_dir = with_fixture_path('host-vm/.ssh') |> :erlang.list_to_binary()
    # on CI the env var SSH_HOST is set to openssh-server to connect
    # to the service container running SSH server
    host = System.get_env("SSH_HOST", "localhost")

    ssh_config = %SSH{
      host: host,
      port: 2222,
      user: "linuxserver.io",
      private_key_dir: private_key_dir
    }

    %{ssh_config: ssh_config}
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

  defp with_fixture_path(path) do
    Path.join([File.cwd!(), "test/fixture", path]) |> to_char_list()
  end
end
