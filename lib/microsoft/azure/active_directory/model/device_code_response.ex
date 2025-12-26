defmodule Microsoft.Azure.ActiveDirectory.DeviceAuthenticator.Model.DeviceCodeResponse do
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

  def from_json(json) when is_binary(json),
    do: json |> Jason.decode!(keys: :atoms) |> from_json()

  def from_json(map) when is_map(map) do
    struct(__MODULE__, map)
    |> Map.update!(:expires_in, fn
      val when is_binary(val) -> String.to_integer(val)
      val when is_integer(val) -> val
    end)
    |> Map.update!(:interval, fn
      val when is_binary(val) -> String.to_integer(val)
      val when is_integer(val) -> val
    end)
  end
end
