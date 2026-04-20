defmodule DoubleTalkWeb.HomeLive do
  use DoubleTalkWeb, :live_view

  alias DoubleTalk.GameRooms

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       page_title: "DoubleTalk",
       viewer_id: session["viewer_id"]
     )}
  end

  @impl true
  def handle_event("create_room", %{"room" => %{"mode" => mode, "nickname" => nickname}}, socket) do
    nickname = sanitize_name(nickname)

    if nickname == "" do
      {:noreply, put_flash(socket, :error, "Pick a nickname before creating a room.")}
    else
      host = %{id: socket.assigns.viewer_id, name: nickname}

      case GameRooms.create_room(host, mode) do
        {:ok, room_code} ->
          {:noreply, push_navigate(socket, to: ~p"/rooms/#{room_code}?name=#{nickname}")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Could not create a room right now.")}
      end
    end
  end

  def handle_event("join_room", %{"room" => %{"code" => code, "nickname" => nickname}}, socket) do
    room_code = normalize_code(code)
    nickname = sanitize_name(nickname)

    cond do
      nickname == "" ->
        {:noreply, put_flash(socket, :error, "Add a nickname before joining a room.")}

      room_code == "" ->
        {:noreply, put_flash(socket, :error, "Enter a room code to join your friends.")}

      not GameRooms.exists?(room_code) ->
        {:noreply, put_flash(socket, :error, "That room code is not active right now.")}

      true ->
        {:noreply, push_navigate(socket, to: ~p"/rooms/#{room_code}?name=#{nickname}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="game-shell hero-grid">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <main class="mx-auto flex min-h-screen max-w-7xl flex-col px-4 py-8 sm:px-6 lg:px-8">
        <section class="reveal-rise grid gap-8 lg:grid-cols-[1.3fr,0.9fr] lg:items-center">
          <div class="space-y-6">
            <div class="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-4 py-2 text-xs uppercase tracking-[0.35em] text-[var(--accent-mint)]">
              Phoenix LiveView party game
            </div>

            <div class="space-y-4">
              <h1 class="font-display text-5xl font-black uppercase leading-none text-[var(--ink-100)] sm:text-6xl lg:text-7xl">
                DoubleTalk
              </h1>
              <p class="max-w-2xl text-lg leading-8 text-[var(--ink-200)]">
                A real-time social deduction game where every player sees a different truth.
                Create a room, give sharp clues, and catch the undercover word or the player
                with no location before the clock runs out.
              </p>
            </div>

            <div class="grid gap-3 sm:grid-cols-3">
              <div class="glass-panel rounded-3xl p-4">
                <div class="text-xs uppercase tracking-[0.3em] text-[var(--ink-300)]">Players</div>
                <div class="mt-2 text-3xl font-bold text-[var(--accent-gold)]">4-10</div>
                <p class="mt-2 text-sm text-[var(--ink-200)]">
                  Built for a real friend group, not just a demo tab.
                </p>
              </div>
              <div class="glass-panel rounded-3xl p-4">
                <div class="text-xs uppercase tracking-[0.3em] text-[var(--ink-300)]">Modes</div>
                <div class="mt-2 text-3xl font-bold text-[var(--accent-coral)]">2</div>
                <p class="mt-2 text-sm text-[var(--ink-200)]">
                  Undercover word pairs and spy-with-no-location.
                </p>
              </div>
              <div class="glass-panel rounded-3xl p-4">
                <div class="text-xs uppercase tracking-[0.3em] text-[var(--ink-300)]">Loop</div>
                <div class="mt-2 text-3xl font-bold text-[var(--accent-mint)]">Live</div>
                <p class="mt-2 text-sm text-[var(--ink-200)]">
                  Synchronized phases, timers, voting, and rematches.
                </p>
              </div>
            </div>
          </div>

          <div class="stagger-fade space-y-5">
            <section class="glass-panel rounded-[2rem] p-6 sm:p-8">
              <div class="mb-5 flex items-center justify-between">
                <div>
                  <h2 class="font-display text-2xl font-bold uppercase text-[var(--ink-100)]">
                    Start a room
                  </h2>
                  <p class="mt-1 text-sm text-[var(--ink-200)]">
                    Make the room, share the code, and host the round flow.
                  </p>
                </div>
                <div class="rounded-full bg-[var(--accent-gold)]/15 px-3 py-1 text-xs uppercase tracking-[0.3em] text-[var(--accent-gold)]">
                  Host
                </div>
              </div>

              <form phx-submit="create_room" class="space-y-4">
                <.input
                  name="room[nickname]"
                  label="Nickname"
                  value=""
                  placeholder="Captain Clue"
                  maxlength="24"
                  autocomplete="nickname"
                />
                <.input
                  type="select"
                  name="room[mode]"
                  label="Game mode"
                  options={[
                    {"Undercover", "undercover"},
                    {"Spyfall-lite", "spy"}
                  ]}
                  value="undercover"
                />
                <.button class="btn btn-primary btn-block h-13 rounded-2xl border-none bg-[var(--accent-gold)] text-slate-900 hover:bg-[var(--accent-gold)]/90">
                  Create room
                </.button>
              </form>
            </section>

            <section class="glass-panel rounded-[2rem] p-6 sm:p-8">
              <div class="mb-5 flex items-center justify-between">
                <div>
                  <h2 class="font-display text-2xl font-bold uppercase text-[var(--ink-100)]">
                    Join a room
                  </h2>
                  <p class="mt-1 text-sm text-[var(--ink-200)]">
                    Bring a nickname and a four-letter code.
                  </p>
                </div>
                <div class="rounded-full bg-[var(--accent-mint)]/15 px-3 py-1 text-xs uppercase tracking-[0.3em] text-[var(--accent-mint)]">
                  Guest
                </div>
              </div>

              <form phx-submit="join_room" class="grid gap-4 sm:grid-cols-2">
                <.input
                  name="room[code]"
                  label="Room code"
                  value=""
                  placeholder="ABCD"
                  maxlength="4"
                  class="w-full input uppercase tracking-[0.45em]"
                />
                <.input
                  name="room[nickname]"
                  label="Nickname"
                  value=""
                  placeholder="Quiet Suspect"
                  maxlength="24"
                />
                <.button class="btn btn-block h-13 rounded-2xl border border-white/10 bg-white/5 text-[var(--ink-100)] hover:bg-white/10 sm:col-span-2">
                  Enter room
                </.button>
              </form>
            </section>
          </div>
        </section>
      </main>
    </div>
    """
  end

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
end
