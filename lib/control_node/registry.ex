defmodule ControlNode.Registry do
  defmodule Local do
    @type t :: %__MODULE__{path: String.t()}
    defstruct path: nil
  end

  def fetch(%Local{} = registry_spec, application, version) do
    Path.join(registry_spec.path, "#{application}-#{version}.tar.gz")
    |> File.read()
  end
end
