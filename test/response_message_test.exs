defmodule EqmiResponseMessageTest do
  use ExUnit.Case
  @payload <<0, 0, 0, 0>>
  test "response message" do
    expected = %{qmi_error: 0, qmi_result: 0}
    assert expected == Eqmi.MessageResponse.parse(@payload)
  end
end
