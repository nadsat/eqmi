defmodule Eqmi.Types do
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
    11 => :qmi_uim,
    12 => :qmi_pbm,
    14 => :qmi_cat,
    16 => :qmi_loc,
    17 => :qmi_sar,
    20 => :qmi_wda,
    226 => :qmi_oma,
    231 => :qmi_gms,
    232 => :qmi_gas
  }
  @message_types %{0 => :request, 2 => :response, 4 => :indication}

  def get_sender_atom(type_id) do
    @sender_types[type_id]
  end

  def get_service_atom(svc_id) do
    @service_types[svc_id]
  end

  def get_message_atom(msg_id) do
    @message_types[msg_id]
  end

  def message_id(msg_name) do
    @message_types
    |> get_id(msg_name)
  end

  def sender_id(msg_name) do
    @sender_types
    |> get_id(msg_name)
  end

  def service_id(msg_name) do
    @service_types
    |> get_id(msg_name)
  end

  defp get_id(types, name) do
    types
    |> Enum.find(fn {_key, val} -> val == name end)
    |> elem(0)
  end
end
