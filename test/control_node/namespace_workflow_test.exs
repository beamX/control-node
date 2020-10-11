defmodule ControlNode.NamespaceWorkflowTest do
  use ExUnit.Case
  import ControlNode.TestUtils
  alias ControlNode.{Release, Registry, Namespace}

  defmodule ServiceApp do
    use ControlNode.Release,
      spec: %Release.Spec{name: :service_app, base_path: "/app/service_app"}
  end

  setup do
    registry_spec = %Registry.Local{path: Path.join(File.cwd!(), "example")}

    namespace_spec = %Namespace.Spec{
      tag: :testing,
      hosts: [ssh_fixture()],
      registry_spec: registry_spec,
      deployment_type: :incremental_replace,
      release_cookie: :"YFWZXAOJGTABHNGIT6KVAC2X6TEHA6WCIRDKSLFD6JZWRC4YHMMA===="
    }

    %{namespace_spec: namespace_spec}
  end

  describe "ServiceApp.start_link/1" do
    setup %{namespace_spec: namespace_spec} do
      {:ok, _pid} = ServiceApp.start_link(namespace_spec)
      :ok
    end

    test "transitions to [state: :manage] when release is not running" do
      assert_until(fn ->
        {:manage, _} = :sys.get_state(:service_app_testing)
      end)
    end
  end
end
