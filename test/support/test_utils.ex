defmodule ControlNode.TestUtils do
  require ExUnit.Assertions
  alias ControlNode.Host.SSH

  def ssh_fixture do
    private_key_dir = with_fixture_path('host-vm/.ssh') |> :erlang.list_to_binary()
    # on CI the env var SSH_HOST is set to openssh-server to connect
    # to the service container running SSH server
    host = System.get_env("SSH_HOST", "localhost")

    %SSH{
      host: host,
      port: 2222,
      user: "linuxserver.io",
      private_key_dir: private_key_dir
    }
  end

  defp with_fixture_path(path) do
    Path.join([File.cwd!(), "test/fixture", path]) |> to_char_list()
  end

  def assert_until(fun) do
    ExUnit.Assertions.assert(
      Enum.any?(0..20, fn _i ->
        :timer.sleep(100)
        fun.()
      end)
    )
  end
end
