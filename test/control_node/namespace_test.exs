defmodule ControlNode.NamespaceTest do
  use ExUnit.Case
  import ControlNode.Factory
  alias ControlNode.Namespace

  @moduletag capture_log: true
  @supervisor ControlNode.ReleaseSupervisor

  defmodule TestRelease do
    use GenServer

    def release_name(), do: :example_release

    def start_link(ns_spec, host_spec) do
      GenServer.start_link(__MODULE__, [ns_spec, host_spec])
    end

    @impl true
    def init(args), do: {:ok, args}
  end

  setup do
    host_spec1 = build(:host_spec, host: "localhost1")
    host_spec2 = build(:host_spec, host: "localhost2")
    namespace_spec = build(:namespace_spec, hosts: [host_spec1, host_spec2])

    on_exit(fn ->
      DynamicSupervisor.which_children(@supervisor)
      |> Enum.map(fn {:undefined, pid, :worker, [TestRelease]} ->
        DynamicSupervisor.terminate_child(@supervisor, pid)
      end)
    end)

    %{namespace_spec: namespace_spec}
  end

  test "starts release process for all hosts", %{namespace_spec: namespace_spec} do
    {:ok, _pid} = Namespace.start_link(namespace_spec, TestRelease)
    :timer.sleep(100)

    assert %{active: 2, specs: 2, supervisors: 0, workers: 2} =
             DynamicSupervisor.count_children(@supervisor)
  end
end
