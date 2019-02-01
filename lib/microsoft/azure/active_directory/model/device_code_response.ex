defmodule Microsoft.Azure.ActiveDirectory.Model.DeviceCodeResponse do
  #
  # Response from /tenant.onmicrosoft.com/oauth2/devicecode
  #

  @derive {Inspect, except: [:device_code]}

  defstruct [
    :user_code,
    :device_code,
    :verification_url,
    :expires_in,
    :interval,
    :message,
    # custom field from me
    :expires_on
  ]

  def expires_in(%__MODULE__{expires_on: expires_on}),
    do: expires_on |> Timex.diff(Timex.now(), :seconds)

  def from_json(json) do
    json
    |> Poison.decode!(as: %__MODULE__{})
    |> Map.update!(:expires_in, &String.to_integer/1)
    |> Map.update!(:interval, &String.to_integer/1)
  end
end
