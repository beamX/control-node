defmodule ControlNode.Inet do
  @moduledoc false

  # Configure lookup priority for resolving names
  # https://erlang.org/doc/apps/erts/inet_cfg.html
  def configure_lookup do
    :inet_db.set_lookup([:file, :native])
  end

  # First key is `hosts` so first element is assumed to have the host list
  # ref: https://github.com/erlang/otp/blob/master/lib/kernel/src/inet_db.erl#L315
  def add_alias_for_localhost(name) do
    [hosts | _] = :inet.get_rc()
    names = find_names_for_localhost(hosts)
    :inet_db.add_host({127, 0, 0, 1}, [to_list(name) | names])
  end

  defp find_names_for_localhost([{:host, {127, 0, 0, 1}, names} | _t]) do
    names
  end

  defp find_names_for_localhost([]), do: []

  defp find_names_for_localhost([_h | t]), do: find_names_for_localhost(t)

  # Incase the host list doesn't exist in get_rc
  defp find_names_for_localhost(_), do: []

  defp to_list(b), do: :binary.bin_to_list(b)
end
