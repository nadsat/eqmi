defmodule Eqmi do
  @moduledoc """
  Documentation for `Eqmi`.
  """
  require Eqmi.Builder
  @sender_types %{0 => :control_point, 128 => :service}
  @service_types %{
    0 => :qmi_ctl,
    1 => :qmi_wds,
    2 => :qmi_dms,
    3 => :qmi_nas,
    4 => :qmi_qos,
    5 => :qmi_wms,
    6 => :qmi_pds,
    9 => :qmi_voice,
    10 => :qmi_cat,
    11 => :qmi_cat,
    12 => :qmi_pbm,
    14 => :qmi_cat
  }
  @message_types %{0 => :request, 2 => :response, 4 => :indication}

  def open_device(dev) do
    options = [:read, :write, :raw]
    File.open(dev, options)
  end

  def close_device(dev) do
    File.close(dev)
  end

  def get_sender_type(type_id) do
    @sender_types[type_id]
  end

  def get_service_type(svc_id) do
    @service_types[svc_id]
  end

  def get_message_type(msg_id) do
    @message_types[msg_id]
  end

  def message_type_id(msg_name) do
    @message_types
    |> get_id(msg_name)
  end

  def sender_type_id(msg_name) do
    @sender_types
    |> get_id(msg_name)
  end

  def service_type_id(msg_name) do
    @service_types
    |> get_id(msg_name)
  end

  defp get_id(types, name) do
    types
    |> Enum.find(fn {_key, val} -> val == name end)
    |> elem(0)
  end

  def qmux_message(header, payload) do
    if_type = <<1::little-unsigned-integer-size(8)>>

    [if_type, header, payload]
    |> :erlang.list_to_binary()
  end

  def hello(device) do
    # for command <- @ctl_msgs do
    #  IO.puts("ddddddddddddddddddddd")
    #  IO.inspect(command)
    #  IO.puts("ddddddddddddddddddddd")

    #  msg_id =
    #    command["id"]
    #    |> Eqmi.Builder.Utils.id_from_str()

    #  IO.inspect(msg_id)

    #  IO.inspect(command["id"])
    #  IO.inspect(command["type"])

    #  elements =
    #    Map.get(command, "output", %{})
    #    |> Enum.filter(fn x -> !Map.has_key?(x, "common-ref") end)
    #    |> Eqmi.Builder.Utils.transform_name()

    #  for out_params <- elements do
    #    IO.puts("TTTTTTTTTTTTTTTTTTTTTTTTTTTT")
    #    IO.inspect(out_params)
    #    IO.puts("----------------------------")
    #    IO.inspect(out_params["format"])
    #    IO.puts("----------------------------")
    #  end
    # end

    IO.puts("+++++++++++++++++")
    msg = IO.binread(device, 3)
    IO.puts("+++++++++++++++++")
    msg = process_message(msg, device)
    IO.inspect(msg)
    :pasturri
  end

  defp process_message({:error, reason}, _) do
    {:error, reason}
  end

  defp process_message(:eof, _) do
    {:error, :eof}
  end

  defp process_message(qmux, dev) do
    <<_version, content::binary>> = qmux
    IO.inspect(qmux)
    len = :binary.decode_unsigned(content, :little)
    msg = IO.binread(dev, len - 2)
    <<header::binary-size(3), rest::binary>> = msg
    payload = Eqmi.QmuxHeader.parse(header)
    process_service(payload, rest)
  end

  defp process_service(%{service_type: :qmi_ctl} = payload, messages) do
    IO.puts("sender_type [#{inspect(payload.sender_type)}]")
    IO.puts("client_id [#{inspect(payload.client_id)}]")
    Eqmi.CTL.process_qmux_sdu(messages, payload)
  end
end
