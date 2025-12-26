defmodule MicrosoftAzureMgmtClient do
  @scopes [
    # impersonate your user account
    "user_impersonation"
  ]

  def new_azure_public(token), do: "https://management.azure.com" |> new(token)
  def new_azure_germany(token), do: "https://management.microsoftazure.de" |> new(token)
  def new_azure_china(token), do: "https://management.chinacloudapi.cn" |> new(token)
  def new_azure_government(token), do: "https://management.usgovcloudapi.net" |> new(token)

  defp new(base_url, token_fetcher) when is_function(token_fetcher) do
    token = token_fetcher.(@scopes)
    new(base_url, token)
  end

  defp new(base_url, token) when is_binary(token) do
    options = [
      base_url: base_url,
      auth: {:bearer, token},
      headers: [{"user-agent", "Elixir"}]
    ]

    options =
      case proxy_config() do
        nil -> options
        proxy -> Keyword.put(options, :connect_options, proxy)
      end

    Req.new(options)
  end

  defp proxy_config do
    case System.get_env("http_proxy") do
      nil -> nil
      "" -> nil
      proxy_cfg ->
        [host, port] = String.split(proxy_cfg, ":")
        [proxy: {String.to_charlist(host), String.to_integer(port)}]
    end
  end
end
