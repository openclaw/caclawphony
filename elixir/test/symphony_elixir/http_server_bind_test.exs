defmodule SymphonyElixir.HttpServerBindTest do
  use SymphonyElixir.TestSupport

  test "allows loopback binds for 127.0.0.1 and localhost" do
    assert {:ok, _pid} = start_supervised({HttpServer, [host: "127.0.0.1", port: 0]})
    assert is_integer(HttpServer.bound_port())
    assert :ok = stop_supervised(HttpServer)

    assert {:ok, _pid} = start_supervised({HttpServer, [host: "localhost", port: 0]})
    assert is_integer(HttpServer.bound_port())
  end

  test "rejects 0.0.0.0 without an explicit opt-in" do
    assert {:error, {:non_loopback_bind, "0.0.0.0"}} =
             HttpServer.start_link(host: "0.0.0.0", port: 0)
  end

  test "allows 0.0.0.0 when allow_non_loopback is set" do
    assert {:ok, _pid} =
             start_supervised({HttpServer, [host: "0.0.0.0", port: 0, allow_non_loopback: true]})

    assert is_integer(HttpServer.bound_port())
  end
end
