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
  @nas_response <<2, 1, 0, 67, 0, 190, 0, 2, 4, 0, 0, 0, 0, 0, 19, 29, 0, 1, 55, 240, 32, 50, 5,
                  34, 94, 17, 0, 228, 12, 11, 0, 7, 6, 4, 56, 1, 11, 0, 116, 255, 177, 251, 4,
                  253, 15, 0, 20, 14, 0, 1, 2, 232, 3, 0, 8, 4, 0, 144, 36, 0, 8, 3, 0, 21, 79, 0,
                  1, 1, 0, 0, 6, 255, 8, 0, 0, 1, 0, 0, 128, 248, 0, 0, 175, 2, 1, 0, 0, 128, 248,
                  0, 0, 176, 2, 1, 0, 0, 128, 248, 0, 0, 177, 2, 1, 0, 0, 128, 248, 0, 0, 178, 2,
                  1, 0, 0, 128, 248, 0, 0, 179, 2, 1, 0, 0, 128, 248, 0, 0, 180, 2, 1, 0, 0, 128,
                  248, 0, 0, 181, 2, 1, 0, 0, 128, 248, 0, 0, 22, 18, 0, 1, 2, 6, 17, 2, 0, 0, 0,
                  0, 0, 31, 17, 2, 0, 0, 0, 0, 0, 30, 4, 0, 255, 255, 255, 255, 38, 2, 0, 70, 0,
                  39, 4, 0, 228, 12, 0, 0, 40, 9, 0, 2, 232, 3, 0, 0, 144, 36, 0, 0>>
  @wms_indication <<4, 1, 0, 70, 0, 18, 0, 1, 15, 0, 49, 52, 53, 11, 43, 53, 54, 57, 49, 54, 48,
                    48, 50, 48, 50>>
  @sync_response <<1, 18, 0, 128, 0, 0, 1, 1, 39, 0, 7, 0, 2, 4, 0, 0, 0, 0, 0>>

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

  def mock_read(device, msgs) do
    {f, t, ref} = device
    dev = {f, t, %{ref | owner: self()}}

    msgs
    |> Enum.each(fn {size, msg} ->
      IO.binread(dev, size)
      IO.binwrite(dev, msg)
    end)
  end

  setup do
    common_setup()
  end

  test "send message", %{sim_device: device} do
    msgs = [{12, @sync_response}, {16, @ctl_response}]
    spawn(fn -> mock_read(device, msgs) end)
    {:ok, dev} = Eqmi.device(qmi_device())
    client = Eqmi.client(dev, :qmi_dms)
    spawn(fn -> mock_read(device, [{12, @dms_response}]) end)
    msg = Eqmi.DMS.request(:get_capabilities, [])
    Eqmi.send_message(dev, client, [msg])
    assert_receive({:qmux, _})

    spawn(fn -> mock_read(device, [{4, @release_response}]) end)
    res = Eqmi.release_client(dev, client)

    assert :ok = res
  end

  test "nas response", %{sim_device: _device} do
    payload = %{client_id: 5, sender_type: :service, service_type: :qmi_nas}
    msg = Eqmi.NAS.process_qmux_sdu(@nas_response, payload)
    [h | _] = msg.messages
    assert h.msg_id == 67
  end

  test "wms indication", %{sim_device: _device} do
    payload = %{client_id: 1, sender_type: :service, service_type: :qmi_wms}
    msg = Eqmi.WMS.process_qmux_sdu(@wms_indication, payload)
    [h | _] = msg.messages
    assert h.msg_id == 70
  end

  test "nas event report request", %{sim_device: _device} do
    expected = <<2, 0, 7, 0, 16, 4, 0, 1, 2, 254, 2>>

    assert Eqmi.NAS.request(:set_event_report, [
             {:signal_strength_indicator, [{:report, 1}, {:thresholds, [-2, 2]}]}
           ]) == expected
  end
end
