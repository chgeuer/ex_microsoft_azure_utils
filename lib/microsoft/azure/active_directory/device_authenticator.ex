defmodule Microsoft.Azure.ActiveDirectory.DeviceAuthenticator do
  alias Microsoft.Azure.ActiveDirectory.RestClient
  alias Microsoft.Azure.ActiveDirectory.DeviceAuthenticatorSupervisor

  alias __MODULE__.Model.{
    DeviceCodeResponse,
    TokenResponse,
    State,
    DeviceAuthenticatorError
  }

  # use GenServer, restart: :transient
  use GenServer, restart: :permanent

  #
  # Client section
  #
  def start_link(%State{supervisor_pid: pid} = state, opts \\ []) when is_pid(pid) do
    GenServer.start_link(__MODULE__, state, opts)
  end

  @spec get_device_code(pid(), integer()) :: struct()
  def get_device_code(pid, timeout \\ :infinity) do
    pid
    |> get_worker_pid()
    |> GenServer.call(:get_device_code, timeout)
  end

  @spec get_token(pid(), integer()) :: struct()
  def get_token(pid, timeout \\ :infinity) do
    pid
    |> get_worker_pid()
    |> GenServer.call(:get_token, timeout)
  end

  def force_refresh(pid) do
    pid
    |> get_worker_pid()
    |> GenServer.cast(:refresh_token)
  end

  def get_stage(pid) do
    pid
    |> get_worker_pid()
    |> GenServer.call(:get_stage)
  end

  def get_agent_pid(supervisor_pid),
    do: supervisor_pid |> DeviceAuthenticatorSupervisor.get_child_pid(Agent)

  def get_worker_pid(supervisor_pid),
    do: supervisor_pid |> DeviceAuthenticatorSupervisor.get_child_pid(Worker)

  def get_state(%{agent_pid: agent_pid}), do: Agent.get(agent_pid, & &1)

  def get_state(%{supervisor_pid: supervisor_pid}),
    do: get_state(%{agent_pid: get_agent_pid(supervisor_pid)})

  def get_state(supervisor_pid) when is_pid(supervisor_pid),
    do: get_state(%{supervisor_pid: supervisor_pid})

  def set_state(%{agent_pid: agent_pid} = worker_state) do
    Agent.update(agent_pid, fn _ -> worker_state end)

    worker_state
  end

  #
  # Server section
  #

  @impl GenServer
  def init(state = %State{}) do
    #
    # After the worker is started, it needs to fetch current state from state Agent.
    #

    {:ok, state, {:continue, :post_init}}
  end

  @impl true
  def handle_continue(
        :post_init,
        %State{supervisor_pid: supervisor_pid} = state
      ) do
    state_pid =
      supervisor_pid
      |> get_agent_pid()

    state =
      state
      |> Map.put(:state_pid, state_pid)
      |> get_state()
      |> Map.put(:state_pid, state_pid)
      |> Map.put(:supervisor_pid, supervisor_pid)
      |> set_default_if_nil(:stage, :initialized)
      |> reactivate_refresh_timers()

    state
    |> set_state()

    {:noreply, state}
  end

  defp set_default_if_nil(map, key, default_value) when is_map(map) do
    # If key is undefined, set it to the default value
    case map do
      %{^key => nil} -> %{map | key => default_value}
      _ -> map
    end
  end

  defp reactivate_refresh_timers(%State{refresh_timer: nil} = state), do: state

  defp reactivate_refresh_timers(
         %State{
           refresh_timer: refresh_timer,
           stage: :polling,
           device_code_response: %DeviceCodeResponse{interval: interval}
         } = state
       ) do
    refresh_timer |> Process.cancel_timer()
    timer = self() |> Process.send_after(:poll_for_token, 1000 * interval)

    state
    |> Map.put(:refresh_timer, timer)
  end

  defp reactivate_refresh_timers(
         %State{
           refresh_timer: refresh_timer,
           stage: :refreshing,
           token_response: %TokenResponse{expires_on: expires_on}
         } = state
       ) do
    expires_in = expires_on |> Timex.diff(Timex.now(), :seconds)
    refresh_timer |> Process.cancel_timer()
    timer = self() |> Process.send_after(:refresh_token, 1000 * expires_in)

    state
    |> Map.put(:refresh_timer, timer)
  end

  @impl GenServer
  def handle_call(
        :get_stage,
        _,
        state = %State{stage: stage}
      ),
      do: {:reply, stage, state}

  def handle_call(
        :get_device_code,
        _,
        state = %State{stage: :initialized}
      ) do
    #
    # Make the initial call to trigger device authentication
    case RestClient.get_device_code(state) do
      {:ok,
       device_code_response = %DeviceCodeResponse{expires_in: expires_in, interval: interval}} ->
        # remember when the code authN code expires
        expires_on = Timex.now() |> Timex.add(Timex.Duration.from_seconds(expires_in))

        timer =
          self()
          |> Process.send_after(:poll_for_token, 1000 * interval)

        new_state =
          state
          |> Map.put(:stage, :polling)
          |> Map.put(
            :device_code_response,
            device_code_response |> Map.put(:expires_on, expires_on)
          )
          |> Map.put(:refresh_timer, timer)

        new_state
        |> set_state()

        {:reply, {:ok, new_state.device_code_response}, new_state}

      {:error, body} ->
        {:reply, {:error, body}, state}
    end
  end

  def handle_call(
        :get_device_code,
        _,
        state = %State{
          stage: :polling,
          device_code_response: %{expires_on: expires_on} = device_code_response
        }
      )
      when expires_on != nil do
    #
    # As long as we're polling for the user signin, return the old device code's response
    #
    seconds_left = device_code_response |> DeviceCodeResponse.expires_in()

    cond do
      seconds_left > 0 -> {:reply, {:ok, device_code_response}, state}

      # if the current device code is expired, process should exit
      true -> {:stop, :normal, {:error, :cannot_use_expired_code_request}, state}
    end
  end

  def handle_call(:get_device_code, _, state = %State{stage: :refreshing}),
    do: {:reply, {:error, :token_already_issued}, state}

  def handle_call(:get_token, _, state = %State{stage: :initialized}),
    do: {:reply, {:error, :must_call_get_device_code}, state}

  def handle_call(:get_token, _, state = %State{stage: :polling}),
    do: {:reply, {:error, :waiting_for_user_authentication}, state}

  def handle_call(:get_token, _, state = %State{stage: :refreshing, token_response: token_response}) do
    # return the current token
    {:reply, {:ok, token_response}, state}
  end

  @impl GenServer
  def handle_info(
        :poll_for_token,
        state = %State{device_code_response: device_code_response}
      ) do
    seconds_left = device_code_response |> DeviceCodeResponse.expires_in()

    cond do
      seconds_left > 0 -> {:noreply, state |> fetch_token_impl()}
      # Process should exit if the current device code is expired
      true -> {:stop, :normal, state}
    end
  end

  def handle_info(:refresh_token, state = %State{stage: :refreshing}) do
    {:noreply, state |> refresh_token_impl()}
  end

  def handle_info(:refresh_token, state = %State{stage: _}) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:refresh_token, state = %State{stage: :refreshing}) do
    {:noreply, state |> refresh_token_impl()}
  end

  def handle_cast(:refresh_token, state = %State{stage: _}) do
    {:noreply, state}
  end

  defp fetch_token_impl(%State{device_code_response: device_code_response} = state) do
    case RestClient.fetch_device_code_token(state) do
      {:ok, token_response = %TokenResponse{}} ->
        # token_response = token_response |> tweak_token_response()

        new_state =
          state
          |> Map.put(:stage, :refreshing)
          |> Map.put(:token_response, token_response)
          |> Map.delete(:device_code_response)

        timer = self() |> Process.send_after(:refresh_token, 1000 * token_response.expires_in)

        new_state
        |> Map.put(:refresh_timer, timer)
        |> set_state()

      {:error, _error_doc = %DeviceAuthenticatorError{}} ->
        self() |> Process.send_after(:poll_for_token, 1000 * state.device_code_response.interval)

        #
        # Each time we polled without success, decrement the :expires_in seconds
        #
        state
        |> Map.put(
          :device_code_response,
          device_code_response
          |> Map.put(:expires_in, device_code_response |> DeviceCodeResponse.expires_in())
        )
        |> set_state()
    end
  end

  # defp tweak_token_response(%TokenResponse{} = token_response) do
  #   expires_in = 5
  #   expires_on = Timex.now() |> Timex.add(Timex.Duration.from_seconds(expires_in))
  #
  #   token_response
  #   |> Map.put(:expires_in, expires_in)
  #   |> Map.put(:ext_expires_in, expires_in)
  #   |> Map.put(:expires_on, expires_on)
  # end

  defp refresh_token_impl(state = %State{}) do
    if state.refresh_timer != nil do
      state.refresh_timer |> Process.cancel_timer()
    end

    case RestClient.refresh_token(state) do
      {:ok, token_response = %TokenResponse{}} ->
        # token_response = token_response |> tweak_token_response()

        new_state =
          state
          |> Map.put(:token_response, token_response)
          |> Map.put(:stage, :refreshing)

        timer = self() |> Process.send_after(:refresh_token, 1000 * token_response.expires_in)

        new_state
        |> Map.put(:refresh_timer, timer)
        |> set_state()

      _ ->
        state
    end
  end
end
