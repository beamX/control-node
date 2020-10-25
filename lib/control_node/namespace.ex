defmodule ControlNode.Namespace do
  @moduledoc false

  alias ControlNode.{Host, Registry}

  defmodule Spec do
    @typedoc """
    `Namespace.Spec` defines a spec with the following attributes,

    * `:tag` : Tag for the namespace (eg: `:testing`)
    * `:hosts` : List of hosts where the release will be deployed.
    * `:registry_spec` : Defines the registry from where there release tar will
      be retireved for rolling out deployment in this namepsace
    * `:release_cookie` : Release cookie used by the release in this given
      namespace. This cookie will be used by control node to connect to the
      release nodes
    """

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
