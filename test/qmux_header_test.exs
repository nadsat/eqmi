defmodule EqmiQmuxHeaderTest do
  use ExUnit.Case
  @payload <<128, 0, 0>>
  test "response message" do
    header = %{
      sender_type: :service,
      client_id: 0,
      service_type: :qmi_ctl
    }

    expected = header
    assert expected == Eqmi.QmuxHeader.parse(@payload)
  end
end
