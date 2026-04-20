defmodule DoubleTalkWeb.RoomLive do
  use DoubleTalkWeb, :live_view

  alias DoubleTalk.GameRooms

  @impl true
  def mount(%{"code" => code} = params, session, socket) do
    code = normalize_code(code)
    viewer_id = session["viewer_id"]

    socket =
      socket
      |> assign(
        page_title: "Room #{code}",
        code: code,
        viewer_id: viewer_id,
        join_name: params["name"] || "",
        now: DateTime.utc_now(),
        room: nil,
        room_missing?: false
      )
      |> load_room()

    if connected?(socket) do
      GameRooms.subscribe(code)
      :timer.send_interval(1_000, :tick)
      send(self(), {:attempt_join, socket.assigns.join_name})
    end

    {:ok, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    GameRooms.disconnect(socket.assigns.code, socket.assigns.viewer_id)
    :ok
  end

  @impl true
  def handle_event("join_room", %{"join" => %{"nickname" => nickname}}, socket) do
    {:noreply, join_room(socket, nickname)}
  end

  def handle_event("leave_lobby", _params, socket) do
    socket =
      case GameRooms.leave(socket.assigns.code, socket.assigns.viewer_id) do
        {:ok, _room} -> load_room(socket)
        {:error, reason} -> put_flash(socket, :error, error_message(reason))
      end

    {:noreply, socket}
  end

  def handle_event("toggle_ready", _params, socket),
    do:
      {:noreply,
       run_action(socket, fn ->
         GameRooms.toggle_ready(socket.assigns.code, socket.assigns.viewer_id)
       end)}

  def handle_event("start_match", _params, socket),
    do:
      {:noreply,
       run_action(socket, fn ->
         GameRooms.start_match(socket.assigns.code, socket.assigns.viewer_id)
       end)}

  def handle_event("submit_clue", %{"clue" => %{"text" => text}}, socket) do
    {:noreply,
     run_action(socket, fn ->
       GameRooms.submit_clue(socket.assigns.code, socket.assigns.viewer_id, text)
     end)}
  end

  def handle_event("cast_vote", %{"target" => target_id}, socket) do
    {:noreply,
     run_action(socket, fn ->
       GameRooms.cast_vote(socket.assigns.code, socket.assigns.viewer_id, target_id)
     end)}
  end

  def handle_event("rematch", _params, socket) do
    {:noreply,
     run_action(socket, fn -> GameRooms.rematch(socket.assigns.code, socket.assigns.viewer_id) end)}
  end

  @impl true
  def handle_info({:attempt_join, nickname}, socket) do
    {:noreply, join_room(socket, nickname)}
  end

  def handle_info({:room_updated, _code}, socket) do
    {:noreply, load_room(socket)}
  end

  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :now, DateTime.utc_now())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="game-shell">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <main class="mx-auto flex min-h-screen max-w-7xl flex-col px-4 py-6 sm:px-6 lg:px-8">
        <%= if @room_missing? do %>
          <section class="mx-auto flex min-h-[70vh] max-w-xl items-center">
            <div class="glass-panel w-full rounded-[2rem] p-8 text-center">
              <div class="mx-auto mb-4 flex h-18 w-18 items-center justify-center rounded-full bg-[var(--accent-coral)]/15 text-[var(--accent-coral)]">
                <.icon name="hero-exclamation-triangle" class="size-10" />
              </div>
              <h1 class="font-display text-4xl font-black uppercase">Room not found</h1>
              <p class="mt-3 text-[var(--ink-200)]">
                This room is not active right now. Create a fresh room or ask your host for a new code.
              </p>
              <.button
                navigate={~p"/"}
                class="mt-6 btn rounded-2xl border-none bg-[var(--accent-gold)] text-slate-900 hover:bg-[var(--accent-gold)]/90"
              >
                Back home
              </.button>
            </div>
          </section>
        <% else %>
          <section class="mb-6 grid gap-4 lg:grid-cols-[1.2fr,0.8fr]">
            <div class="glass-panel rounded-[2rem] p-6">
              <div class="flex flex-wrap items-center justify-between gap-4">
                <div>
                  <div class="text-xs uppercase tracking-[0.35em] text-[var(--accent-mint)]">
                    Room {@room.room_code}
                  </div>
                  <h1 class="mt-2 font-display text-4xl font-black uppercase text-[var(--ink-100)]">
                    {mode_title(@room.mode)}
                  </h1>
                  <p class="mt-2 max-w-2xl text-sm leading-7 text-[var(--ink-200)]">
                    {mode_copy(@room.mode)}
                  </p>
                </div>

                <div class="flex flex-wrap items-center gap-3">
                  <div class="rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-center">
                    <div class="text-xs uppercase tracking-[0.3em] text-[var(--ink-300)]">Phase</div>
                    <div class="mt-1 text-lg font-semibold text-[var(--ink-100)]">
                      {phase_title((@room.round && @room.round.phase) || :lobby)}
                    </div>
                  </div>
                  <div class="rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-center">
                    <div class="text-xs uppercase tracking-[0.3em] text-[var(--ink-300)]">Timer</div>
                    <div class="mt-1 text-lg font-semibold text-[var(--accent-gold)]">
                      {countdown(@room.round && @room.round.phase_ends_at, @now)}
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div class="glass-panel rounded-[2rem] p-6">
              <div class="text-xs uppercase tracking-[0.35em] text-[var(--ink-300)]">Scoreboard</div>
              <div class="mt-4 space-y-3">
                <%= for player <- sorted_players(@room.players) do %>
                  <div class="flex items-center justify-between rounded-2xl border border-white/8 bg-black/10 px-4 py-3">
                    <div>
                      <div class="font-semibold text-[var(--ink-100)]">{player.name}</div>
                      <div class="mt-1 text-xs uppercase tracking-[0.25em] text-[var(--ink-300)]">
                        {player_status(player, @room.host_id)}
                      </div>
                    </div>
                    <div class="text-2xl font-black text-[var(--accent-gold)]">{player.score}</div>
                  </div>
                <% end %>
              </div>
            </div>
          </section>

          <%= if not @room.joined? and @room.status == :lobby do %>
            <section class="mx-auto mt-6 grid max-w-5xl gap-6 lg:grid-cols-[0.9fr,1.1fr]">
              <div class="glass-panel rounded-[2rem] p-6">
                <div class="text-xs uppercase tracking-[0.35em] text-[var(--accent-gold)]">
                  Join lobby
                </div>
                <h2 class="mt-3 font-display text-3xl font-black uppercase">Enter the room</h2>
                <p class="mt-2 text-sm leading-7 text-[var(--ink-200)]">
                  This room is waiting in the lobby. Pick a nickname and you can ready up immediately.
                </p>
                <form phx-submit="join_room" class="mt-6 space-y-4">
                  <.input name="join[nickname]" label="Nickname" maxlength="24" value={@join_name} />
                  <.button class="btn btn-block rounded-2xl border-none bg-[var(--accent-gold)] text-slate-900 hover:bg-[var(--accent-gold)]/90">
                    Join room
                  </.button>
                </form>
              </div>

              <div class="glass-panel rounded-[2rem] p-6">
                <div class="flex items-center justify-between">
                  <div>
                    <div class="text-xs uppercase tracking-[0.35em] text-[var(--ink-300)]">
                      Players
                    </div>
                    <h2 class="mt-2 font-display text-2xl font-black uppercase">
                      {length(@room.players)} / {@room.room_rules.max_players}
                    </h2>
                  </div>
                  <div class="rounded-full bg-white/5 px-4 py-2 text-xs uppercase tracking-[0.25em] text-[var(--accent-mint)]">
                    {ready_count(@room.players)} ready
                  </div>
                </div>

                <div class="mt-6 grid gap-3 sm:grid-cols-2">
                  <%= for player <- @room.players do %>
                    <div class="rounded-2xl border border-white/8 bg-black/10 px-4 py-3">
                      <div class="font-semibold">{player.name}</div>
                      <div class="mt-1 text-xs uppercase tracking-[0.25em] text-[var(--ink-300)]">
                        {player_status(player, @room.host_id)}
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </section>
          <% else %>
            <section class="grid gap-6 lg:grid-cols-[0.92fr,1.08fr]">
              <div class="space-y-6">
                <div class={[
                  "glass-panel rounded-[2rem] p-6",
                  @room.round && @room.round.phase in [:role_reveal, :clue_turn] && "phase-pulse"
                ]}>
                  <div class="text-xs uppercase tracking-[0.35em] text-[var(--ink-300)]">
                    Your secret
                  </div>
                  <%= if secret = @room.viewer.secret do %>
                    <div class="mt-4 rounded-[1.75rem] border border-white/10 bg-black/15 p-5">
                      <div class="text-sm uppercase tracking-[0.3em] text-[var(--accent-mint)]">
                        {role_title(secret.role)}
                      </div>
                      <div class="mt-3 font-display text-4xl font-black uppercase text-[var(--accent-gold)]">
                        {secret_word(secret.word)}
                      </div>
                      <p class="mt-3 text-sm leading-7 text-[var(--ink-200)]">
                        {role_copy(secret.role)}
                      </p>
                    </div>
                  <% else %>
                    <p class="mt-4 text-[var(--ink-200)]">
                      Once the match starts, your role and secret prompt will appear here.
                    </p>
                  <% end %>
                </div>

                <div class="glass-panel rounded-[2rem] p-6">
                  <div class="text-xs uppercase tracking-[0.35em] text-[var(--ink-300)]">Players</div>
                  <div class="mt-4 space-y-3">
                    <%= for player <- @room.players do %>
                      <div class={[
                        "rounded-2xl border px-4 py-3 transition",
                        player.id == (@room.round && @room.round.current_turn_player_id) &&
                          "border-[var(--accent-gold)] bg-[var(--accent-gold)]/10",
                        player.id != (@room.round && @room.round.current_turn_player_id) &&
                          "border-white/8 bg-black/10"
                      ]}>
                        <div class="flex items-start justify-between gap-3">
                          <div>
                            <div class="font-semibold text-[var(--ink-100)]">{player.name}</div>
                            <div class="mt-1 text-xs uppercase tracking-[0.25em] text-[var(--ink-300)]">
                              {player_status(player, @room.host_id)}
                            </div>
                          </div>
                          <div class="flex flex-wrap gap-2 text-[11px] uppercase tracking-[0.22em]">
                            <span
                              :if={player.ready?}
                              class="rounded-full bg-[var(--accent-mint)]/15 px-2 py-1 text-[var(--accent-mint)]"
                            >
                              Ready
                            </span>
                            <span
                              :if={player.clue}
                              class="rounded-full bg-white/5 px-2 py-1 text-[var(--ink-200)]"
                            >
                              Clued
                            </span>
                            <span
                              :if={player.has_voted?}
                              class="rounded-full bg-white/5 px-2 py-1 text-[var(--ink-200)]"
                            >
                              Voted
                            </span>
                            <span
                              :if={player.revealed_role}
                              class="rounded-full bg-[var(--accent-coral)]/15 px-2 py-1 text-[var(--accent-coral)]"
                            >
                              {role_title(player.revealed_role)}
                            </span>
                          </div>
                        </div>
                        <div :if={player.revealed_word} class="mt-3 text-sm text-[var(--ink-200)]">
                          Secret:
                          <span class="font-semibold text-[var(--accent-gold)]">
                            {player.revealed_word}
                          </span>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>

              <div class="space-y-6">
                <div class="glass-panel rounded-[2rem] p-6">
                  <div class="flex flex-wrap items-center justify-between gap-4">
                    <div>
                      <div class="text-xs uppercase tracking-[0.35em] text-[var(--ink-300)]">
                        {phase_title((@room.round && @room.round.phase) || :lobby)}
                      </div>
                      <h2 class="mt-2 font-display text-3xl font-black uppercase">
                        {phase_heading((@room.round && @room.round.phase) || :lobby)}
                      </h2>
                      <p class="mt-2 max-w-2xl text-sm leading-7 text-[var(--ink-200)]">
                        {phase_copy((@room.round && @room.round.phase) || :lobby, @room)}
                      </p>
                    </div>
                    <div class="rounded-full border border-white/10 bg-white/5 px-4 py-2 text-sm uppercase tracking-[0.25em] text-[var(--accent-gold)]">
                      {countdown(@room.round && @room.round.phase_ends_at, @now)}
                    </div>
                  </div>

                  <%= if @room.status == :lobby and @room.joined? do %>
                    <div class="mt-6 grid gap-3 sm:grid-cols-2">
                      <.button
                        phx-click="toggle_ready"
                        class="btn h-13 rounded-2xl border-none bg-[var(--accent-mint)] text-slate-900 hover:bg-[var(--accent-mint)]/90"
                      >
                        {if @room.viewer.ready?, do: "Unready", else: "Ready up"}
                      </.button>
                      <.button
                        :if={@room.can.start_match}
                        phx-click="start_match"
                        class="btn h-13 rounded-2xl border-none bg-[var(--accent-gold)] text-slate-900 hover:bg-[var(--accent-gold)]/90"
                      >
                        Start match
                      </.button>
                      <.button
                        phx-click="leave_lobby"
                        class="btn rounded-2xl border border-white/10 bg-white/5 text-[var(--ink-100)] hover:bg-white/10 sm:col-span-2"
                      >
                        Leave lobby
                      </.button>
                    </div>
                  <% end %>

                  <%= if @room.can.submit_clue do %>
                    <form phx-submit="submit_clue" class="mt-6 space-y-4">
                      <.input
                        name="clue[text]"
                        label="Your clue"
                        value=""
                        placeholder="One sharp word or a tiny phrase"
                        maxlength="28"
                        autocomplete="off"
                      />
                      <.button class="btn rounded-2xl border-none bg-[var(--accent-gold)] text-slate-900 hover:bg-[var(--accent-gold)]/90">
                        Lock clue
                      </.button>
                    </form>
                  <% end %>

                  <%= if @room.can.vote do %>
                    <div class="mt-6 grid gap-3 sm:grid-cols-2">
                      <%= for player <- vote_targets(@room.players, @viewer_id) do %>
                        <button
                          type="button"
                          phx-click="cast_vote"
                          phx-value-target={player.id}
                          class="rounded-2xl border border-white/10 bg-black/15 px-4 py-4 text-left transition hover:border-[var(--accent-coral)] hover:bg-[var(--accent-coral)]/8"
                        >
                          <div class="text-xs uppercase tracking-[0.3em] text-[var(--ink-300)]">
                            Vote out
                          </div>
                          <div class="mt-2 text-xl font-bold text-[var(--ink-100)]">
                            {player.name}
                          </div>
                        </button>
                      <% end %>
                    </div>
                  <% end %>

                  <%= if @room.can.rematch do %>
                    <div class="mt-6">
                      <.button
                        phx-click="rematch"
                        class="btn rounded-2xl border-none bg-[var(--accent-gold)] text-slate-900 hover:bg-[var(--accent-gold)]/90"
                      >
                        Run it back
                      </.button>
                    </div>
                  <% end %>
                </div>

                <div class="glass-panel rounded-[2rem] p-6">
                  <div class="flex items-center justify-between">
                    <div class="text-xs uppercase tracking-[0.35em] text-[var(--ink-300)]">Clues</div>
                    <div class="text-xs uppercase tracking-[0.25em] text-[var(--ink-300)]">
                      Round {(@room.round && @room.round.round_number) || 0} / {@room.room_rules.max_rounds}
                    </div>
                  </div>

                  <div class="mt-4 space-y-3">
                    <%= if @room.round && @room.round.clues != [] do %>
                      <%= for clue <- @room.round.clues do %>
                        <div class="rounded-2xl border border-white/8 bg-black/10 px-4 py-3">
                          <div class="flex items-center justify-between gap-4">
                            <div class="font-semibold">{clue.player_name}</div>
                            <span
                              :if={clue.timed_out?}
                              class="rounded-full bg-[var(--accent-coral)]/12 px-2 py-1 text-[11px] uppercase tracking-[0.24em] text-[var(--accent-coral)]"
                            >
                              Timeout
                            </span>
                          </div>
                          <div class="mt-2 text-lg text-[var(--ink-100)]">{clue.text}</div>
                        </div>
                      <% end %>
                    <% else %>
                      <div class="rounded-2xl border border-dashed border-white/10 px-4 py-8 text-center text-[var(--ink-300)]">
                        Clues will appear here as players lock them in.
                      </div>
                    <% end %>
                  </div>
                </div>

                <%= if result = @room.round && @room.round.result do %>
                  <div class="glass-panel rounded-[2rem] p-6">
                    <div class="text-xs uppercase tracking-[0.35em] text-[var(--ink-300)]">
                      Round reveal
                    </div>
                    <h3 class="mt-2 font-display text-3xl font-black uppercase text-[var(--accent-gold)]">
                      {round_result_title(result.winner)}
                    </h3>
                    <p class="mt-3 text-sm leading-7 text-[var(--ink-200)]">
                      {round_result_copy(result, @room.players)}
                    </p>

                    <div class="mt-5 grid gap-3 sm:grid-cols-2">
                      <%= for player <- @room.players do %>
                        <div class="rounded-2xl border border-white/8 bg-black/10 px-4 py-3">
                          <div class="font-semibold">{player.name}</div>
                          <div class="mt-2 text-sm text-[var(--ink-200)]">
                            {role_title(player.revealed_role || :civilian)}
                            <%= if player.revealed_word do %>
                              ·
                              <span class="font-semibold text-[var(--accent-gold)]">
                                {player.revealed_word}
                              </span>
                            <% end %>
                          </div>
                          <div class="mt-2 text-xs uppercase tracking-[0.25em] text-[var(--ink-300)]">
                            Votes: {Map.get(result.vote_tally, player.id, 0)}
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </section>
          <% end %>
        <% end %>
      </main>
    </div>
    """
  end

  defp join_room(%{assigns: %{room_missing?: true}} = socket, _nickname), do: socket

  defp join_room(socket, nickname) do
    nickname = sanitize_name(nickname)

    cond do
      socket.assigns.room && socket.assigns.room.joined? && socket.assigns.room.viewer.connected? ->
        socket

      nickname == "" && not (socket.assigns.room && socket.assigns.room.joined?) ->
        put_flash(socket, :error, "Choose a nickname before joining the room.")

      true ->
        case GameRooms.join(socket.assigns.code, %{id: socket.assigns.viewer_id, name: nickname}) do
          {:ok, _room} ->
            socket
            |> assign(:join_name, nickname)
            |> load_room()

          {:error, reason} ->
            put_flash(socket, :error, error_message(reason))
        end
    end
  end

  defp load_room(socket) do
    case GameRooms.get_view(socket.assigns.code, socket.assigns.viewer_id) do
      {:ok, room} ->
        socket
        |> assign(:room, room)
        |> assign(:room_missing?, false)

      {:error, :room_not_found} ->
        assign(socket, room: nil, room_missing?: true)
    end
  end

  defp run_action(socket, action) do
    case action.() do
      {:ok, _room} -> load_room(socket)
      {:error, reason} -> put_flash(socket, :error, error_message(reason))
    end
  end

  defp error_message(:not_host), do: "Only the host can do that."
  defp error_message(:not_enough_players), do: "You need at least four players to start."
  defp error_message(:players_not_ready), do: "Everyone in the lobby needs to be ready first."
  defp error_message(:match_in_progress), do: "This room is already mid-match."
  defp error_message(:room_full), do: "That room is already full."
  defp error_message(:nickname_required), do: "Add a nickname first."
  defp error_message(:wrong_phase), do: "That action is not available in this phase."
  defp error_message(:not_your_turn), do: "Hold for your turn."
  defp error_message(:already_voted), do: "Your vote is already locked in."
  defp error_message(:cannot_vote_self), do: "Pick someone else."
  defp error_message(:cannot_leave_now), do: "You can only leave from the lobby."
  defp error_message(:cannot_rematch), do: "Only the host can start the rematch."
  defp error_message(:invalid_clue), do: "Your clue needs at least one character."
  defp error_message(_reason), do: "That move did not go through."

  defp normalize_code(code) do
    code
    |> to_string()
    |> String.trim()
    |> String.upcase()
  end

  defp sanitize_name(name) do
    name
    |> to_string()
    |> String.trim()
    |> String.slice(0, 24)
  end

  defp countdown(nil, _now), do: "--"

  defp countdown(%DateTime{} = ends_at, %DateTime{} = now) do
    ends_at
    |> DateTime.diff(now, :second)
    |> max(0)
    |> Integer.to_string()
    |> String.pad_leading(2, "0")
  end

  defp ready_count(players), do: Enum.count(players, & &1.ready?)

  defp sorted_players(players), do: Enum.sort_by(players, &{-&1.score, &1.name})

  defp vote_targets(players, viewer_id), do: Enum.reject(players, &(&1.id == viewer_id))

  defp player_status(player, host_id) do
    flags =
      []
      |> maybe_add_flag(player.id == host_id, "host")
      |> maybe_add_flag(player.connected?, "online")
      |> maybe_add_flag(not player.connected?, "away")

    flags |> Enum.join(" · ") |> String.upcase()
  end

  defp maybe_add_flag(flags, true, value), do: flags ++ [value]
  defp maybe_add_flag(flags, false, _value), do: flags

  defp mode_title(:undercover), do: "Undercover"
  defp mode_title(:spy), do: "Spyfall-lite"

  defp mode_copy(:undercover) do
    "Most players share the same word. One or two hidden players get a related word and need to blend in."
  end

  defp mode_copy(:spy) do
    "Most players see the same location. The spy gets no location and has to survive the vote."
  end

  defp phase_title(:lobby), do: "Lobby"
  defp phase_title(:role_reveal), do: "Role reveal"
  defp phase_title(:clue_turn), do: "Clue turn"
  defp phase_title(:discussion), do: "Discussion"
  defp phase_title(:voting), do: "Voting"
  defp phase_title(:round_result), do: "Round result"
  defp phase_title(:match_result), do: "Match result"

  defp phase_heading(:lobby), do: "Ready the table"
  defp phase_heading(:role_reveal), do: "Secrets are live"
  defp phase_heading(:clue_turn), do: "One player at a time"
  defp phase_heading(:discussion), do: "Read the room"
  defp phase_heading(:voting), do: "Point at someone"
  defp phase_heading(:round_result), do: "Masks off"
  defp phase_heading(:match_result), do: "Final board"

  defp phase_copy(:lobby, room) do
    "#{ready_count(room.players)} of #{length(room.players)} players are ready. The host can start once everyone is locked in."
  end

  defp phase_copy(:role_reveal, _room),
    do: "Memorize your role and your secret prompt before the clue train starts."

  defp phase_copy(:clue_turn, room) do
    current_name = current_player_name(room)
    "Only #{current_name} can clue right now. Keep it short and suspicious."
  end

  defp phase_copy(:discussion, _room),
    do: "Talk it out. Compare the clues, accuse carefully, and get ready to vote."

  defp phase_copy(:voting, _room),
    do:
      "Everyone casts one vote. A unique top vote on a hidden player gives the seekers the round."

  defp phase_copy(:round_result, _room),
    do: "Roles are revealed and points are awarded. The next round starts automatically."

  defp phase_copy(:match_result, _room),
    do: "Five rounds are over. Keep the room together and hit rematch for another run."

  defp current_player_name(room) do
    current_id = room.round && room.round.current_turn_player_id
    current = Enum.find(room.players, &(&1.id == current_id))
    if current, do: current.name, else: "Nobody"
  end

  defp role_title(:civilian), do: "Civilian"
  defp role_title(:undercover), do: "Undercover"
  defp role_title(:spy), do: "Spy"
  defp role_title(:detective), do: "Insider"

  defp role_copy(:civilian),
    do: "Match the table, expose the off-note clue, and catch the hidden player."

  defp role_copy(:undercover), do: "You have the related word. Blend in and avoid the vote."
  defp role_copy(:spy), do: "You have no location. Reverse-engineer the room from the clues."

  defp role_copy(:detective),
    do: "Everyone else knows the location. Use careful clues to flush out the spy."

  defp secret_word(nil), do: "No location"
  defp secret_word(word), do: word

  defp round_result_title(:seekers), do: "Seekers score"
  defp round_result_title(:hidden), do: "Hidden players survive"

  defp round_result_copy(result, players) do
    names = Map.new(players, &{&1.id, &1.name})
    hidden_names = Enum.map(result.hidden_ids, &Map.get(names, &1)) |> Enum.join(", ")

    case result.winner do
      :seekers ->
        top_name = result.top_target_id && Map.get(names, result.top_target_id)
        "The room isolated #{top_name}. Hidden role holders were #{hidden_names}."

      :hidden ->
        if result.top_target_id do
          "The table voted out the wrong player, so #{hidden_names} escaped with the point."
        else
          "The vote tied or stalled, so #{hidden_names} slipped through the chaos."
        end
    end
  end
end
