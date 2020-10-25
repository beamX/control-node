defmodule ControlNode.Epmd do
  # ref: https://www.erlang-solutions.com/blog/erlang-and-elixir-distribution-without-epmd.html

  @moduledoc false

  def start_link, do: :ignore

  # As of Erlang/OTP 19.1, register_node/3 is used instead of
  # register_node/2, passing along the address family, 'inet_tcp' or
  # 'inet6_tcp'.  This makes no difference for our purposes.
  def register_node(name, port, _family) do
    register_node(name, port)
  end

  def register_node(_name, _port) do
    # This is where we would connect to epmd and tell it which port
    # we're listening on, but since we're epmd-less, we don't do that.

    # Need to return a "creation" number between 1 and 3.
    creation = :rand.uniform(3)
    {:ok, creation}
  end

  def address_please(name, host, _address_family) do
    key = {"#{name}", "#{host}"}
    [{_, port}] = :ets.lookup(:control_node_epmd, key)
    # The distribution protocol version number has been 5 ever since
    # Erlang/OTP R6.
    version = 5
    {:ok, {127, 0, 0, 1}, port, version}
  end

  def register_release(name, host, port) do
    key = {"#{name}", "#{host}"}
    :ets.insert(:control_node_epmd, {key, port})
  end

  # Should not be invoked because `address_please/3` already returns the port
  def port_please(_name, _ip) do
    raise RuntimeError, "unexpected call to #{__MODULE__}.port_please/2"
    # The distribution protocol version number has been 5 ever since
    # Erlang/OTP R6.
    # version = 5
    # {:port, port, version}
  end

  def names(_hostname) do
    # Since we don't have epmd, we don't really know what other nodes
    # there are.
    {:error, :address}
  end
end
