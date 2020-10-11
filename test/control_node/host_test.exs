defmodule ControlNode.HostTest do
  use ExUnit.Case
  import ControlNode.TestUtils
  alias ControlNode.Host.SSH
  alias ControlNode.{Release, Registry, Host}

  setup do
    host_spec = ssh_fixture()
    release_spec = %Release.Spec{name: :service_app, base_path: "/app/service_app"}
    registry_spec = %Registry.Local{path: Path.join(File.cwd!(), "example")}

    :ok = Release.deploy(release_spec, host_spec, registry_spec, "0.1.0")
    ensure_started(host_spec, release_spec)

    on_exit(fn ->
      {:ok, %SSH.ExecStatus{exit_status: :success}} =
        SSH.exec(host_spec, "#{release_spec.base_path}/0.1.0/bin/#{release_spec.name} stop")
    end)

    %{host_spec: host_spec}
  end

  describe "info/1" do
    test "list epmd and release info for the host", %{host_spec: host_spec} do
      assert {:ok, %Host.Info{services: %{service_app: _port}}} = Host.info(host_spec)
    end
  end

  defp ensure_started(host_spec, release_spec) do
    assert_until(fn ->
      {:ok, %SSH.ExecStatus{exit_status: exit_status}} =
        SSH.exec(host_spec, "#{release_spec.base_path}/0.1.0/bin/#{release_spec.name} pid")

      exit_status == :success
    end)
  end
end
