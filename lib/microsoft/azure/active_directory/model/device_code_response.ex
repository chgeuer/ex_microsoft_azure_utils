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
    :message
  ]

  def from_json(json) do
    json
    |> Poison.decode!(as: %__MODULE__{})
    |> Map.update!(:expires_in, &String.to_integer/1)
    |> Map.update!(:interval, &String.to_integer/1)
  end
end
