defmodule ControlNode.Host.SSHTest do
  use ExUnit.Case
  alias ControlNode.Host.SSH

  describe "upload_file/2" do
    setup do
      base_path = "/tmp/control-node"

      on_exit(fn -> System.cmd("rm", ["-rf", base_path]) end)
      %{base_path: base_path}
    end

    test "Connects and uploads files to ssh server", %{base_path: base_path} do
      application_path = Path.join(base_path, "/namespace/application.txt")
      private_key_dir = with_fixture_path('host-vm/.ssh') |> :erlang.list_to_binary()

      %SSH{
        host: "openssh-server",
        port: 2222,
        user: "linuxserver.io",
        private_key_dir: private_key_dir
      }
      |> SSH.upload_file(application_path, "hello world")

      assert {:ok, "hello world"} = File.read(application_path)
    end
  end

  defp with_fixture_path(path) do
    Path.join([File.cwd!(), "test/fixture", path]) |> to_char_list()
  end
end
