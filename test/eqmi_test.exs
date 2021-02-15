defmodule EqmiTest do
  use ExUnit.Case
  @cts_response <<1, 23, 0, 128, 0, 0, 1, 2, 34, 0, 12, 0, 2, 4, 0, 0, 0, 0, 0, 1, 2, 0, 1, 20>>
  @dms_response <<1, 146, 0, 128, 2, 2, 2, 1, 0, 32, 0, 134, 0, 2, 4, 0, 0, 0, 0, 0, 1, 14, 0,
                  128, 240, 250, 2, 0, 225, 245, 5, 4, 2, 3, 4, 5, 8, 16, 4, 0, 4, 0, 0, 0, 17, 8,
                  0, 3, 0, 0, 0, 0, 0, 0, 0, 18, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 19, 12, 0, 1, 1, 1,
                  1, 56, 0, 0, 0, 0, 0, 0, 0, 20, 2, 0, 1, 1, 21, 9, 0, 1, 56, 0, 0, 0, 0, 0, 0,
                  0, 22, 6, 0, 1, 1, 0, 0, 0, 0, 23, 5, 0, 1, 0, 0, 0, 0, 24, 1, 0, 1, 25, 9, 0,
                  1, 56, 0, 0, 0, 0, 0, 0, 0, 26, 13, 0, 1, 1, 1, 1, 56, 0, 0, 0, 0, 0, 0, 0, 0>>

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

  setup do
    common_setup()
  end

  test "greets the world", %{sim_device: device} do
    {:ok, dev} = Eqmi.open(qmi_device())
    IO.binwrite(device, @cts_response)
    assert Eqmi.hello(dev) == :pasturri
    Eqmi.close(dev)
  end

  test "dms response", %{sim_device: device} do
    {:ok, dev} = Eqmi.open(qmi_device())
    IO.binwrite(device, @dms_response)
    assert Eqmi.hello(dev) == :pasturri
    Eqmi.close(dev)
  end

  test "create message", %{sim_device: _device} do
    msg = Eqmi.CTL.request(:allocate_cid, [{:service, 1}])
    payload = Eqmi.CTL.qmux_sdu(:request, 2, [msg])
    header = Eqmi.QmuxHeader.new(:control_point, 0, :qmi_ctl, byte_size(payload))
    qmux_msg = Eqmi.qmux_message(header, payload)
    assert qmux_msg == <<1, 15, 0, 0, 0, 0, 0, 2, 34, 0, 4, 0, 1, 1, 0, 1>>
  end
end
