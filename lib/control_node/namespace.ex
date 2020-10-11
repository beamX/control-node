defmodule ControlNode.Namespace do
  alias ControlNode.{Host, Registry}

  defmodule Spec do
    @type t :: %__MODULE__{
            tag: atom,
            hosts: [Host.SSH.t()],
            registry_spec: Registry.Local.t(),
            deployment_type: atom,
            release_cookie: atom
          }
    defstruct tag: nil,
              hosts: nil,
              registry_spec: nil,
              deployment_type: :incremental_replace,
              release_management: :replica,
              release_cookie: nil
  end
end
