defmodule EqmiTest do
  use ExUnit.Case
  @cts_response <<1, 23, 0, 128, 0, 0, 1, 2, 34, 0, 12, 0, 2, 4, 0, 0, 0, 0, 0, 1, 2, 0, 1, 20>>

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
    {:ok, dev} = Eqmi.open_device(qmi_device())
    IO.binwrite(device, @cts_response)
    assert Eqmi.hello(dev) == :pasturri
    Eqmi.close_device(dev)
  end

  test "create message", %{sim_device: _device} do
    msg = Eqmi.CTL.request(:allocate_cid, [{:service, 1}])
    payload = Eqmi.CTL.qmux_sdu(:request, 2, [msg])
    IO.puts("testi ......................")
    header = Eqmi.QmuxHeader.new(:control_point, 0, :qmi_ctl, byte_size(payload))
    qmux_msg = Eqmi.qmux_message(header, payload)
    assert qmux_msg == <<1, 15, 0, 0, 0, 0, 0, 2, 34, 0, 4, 0, 1, 1, 0, 1>>
  end
end
