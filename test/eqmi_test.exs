defmodule EqmiTest do
  require Logger

  use ExUnit.Case
  @ctl_response <<1, 23, 0, 128, 0, 0, 1, 2, 34, 0, 12, 0, 2, 4, 0, 0, 0, 0, 0, 1, 2, 0, 1, 2>>
  @dms_response <<1, 146, 0, 128, 2, 2, 2, 1, 0, 32, 0, 134, 0, 2, 4, 0, 0, 0, 0, 0, 1, 14, 0,
                  128, 240, 250, 2, 0, 225, 245, 5, 4, 2, 3, 4, 5, 8, 16, 4, 0, 4, 0, 0, 0, 17, 8,
                  0, 3, 0, 0, 0, 0, 0, 0, 0, 18, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 19, 12, 0, 1, 1, 1,
                  1, 56, 0, 0, 0, 0, 0, 0, 0, 20, 2, 0, 1, 1, 21, 9, 0, 1, 56, 0, 0, 0, 0, 0, 0,
                  0, 22, 6, 0, 1, 1, 0, 0, 0, 0, 23, 5, 0, 1, 0, 0, 0, 0, 24, 1, 0, 1, 25, 9, 0,
                  1, 56, 0, 0, 0, 0, 0, 0, 0, 26, 13, 0, 1, 1, 1, 1, 56, 0, 0, 0, 0, 0, 0, 0, 0>>
  @release_response <<1, 23, 0, 128, 0, 0, 1, 3, 35, 0, 12, 0, 2, 4, 0, 0, 0, 0, 0, 1, 2, 0, 2,
                      1>>

  def qmi_device() do
    System.get_env("QMI_DEVICE")
  end

  def simulator_device() do
    System.get_env("SIM_DEVICE")
  end

  def common_setup() do
    if is_nil(qmi_device()) || is_nil(simulator_device()) do
      msg = "Please define QMI_DEVICE and SIM_DEVICE.\n\n"
      flunk(msg)
    end

    options = [:read, :write, :raw]

    case File.open(simulator_device(), options) do
      {:ok, device} ->
        {:ok, sim_device: device}

      {:error, reason} ->
        flunk(reason)
    end
  end

  def mock_read(device, size, msg) do
    {f, t, ref} = device
    dev = {f, t, %{ref | owner: self()}}
    _data = IO.binread(dev, size)
    IO.binwrite(dev, msg)
  end

  setup do
    common_setup()
  end

  test "send message", %{sim_device: device} do
    {:ok, dev} = Eqmi.start_link(qmi_device())
    spawn(fn -> mock_read(device, 16, @ctl_response) end)
    client = Eqmi.client(dev, :qmi_dms)
    spawn(fn -> mock_read(device, 12, @dms_response) end)
    msg = Eqmi.DMS.request(:get_capabilities, [])
    Eqmi.send_message(dev, client, [msg])
    assert_receive({:qmux, _})

    spawn(fn -> mock_read(device, 4, @release_response) end)
    res = Eqmi.release_client(dev, client)

    assert :ok = res
  end
end
