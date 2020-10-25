defmodule ControlNode.Registry do
  defmodule Local do
    @typedoc """
    `Registry.Spec` defines the registry where release tar will be stored on
    local host

    * `:path` : base path under which all release tars will be stored
    """

    @type t :: %__MODULE__{path: String.t()}
    defstruct path: nil
  end

  @doc """
  Retrieves application release tar file stored in the filesystem
  """
  def fetch(%Local{} = registry_spec, application, version) do
    Path.join(registry_spec.path, "#{application}-#{version}.tar.gz")
    |> File.read()
  end

  @doc """
  Stores application release tar file in the filesystem
  """
  def store(%Local{} = registry_spec, application, version, file_data) do
    Path.join(registry_spec.path, "#{application}-#{version}.tar.gz")
    |> File.write(file_data)
  end
end
