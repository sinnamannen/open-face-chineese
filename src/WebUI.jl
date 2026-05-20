module WebUI

using Sockets
using ..Cards
using ..Engine
using ..Players
using ..Simulation: player_factory

export WebSession, new_web_session, action_from_row_tokens, apply_human_action!
export start_next_hand!, render_page, serve

mutable struct WebSession
    state::GameState
    seed::Int
    hand_number::Int
    cumulative_score::Int
    fantasy_cards::NTuple{2, UInt8}
    bot_name::String
    bot::Player
    bot_seed::Int
    bot_samples::Int
    message::String
end

make_bot(name::AbstractString, seed::Integer, samples::Integer)::Player =
    player_factory(name, seed_offset = seed, greedy_samples = samples)(0)

function new_web_session(; seed::Integer = 1, bot_name::AbstractString = "greedy", bot_samples::Integer = 500)
    bot_seed = seed + 10_000
    clean_bot_name = lowercase(strip(bot_name))
    return WebSession(
        new_hand(seed = seed),
        Int(seed),
        1,
        0,
        (UInt8(0), UInt8(0)),
        clean_bot_name,
        make_bot(clean_bot_name, bot_seed, bot_samples),
        Int(bot_seed),
        Int(bot_samples),
        "",
    )
end

function row_from_token(token::AbstractString)::UInt8
    t = lowercase(strip(token))
    t in ("t", "top", "1") && return TOP
    t in ("m", "middle", "2") && return MIDDLE
    t in ("b", "bottom", "3") && return BOTTOM
    t in ("d", "discard", "0") && return UInt8(0)
    throw(ArgumentError("unknown row token '$token'"))
end

function action_from_row_tokens(obs::Observation, row_tokens::AbstractVector{<:AbstractString})::PlacementAction
    pcards = pending_cards(obs.pending)
    length(row_tokens) == length(pcards) ||
        throw(ArgumentError("expected $(length(pcards)) row choices, got $(length(row_tokens))"))

    placements = Placement[]
    discards = Card[]
    for (card, token) in zip(pcards, row_tokens)
        row = row_from_token(token)
        row == 0 ? push!(discards, card) : push!(placements, Placement(card, row))
    end

    action = PlacementAction(placements, discards)
    Engine.validate_action(obs.boards[Int(obs.player_id)], obs.pending, action)
    return action
end

function bot_until_human!(session::WebSession)
    while !is_terminal(session.state) && current_player(session.state) == 2
        obs = view_from(session.state, 2)
        action = decide(session.bot, obs)
        session.state = Engine.apply(session.state, action)
    end
    return session
end

function apply_human_action!(session::WebSession, row_tokens::AbstractVector{<:AbstractString})
    if is_terminal(session.state)
        session.message = "The hand is complete."
        return session
    end

    if current_player(session.state) != 1
        bot_until_human!(session)
        return session
    end

    obs = view_from(session.state, 1)
    action = action_from_row_tokens(obs, row_tokens)
    session.state = Engine.apply(session.state, action)
    bot_until_human!(session)
    session.message = is_terminal(session.state) ? "Hand complete." : "Bot moved."
    return session
end

function start_next_hand!(session::WebSession)
    if !is_terminal(session.state)
        session.message = "Finish the current hand before starting the next one."
        return session
    end

    score = score_hand(session.state)
    session.cumulative_score += Int(score.total)
    session.fantasy_cards = next_fantasy_cards(session.state)
    session.hand_number += 1
    session.seed += 1
    session.bot_seed += 1
    session.state = new_hand(seed = session.seed, fantasy_cards = session.fantasy_cards)
    session.bot = make_bot(session.bot_name, session.bot_seed, session.bot_samples)
    session.message = "Started hand $(session.hand_number)."
    bot_until_human!(session)
    return session
end

function reset!(session::WebSession, seed::Integer; bot_name::AbstractString = session.bot_name)
    fresh = new_web_session(seed = seed, bot_name = bot_name, bot_samples = session.bot_samples)
    session.state = fresh.state
    session.seed = fresh.seed
    session.hand_number = fresh.hand_number
    session.cumulative_score = fresh.cumulative_score
    session.fantasy_cards = fresh.fantasy_cards
    session.bot_name = fresh.bot_name
    session.bot = fresh.bot
    session.bot_seed = fresh.bot_seed
    session.message = "Restarted at seed $(session.seed) against $(session.bot_name)."
    return session
end

html_escape(value)::String = replace(
    string(value),
    "&" => "&amp;",
    "<" => "&lt;",
    ">" => "&gt;",
    "\"" => "&quot;",
    "'" => "&#39;",
)

function suit_entity(c::Card)::String
    s = suit(c)
    s == 0 && return "&clubs;"
    s == 1 && return "&diams;"
    s == 2 && return "&hearts;"
    return "&spades;"
end

rank_label(c::Card)::String = string(RANK_CHARS[rank(c) + 1])
card_color_class(c::Card)::String = suit(c) in (1, 2) ? "red" : "black"

function render_card(c::Card; empty::Bool = false)::String
    if empty || c == EMPTY_CARD
        return "<div class=\"slot empty\"></div>"
    end

    label = html_escape(rank_label(c))
    entity = suit_entity(c)
    cls = card_color_class(c)
    return """
    <div class="playing-card $cls">
      <span class="corner">$label</span>
      <span class="suit">$entity</span>
      <span class="corner bottom">$label</span>
    </div>
    """
end

function render_row(board::PlayerBoard, row::Integer, label::AbstractString)::String
    cs = row_cards(board, row)
    cap = row_capacity(row)
    cards = String[]
    for i in 1:cap
        push!(cards, i <= length(cs) ? render_card(cs[i]) : render_card(EMPTY_CARD, empty = true))
    end

    return """
    <div class="board-row">
      <div class="row-meta">
        <span>$(html_escape(label))</span>
        <span>$(length(cs))/$cap</span>
      </div>
      <div class="card-slots row-$row">$(join(cards, ""))</div>
    </div>
    """
end

function render_board_panel(board::PlayerBoard, title::AbstractString)::String
    status = ""
    if is_complete(board)
        status = is_foul(board) ? "<span class=\"badge danger\">Foul</span>" : "<span class=\"badge ok\">Clean</span>"
    end

    return """
    <article class="board-panel">
      <header class="panel-header">
        <h2>$(html_escape(title))</h2>
        $status
      </header>
      $(render_row(board, TOP, "Top"))
      $(render_row(board, MIDDLE, "Middle"))
      $(render_row(board, BOTTOM, "Bottom"))
    </article>
    """
end

function required_placements(obs::Observation)::Int
    pcards = pending_cards(obs.pending)
    n = length(pcards)
    board = obs.boards[Int(obs.player_id)]
    slots = 13 - board_count(board)
    n > 5 && return 13
    n == slots && return n
    n == 5 && board_count(board) == 0 && return 5
    n == 3 && slots >= 2 && return 2
    throw(ArgumentError("unsupported pending count $n"))
end

function render_row_option(i::Int, value::AbstractString, label::AbstractString)::String
    input_id = "r$(i)-$(value)"
    return """
    <label class="choice" for="$input_id">
      <input id="$input_id" required type="radio" name="r$i" value="$(html_escape(value))">
      <span>$(html_escape(label))</span>
    </label>
    """
end

function render_pending_form(session::WebSession)::String
    state = session.state

    if is_terminal(state)
        score = score_hand(state)
        next_fl = next_fantasy_cards(state)
        lines = score.line_points
        return """
        <section class="action-panel terminal">
          <div class="score-grid">
            <div><span>Total</span><strong>$(score.total)</strong></div>
            <div><span>Top</span><strong>$(lines[1])</strong></div>
            <div><span>Middle</span><strong>$(lines[2])</strong></div>
            <div><span>Bottom</span><strong>$(lines[3])</strong></div>
            <div><span>Scoop</span><strong>$(score.scoop_bonus)</strong></div>
            <div><span>Royalties</span><strong>$(score.p1_royalties)-$(score.p2_royalties)</strong></div>
          </div>
          <p class="next-fl">Next Fantasyland: P1 $(Int(next_fl[1])) / P2 $(Int(next_fl[2]))</p>
          <form method="post" action="/new">
            <button class="primary-button" type="submit">Next Hand</button>
          </form>
        </section>
        """
    end

    if current_player(state) != 1
        return """
        <section class="action-panel">
          <p class="waiting">Bot is moving...</p>
        </section>
        """
    end

    obs = view_from(state, 1)
    pcards = pending_cards(obs.pending)
    own_discards = discard_cards(obs.own_discards)
    discard_text = isempty(own_discards) ? "None" : cards_string(own_discards)
    board = obs.boards[1]
    place_count = required_placements(obs)
    discard_count = length(pcards) - place_count
    caps = (
        3 - Int(board.top_count),
        5 - Int(board.middle_count),
        5 - Int(board.bottom_count),
    )

    pending_html = String[]
    for (i, c) in enumerate(pcards)
        options = String[]
        caps[1] > 0 && push!(options, render_row_option(i, "t", "Top"))
        caps[2] > 0 && push!(options, render_row_option(i, "m", "Middle"))
        caps[3] > 0 && push!(options, render_row_option(i, "b", "Bottom"))
        discard_count > 0 && push!(options, render_row_option(i, "d", "Discard"))

        push!(pending_html, """
        <div class="pending-card">
          $(render_card(c))
          <div class="choices">$(join(options, ""))</div>
        </div>
        """)
    end

    return """
    <section class="action-panel">
      <header class="action-header">
        <h2>Your Move</h2>
        <span>Place $place_count · Discard $discard_count</span>
      </header>
      <p class="discard-note">Your discards: $(html_escape(discard_text)) · Bot discards hidden: $(Int(obs.opponent_discard_count))</p>
      <form method="post" action="/act">
        <div class="pending-grid">$(join(pending_html, ""))</div>
        <button class="primary-button" type="submit">Place Cards</button>
      </form>
    </section>
    """
end

function render_page(session::WebSession)::String
    state = session.state
    message = isempty(session.message) ? "" : "<div class=\"notice\">$(html_escape(session.message))</div>"
    projected_total = session.cumulative_score + (is_terminal(state) ? Int(score_hand(state).total) : 0)

    return """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>OpenFaceChinese.jl</title>
      <style>
        :root {
          color-scheme: light;
          --felt: #0d5a43;
          --felt-dark: #063829;
          --ink: #17211d;
          --muted: #64726c;
          --panel: #f7f4eb;
          --line: #d8d0bd;
          --gold: #d5a642;
          --red: #b82832;
          --black: #151a18;
          --white: #fffdf8;
        }

        * { box-sizing: border-box; }

        body {
          margin: 0;
          min-height: 100vh;
          font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          background:
            linear-gradient(90deg, rgba(255,255,255,0.035) 1px, transparent 1px),
            linear-gradient(0deg, rgba(255,255,255,0.025) 1px, transparent 1px),
            var(--felt);
          background-size: 34px 34px;
          color: var(--ink);
        }

        .app {
          width: min(1440px, 100%);
          margin: 0 auto;
          padding: 18px;
        }

        .topbar {
          display: grid;
          grid-template-columns: 1fr auto;
          gap: 16px;
          align-items: end;
          color: var(--white);
          margin-bottom: 16px;
        }

        h1, h2, p { margin: 0; }
        h1 { font-size: 28px; font-weight: 800; letter-spacing: 0; }
        h2 { font-size: 16px; font-weight: 800; letter-spacing: 0; }

        .meta {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
          margin-top: 8px;
        }

        .pill {
          display: inline-flex;
          align-items: center;
          min-height: 28px;
          padding: 4px 9px;
          border: 1px solid rgba(255,255,255,0.28);
          border-radius: 8px;
          color: var(--white);
          background: rgba(0,0,0,0.15);
          font-size: 13px;
        }

        .reset-form {
          display: flex;
          gap: 8px;
          align-items: center;
          justify-content: flex-end;
        }

        .seed-input {
          width: 96px;
          min-height: 34px;
          border: 1px solid rgba(255,255,255,0.34);
          border-radius: 8px;
          padding: 6px 8px;
          color: var(--white);
          background: rgba(0,0,0,0.2);
        }

        .bot-input { width: 118px; }

        .secondary-button, .primary-button {
          min-height: 38px;
          border: 0;
          border-radius: 8px;
          padding: 8px 13px;
          font-weight: 800;
          cursor: pointer;
        }

        .secondary-button {
          color: var(--white);
          background: rgba(255,255,255,0.14);
          border: 1px solid rgba(255,255,255,0.28);
        }

        .primary-button {
          width: 100%;
          margin-top: 14px;
          background: var(--gold);
          color: #1e1707;
        }

        .layout {
          display: grid;
          grid-template-columns: minmax(0, 1fr) 420px;
          gap: 16px;
          align-items: start;
        }

        .boards {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: 16px;
        }

        .board-panel, .action-panel {
          background: var(--panel);
          border: 1px solid var(--line);
          border-radius: 8px;
          box-shadow: 0 18px 46px rgba(0,0,0,0.18);
        }

        .board-panel { padding: 14px; }
        .action-panel { padding: 14px; }

        .panel-header, .action-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          gap: 10px;
          margin-bottom: 12px;
        }

        .action-header span, .row-meta span:last-child {
          color: var(--muted);
          font-size: 13px;
          font-weight: 700;
        }

        .badge {
          display: inline-flex;
          align-items: center;
          min-height: 26px;
          padding: 4px 8px;
          border-radius: 8px;
          font-size: 12px;
          font-weight: 800;
        }

        .badge.ok { background: #dceade; color: #1e6338; }
        .badge.danger { background: #f4d7d6; color: #8b1d28; }

        .board-row + .board-row { margin-top: 12px; }

        .row-meta {
          display: flex;
          justify-content: space-between;
          margin-bottom: 6px;
          font-size: 13px;
          font-weight: 800;
        }

        .card-slots {
          display: grid;
          gap: 8px;
        }

        .row-1 { grid-template-columns: repeat(3, minmax(56px, 76px)); }
        .row-2, .row-3 { grid-template-columns: repeat(5, minmax(48px, 76px)); }

        .playing-card, .slot {
          aspect-ratio: 5 / 7;
          min-width: 0;
          border-radius: 8px;
        }

        .playing-card {
          position: relative;
          display: grid;
          place-items: center;
          background: var(--white);
          border: 1px solid #cfc7b7;
          box-shadow: 0 4px 10px rgba(0,0,0,0.13);
          font-weight: 900;
        }

        .playing-card.red { color: var(--red); }
        .playing-card.black { color: var(--black); }

        .corner {
          position: absolute;
          top: 6px;
          left: 7px;
          font-size: 14px;
        }

        .corner.bottom {
          top: auto;
          left: auto;
          right: 7px;
          bottom: 6px;
          transform: rotate(180deg);
        }

        .suit {
          font-family: Georgia, serif;
          font-size: 31px;
          line-height: 1;
        }

        .slot.empty {
          border: 1px dashed rgba(23,33,29,0.26);
          background: rgba(255,255,255,0.38);
        }

        .pending-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(116px, 1fr));
          gap: 12px;
        }

        .pending-card {
          display: grid;
          grid-template-columns: 62px 1fr;
          gap: 8px;
          align-items: start;
          min-width: 0;
        }

        .choices {
          display: grid;
          grid-template-columns: 1fr;
          gap: 5px;
        }

        .choice input {
          position: absolute;
          opacity: 0;
          pointer-events: none;
        }

        .choice span {
          display: flex;
          align-items: center;
          justify-content: center;
          min-height: 29px;
          border: 1px solid var(--line);
          border-radius: 8px;
          background: rgba(255,255,255,0.52);
          color: var(--ink);
          font-size: 12px;
          font-weight: 800;
          cursor: pointer;
        }

        .choice input:checked + span {
          border-color: #88651d;
          background: #f1d589;
        }

        .notice {
          margin-bottom: 12px;
          padding: 10px 12px;
          border-radius: 8px;
          background: #fff3c4;
          border: 1px solid #dec25f;
          color: #5f4710;
          font-weight: 700;
        }

        .score-grid {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: 8px;
        }

        .score-grid div {
          min-height: 58px;
          padding: 10px;
          border: 1px solid var(--line);
          border-radius: 8px;
          background: rgba(255,255,255,0.42);
        }

        .score-grid span {
          display: block;
          color: var(--muted);
          font-size: 12px;
          font-weight: 800;
        }

        .score-grid strong {
          display: block;
          margin-top: 3px;
          font-size: 22px;
        }

        .next-fl, .waiting {
          margin-top: 12px;
          color: var(--muted);
          font-weight: 700;
        }

        .discard-note {
          margin-bottom: 12px;
          color: var(--muted);
          font-size: 13px;
          font-weight: 700;
        }

        @media (max-width: 1040px) {
          .layout { grid-template-columns: 1fr; }
          .action-panel { order: -1; }
        }

        @media (max-width: 720px) {
          .app { padding: 12px; }
          .topbar { grid-template-columns: 1fr; align-items: start; }
          .reset-form { justify-content: start; }
          .boards { grid-template-columns: 1fr; }
          .row-2, .row-3 { grid-template-columns: repeat(5, minmax(42px, 1fr)); }
          .row-1 { grid-template-columns: repeat(3, minmax(48px, 1fr)); }
          .suit { font-size: 26px; }
          .corner { font-size: 12px; }
        }
      </style>
    </head>
    <body>
      <main class="app">
        <header class="topbar">
          <div>
            <h1>OpenFaceChinese.jl</h1>
            <div class="meta">
              <span class="pill">Hand $(session.hand_number)</span>
              <span class="pill">Seed $(session.seed)</span>
              <span class="pill">Round $(Int(state.round))/$(Int(NORMAL_DRAW_ROUNDS))</span>
              <span class="pill">Total $projected_total</span>
              <span class="pill">Bot $(html_escape(session.bot_name))</span>
            </div>
          </div>
          <form class="reset-form" method="post" action="/reset">
            <input class="seed-input" name="seed" type="number" value="$(session.seed)">
            <input class="seed-input bot-input" name="bot" type="text" value="$(html_escape(session.bot_name))" list="bot-options">
            <datalist id="bot-options">
              <option value="greedy">
              <option value="safe">
              <option value="royalty">
              <option value="balanced">
              <option value="ensemble">
              <option value="mc5k16">
              <option value="mc25k16">
            </datalist>
            <button class="secondary-button" type="submit">Restart</button>
          </form>
        </header>
        $message
        <div class="layout">
          <section class="boards">
            $(render_board_panel(state.boards[1], "You"))
            $(render_board_panel(state.boards[2], "$(session.bot_name) Bot"))
          </section>
          $(render_pending_form(session))
        </div>
      </main>
    </body>
    </html>
    """
end

function percent_decode(value::AbstractString)::String
    out = IOBuffer()
    i = firstindex(value)
    while i <= lastindex(value)
        c = value[i]
        if c == '+'
            write(out, UInt8(' '))
            i = nextind(value, i)
        elseif c == '%' && nextind(value, nextind(value, i)) <= lastindex(value)
            j = nextind(value, i)
            k = nextind(value, j)
            hex = value[j:k]
            write(out, UInt8(parse(Int, hex, base = 16)))
            i = nextind(value, k)
        else
            print(out, c)
            i = nextind(value, i)
        end
    end
    return String(take!(out))
end

function parse_params(value::AbstractString)::Dict{String, String}
    params = Dict{String, String}()
    isempty(value) && return params
    for pair in split(value, "&")
        isempty(pair) && continue
        parts = split(pair, "=", limit = 2)
        key = percent_decode(parts[1])
        val = length(parts) == 2 ? percent_decode(parts[2]) : ""
        params[key] = val
    end
    return params
end

function read_http_request(sock)
    request_line = strip(readline(sock))
    isempty(request_line) && return nothing
    request_parts = split(request_line, " ", limit = 3)
    length(request_parts) >= 2 || return nothing

    headers = Dict{String, String}()
    while !eof(sock)
        line = strip(readline(sock))
        isempty(line) && break
        parts = split(line, ":", limit = 2)
        length(parts) == 2 && (headers[lowercase(strip(parts[1]))] = strip(parts[2]))
    end

    len = parse(Int, get(headers, "content-length", "0"))
    body = len > 0 ? String(read(sock, len)) : ""
    target = request_parts[2]
    target_parts = split(target, "?", limit = 2)
    path = target_parts[1]
    query = length(target_parts) == 2 ? target_parts[2] : ""
    return (method = request_parts[1], path = path, query = query, body = body, headers = headers)
end

function write_response(sock, status::AbstractString, body::AbstractString; content_type::AbstractString = "text/html")
    bytes = codeunits(body)
    print(sock, "HTTP/1.1 $status\r\n")
    print(sock, "Content-Type: $content_type; charset=utf-8\r\n")
    print(sock, "Content-Length: $(length(bytes))\r\n")
    print(sock, "Connection: close\r\n\r\n")
    write(sock, bytes)
end

function redirect(sock, location::AbstractString = "/")
    body = ""
    print(sock, "HTTP/1.1 303 See Other\r\n")
    print(sock, "Location: $location\r\n")
    print(sock, "Content-Length: 0\r\n")
    print(sock, "Connection: close\r\n\r\n")
    write(sock, body)
end

function route!(session::WebSession, request, sock)
    request === nothing && return write_response(sock, "400 Bad Request", "Bad request", content_type = "text/plain")

    if request.method == "GET" && request.path == "/"
        return write_response(sock, "200 OK", render_page(session))
    elseif request.method == "GET" && request.path == "/health"
        return write_response(sock, "200 OK", "ok", content_type = "text/plain")
    elseif request.method == "GET" && request.path == "/favicon.ico"
        return write_response(sock, "204 No Content", "")
    elseif request.method == "POST" && request.path == "/act"
        params = parse_params(request.body)
        obs = view_from(session.state, 1)
        tokens = [get(params, "r$i", "") for i in 1:Int(obs.pending.count)]
        try
            apply_human_action!(session, tokens)
        catch err
            session.message = sprint(showerror, err)
        end
        return redirect(sock)
    elseif request.method == "POST" && request.path == "/new"
        start_next_hand!(session)
        return redirect(sock)
    elseif request.method == "POST" && request.path == "/reset"
        params = parse_params(request.body)
        seed = parse(Int, get(params, "seed", string(session.seed)))
        bot_name = get(params, "bot", session.bot_name)
        try
            reset!(session, seed, bot_name = bot_name)
        catch err
            session.message = sprint(showerror, err)
        end
        return redirect(sock)
    end

    return write_response(sock, "404 Not Found", "Not found", content_type = "text/plain")
end

function handle_client(session::WebSession, sock)
    try
        request = read_http_request(sock)
        route!(session, request, sock)
    catch err
        body = "Server error: $(sprint(showerror, err))"
        write_response(sock, "500 Internal Server Error", body, content_type = "text/plain")
    finally
        close(sock)
    end
end

function open_browser(url::AbstractString)
    try
        if Sys.iswindows()
            run(Cmd(["cmd", "/c", "start", "", url]))
        elseif Sys.isapple()
            run(`open $url`)
        else
            run(`xdg-open $url`)
        end
    catch
        return false
    end
    return true
end

function serve(; host::AbstractString = "127.0.0.1", port::Integer = 8088,
    seed::Integer = 1, bot_name::AbstractString = "greedy", bot_samples::Integer = 500, open::Bool = true)

    session = new_web_session(seed = seed, bot_name = bot_name, bot_samples = bot_samples)
    server = listen(Sockets.InetAddr(parse(IPAddr, host), UInt16(port)))
    url = "http://$host:$port/"
    println("OFC browser UI listening at $url against $(session.bot_name)")
    open && open_browser(url)

    while true
        sock = accept(server)
        @async handle_client(session, sock)
    end
end

end
