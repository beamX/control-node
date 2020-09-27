defmodule ControlNode.ReleaseTest do
  use ExUnit.Case
  import ControlNode.TestUtils
  alias ControlNode.Host.SSH
  alias ControlNode.{Release, Registry}

  setup do
    {:ok, ssh_config} = ssh_fixture()
    %{ssh_config: ssh_config}
  end

  describe "deploy/4" do
    setup do
      release_spec = %Release.Spec{
        name: :service_app,
        base_path: "/app/service_app",
        start_strategy: :restart
      }

      registry_spec = %Registry.Local{path: Path.join(File.cwd!(), "example")}

      %{release_spec: release_spec, registry_spec: registry_spec}
    end

    test "uploads tar and start release", %{
      release_spec: release_spec,
      ssh_config: ssh_config,
      registry_spec: registry_spec
    } do
      :ok = Release.deploy(release_spec, ssh_config, registry_spec, "0.1.0")

      assert_until(fn ->
        {:ok, %SSH.ExecStatus{exit_status: exit_status}} =
          SSH.exec(ssh_config, "#{release_spec.base_path}/0.1.0/bin/#{release_spec.name} pid")

        exit_status == :success
      end)

      {:ok, %SSH.ExecStatus{exit_status: :success}} =
        SSH.exec(ssh_config, "#{release_spec.base_path}/0.1.0/bin/#{release_spec.name} stop")
    end
  end
end
