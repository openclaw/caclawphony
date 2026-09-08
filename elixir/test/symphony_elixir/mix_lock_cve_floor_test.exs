defmodule SymphonyElixir.MixLockCveFloorTest do
  use ExUnit.Case, async: true

  @lock_path Path.expand("../../mix.lock", __DIR__)

  @floors %{
    "bandit" => Version.parse!("1.11.1"),
    "phoenix" => Version.parse!("1.8.9"),
    "plug" => Version.parse!("1.19.2")
  }

  test "mix.lock pins Bandit, Phoenix, and Plug past HIGH CVE floors" do
    lock = File.read!(@lock_path)

    Enum.each(@floors, fn {name, floor} ->
      version = lock_hex_version!(lock, name)

      assert Version.compare(version, floor) in [:eq, :gt],
             "#{name} #{version} is below CVE floor #{floor}"
    end)
  end

  defp lock_hex_version!(lock, name) do
    pattern = ~r/"#{Regex.escape(name)}": \{:hex, :#{Regex.escape(name)}, "([^"]+)"/

    case Regex.run(pattern, lock) do
      [_, version] -> Version.parse!(version)
      nil -> flunk("expected #{name} hex entry in mix.lock")
    end
  end
end
