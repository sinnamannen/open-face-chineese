module Players

using Random
using ..Cards
using ..HandEval
using ..Engine

export Player, RandomPlayer, GreedyPlayer, SafeGreedyPlayer, RoyaltyGreedyPlayer, BalancedGreedyPlayer, EnsemblePlayer, MCRolloutPlayer, HumanPlayer
export decide, random_full_board_action, determinize_observation, render_board, render_state, play_hand, play_game, tournament

abstract type Player end

struct RandomPlayer <: Player
    rng::Random.Xoshiro
end

RandomPlayer(; seed::Integer = 1) = RandomPlayer(Random.Xoshiro(seed))

struct GreedyPlayer <: Player
    rng::Random.Xoshiro
    fantasyland_samples::Int
end

GreedyPlayer(; seed::Integer = 2, fantasyland_samples::Integer = 2_000) =
    GreedyPlayer(Random.Xoshiro(seed), Int(fantasyland_samples))

struct HeuristicProfile
    safety_weight::Float64
    royalty_weight::Float64
    fantasyland_weight::Float64
    top_weight::Float64
    middle_weight::Float64
    bottom_weight::Float64
end

const SAFE_PROFILE = HeuristicProfile(28.0, 0.7, 1.0, 0.55, 1.05, 1.35)
const ROYALTY_PROFILE = HeuristicProfile(8.0, 2.6, 3.2, 1.25, 1.2, 1.0)
const BALANCED_PROFILE = HeuristicProfile(15.0, 1.5, 2.0, 0.9, 1.1, 1.2)
const ENSEMBLE_PROFILES = (SAFE_PROFILE, ROYALTY_PROFILE, BALANCED_PROFILE)

struct SafeGreedyPlayer <: Player
    rng::Random.Xoshiro
    fantasyland_samples::Int
end

SafeGreedyPlayer(; seed::Integer = 3, fantasyland_samples::Integer = 2_000) =
    SafeGreedyPlayer(Random.Xoshiro(seed), Int(fantasyland_samples))

struct RoyaltyGreedyPlayer <: Player
    rng::Random.Xoshiro
    fantasyland_samples::Int
end

RoyaltyGreedyPlayer(; seed::Integer = 4, fantasyland_samples::Integer = 2_000) =
    RoyaltyGreedyPlayer(Random.Xoshiro(seed), Int(fantasyland_samples))

struct BalancedGreedyPlayer <: Player
    rng::Random.Xoshiro
    fantasyland_samples::Int
end

BalancedGreedyPlayer(; seed::Integer = 5, fantasyland_samples::Integer = 2_000) =
    BalancedGreedyPlayer(Random.Xoshiro(seed), Int(fantasyland_samples))

struct EnsemblePlayer <: Player
    rng::Random.Xoshiro
    fantasyland_samples::Int
end

EnsemblePlayer(; seed::Integer = 6, fantasyland_samples::Integer = 2_000) =
    EnsemblePlayer(Random.Xoshiro(seed), Int(fantasyland_samples))

struct MCRolloutPlayer <: Player
    rng::Random.Xoshiro
    n_rollouts::Int
    top_k::Int
end

MCRolloutPlayer(; seed::Integer = 7, n_rollouts::Integer = 100, top_k::Integer = 16) =
    MCRolloutPlayer(Random.Xoshiro(seed), Int(n_rollouts), Int(top_k))

struct HumanPlayer <: Player end

function assert_turn(obs::Observation)
    obs.current_player == obs.player_id ||
        throw(ArgumentError("observation is for player $(obs.player_id), but current player is $(obs.current_player)"))
end

function random_full_board_action(rng::AbstractRNG, obs::Observation)::PlacementAction
    pcards = pending_cards(obs.pending)
    length(pcards) >= 13 || throw(ArgumentError("full-board action needs at least 13 pending cards"))
    shuffled = shuffle(rng, pcards)
    return full_board_action(shuffled[1:3], shuffled[4:8], shuffled[9:13], shuffled[14:end])
end

function decide(player::RandomPlayer, obs::Observation)::PlacementAction
    assert_turn(obs)
    length(pending_cards(obs.pending)) > 5 && return random_full_board_action(player.rng, obs)
    actions = legal_actions(obs)
    isempty(actions) && throw(ArgumentError("no legal actions"))
    return rand(player.rng, actions)
end

function observation_known_mask(obs::Observation)::UInt64
    mask = UInt64(0)
    for board in obs.boards
        for c in all_board_cards(board)
            mask |= card_mask(c)
        end
    end
    for c in pending_cards(obs.pending)
        mask |= card_mask(c)
    end
    for c in discard_cards(obs.own_discards)
        mask |= card_mask(c)
    end
    return mask
end

function determinize_observation(obs::Observation, rng::AbstractRNG)::GameState
    pid = Int(obs.player_id)
    opp = 3 - pid
    unknown = FULL_DECK & ~observation_known_mask(obs)

    hidden_pending, unknown = draw(unknown, rng, Int(obs.opponent_pending_count))
    hidden_discards, deck = draw(unknown, rng, Int(obs.opponent_discard_count))

    pending = Vector{PendingCards}(undef, 2)
    discards = Vector{DiscardPile}(undef, 2)
    pending[pid] = obs.pending
    pending[opp] = PendingCards(hidden_pending)
    discards[pid] = obs.own_discards
    discards[opp] = DiscardPile(hidden_discards)

    return GameState(obs.boards, deck, (pending[1], pending[2]), (discards[1], discards[2]),
        obs.current_player, obs.round, obs.fantasy_cards, Random.Xoshiro(rand(rng, UInt64)))
end

function random_rollout_value(state::GameState, player_id::Integer, seed::Integer)::Int
    rollout_state = state
    players = (
        RandomPlayer(seed = seed + 1),
        RandomPlayer(seed = seed + 2),
    )

    steps = 0
    while !is_terminal(rollout_state)
        steps += 1
        steps <= 20 || throw(ErrorException("rollout did not terminate after 20 actions"))
        pid = current_player(rollout_state)
        action = decide(players[pid], view_from(rollout_state, pid))
        rollout_state = Engine.apply(rollout_state, action)
    end

    total = Int(score_hand(rollout_state).total)
    return player_id == 1 ? total : -total
end

function mc_action_score(obs::Observation, action::PlacementAction)::Float64
    board = apply_action_to_board(obs.boards[Int(obs.player_id)], action)
    return contextual_ensemble_value(obs, board)
end

function top_scored_actions(obs::Observation, actions::Vector{PlacementAction}, top_k::Integer)::Vector{PlacementAction}
    isempty(actions) && return actions
    top_k <= 0 && return actions
    length(actions) <= top_k && return actions

    scores = [mc_action_score(obs, action) for action in actions]
    order = sortperm(scores, rev = true)
    return actions[order[1:Int(top_k)]]
end

function mc_candidate_actions(player::MCRolloutPlayer, obs::Observation)::Vector{PlacementAction}
    if length(pending_cards(obs.pending)) > 5
        samples = player.top_k <= 0 ? min(player.n_rollouts, 128) : min(max(player.top_k, player.n_rollouts), 256)
        actions = [random_full_board_action(player.rng, obs) for _ in 1:max(samples, 1)]
        return top_scored_actions(obs, actions, player.top_k)
    end
    return top_scored_actions(obs, legal_actions(obs), player.top_k)
end

function decide(player::MCRolloutPlayer, obs::Observation)::PlacementAction
    assert_turn(obs)
    player.n_rollouts > 0 || throw(ArgumentError("MCRolloutPlayer requires at least one rollout"))
    actions = mc_candidate_actions(player, obs)
    isempty(actions) && throw(ArgumentError("no legal actions"))

    det_seeds = [rand(player.rng, UInt64) for _ in 1:player.n_rollouts]
    rollout_seeds = [rand(player.rng, 1:typemax(Int32)) for _ in 1:player.n_rollouts]
    totals = zeros(Float64, length(actions))

    for rollout_idx in 1:player.n_rollouts
        det_rng = Random.Xoshiro(det_seeds[rollout_idx])
        determined = determinize_observation(obs, det_rng)
        for (action_idx, action) in enumerate(actions)
            after_action = Engine.apply(determined, action)
            totals[action_idx] += random_rollout_value(after_action, Int(obs.player_id), rollout_seeds[rollout_idx])
        end
    end

    best_idx = argmax(totals)
    return actions[best_idx]
end

function partial_row_value(cs, row::Integer)::Float64
    isempty(cs) && return 0.0
    value = sum(rank_value(c) for c in cs) / 20
    if row == TOP && length(cs) == 3
        value += category(evaluate3(cs)) * 20 + top_royalty(cs) * 10
    elseif row != TOP && length(cs) == 5
        score = evaluate5(cs)
        value += category(score) * 20 + line_royalty(row, cs) * 10
    end
    return value
end

function board_value(board::PlayerBoard)::Float64
    if is_complete(board)
        is_foul(board) && return -1.0e9
    end

    return partial_row_value(row_cards(board, TOP), TOP) +
        partial_row_value(row_cards(board, MIDDLE), MIDDLE) +
        partial_row_value(row_cards(board, BOTTOM), BOTTOM)
end

function rank_groups(cs)
    counts = Dict{Int, Int}()
    for c in cs
        r = rank(c)
        counts[r] = get(counts, r, 0) + 1
    end
    return counts
end

function group_value(cs)::Float64
    isempty(cs) && return 0.0
    counts = rank_groups(cs)
    value = 0.0
    for (r, count) in counts
        count == 2 && (value += 1.3 + r / 12)
        count == 3 && (value += 4.2 + 1.5 * r / 12)
        count == 4 && (value += 8.0 + 2.0 * r / 12)
    end
    return value
end

function suit_potential(cs)::Float64
    length(cs) < 2 && return 0.0
    counts = zeros(Int, 4)
    for c in cs
        counts[suit(c) + 1] += 1
    end
    best = maximum(counts)
    return best >= 5 ? 5.0 : best == 4 ? 2.7 : best == 3 ? 0.9 : 0.0
end

function straight_potential(cs)::Float64
    length(cs) < 3 && return 0.0
    rs = unique(rank.(cs))
    12 in rs && push!(rs, -1)
    best = 1
    for start in -1:8
        run = count(r -> start <= r <= start + 4, rs)
        best = max(best, run)
    end
    return best >= 5 ? 4.0 : best == 4 ? 1.8 : best == 3 ? 0.5 : 0.0
end

function partial_strength(cs, row::Integer)::Float64
    isempty(cs) && return 0.0

    if row == TOP
        if length(cs) == 3
            score = evaluate3(cs)
            return 3.0 * category(score) + Float64(kicker_tuple(score)[1]) / 12
        end
        base = sum(rank(c) for c in cs) / (18 * length(cs))
        return base + group_value(cs)
    end

    if length(cs) == 5
        score = evaluate5(cs)
        return 3.0 * category(score) + Float64(kicker_tuple(score)[1]) / 12
    end

    density = length(cs) / row_capacity(row)
    high = sum(rank(c) for c in cs) / (20 * max(length(cs), 1))
    return density + high + group_value(cs) + suit_potential(cs) + straight_potential(cs)
end

function royalty_signal(cs, row::Integer)::Float64
    if row == TOP
        exact = top_royalty(cs)
        exact > 0 && return exact
        counts = rank_groups(cs)
        value = 0.0
        for (r, count) in counts
            if count == 2 && r >= 4
                value += 0.55 * (r - 3)
            elseif count == 1 && r >= 10 && length(cs) < 3
                value += 0.35 * (r - 9)
            end
        end
        return value
    end

    exact = line_royalty(row, cs)
    exact > 0 && return exact
    return 0.55 * group_value(cs) + 0.45 * suit_potential(cs) + 0.35 * straight_potential(cs)
end

function fantasyland_signal(board::PlayerBoard)::Float64
    top = row_cards(board, TOP)
    isempty(top) && return 0.0
    counts = rank_groups(top)
    value = 0.0

    if length(top) == 3
        is_complete(board) && !is_foul(board) && return Float64(fantasyland_card_count(board))
        for (r, count) in counts
            count == 3 && return 17.0
            count == 2 && r >= 10 && return 14.0 + (r - 10)
        end
        return 0.0
    end

    for (r, count) in counts
        count == 2 && r >= 10 && (value += 8.0 + r - 10)
        count == 1 && r >= 10 && (value += 1.2 + 0.3 * (r - 10))
    end
    return value
end

function foul_risk(board::PlayerBoard)::Float64
    if is_complete(board)
        return is_foul(board) ? 100.0 : 0.0
    end

    top = partial_strength(row_cards(board, TOP), TOP)
    middle = partial_strength(row_cards(board, MIDDLE), MIDDLE)
    bottom = partial_strength(row_cards(board, BOTTOM), BOTTOM)
    middle_gap = max(0.0, top - middle)
    bottom_gap = max(0.0, middle - bottom)
    return middle_gap^2 + bottom_gap^2
end

function opponent_pressure(obs::Observation, board::PlayerBoard, profile::HeuristicProfile)::Float64
    opponent = obs.boards[3 - Int(obs.player_id)]
    board_count(opponent) == 0 && return 0.0

    value = 0.0
    for (row, weight) in ((TOP, profile.top_weight), (MIDDLE, profile.middle_weight), (BOTTOM, profile.bottom_weight))
        own_cards = row_cards(board, row)
        opp_cards = row_cards(opponent, row)
        if isempty(own_cards) || isempty(opp_cards)
            continue
        end
        value += weight * (partial_strength(own_cards, row) - partial_strength(opp_cards, row))
    end
    return value
end

function discard_memory_adjustment(obs::Observation, board::PlayerBoard)::Float64
    dead = discard_cards(obs.own_discards)
    isempty(dead) && return 0.0

    penalty = 0.0
    for row in (TOP, MIDDLE, BOTTOM)
        cs = row_cards(board, row)
        isempty(cs) && continue
        counts = rank_groups(cs)

        if row == TOP && length(cs) < 3
            for (r, n) in counts
                n >= 2 && (penalty += 1.2 * count(c -> rank(c) == r, dead))
            end
        elseif row != TOP && length(cs) < 5
            suit_counts = zeros(Int, 4)
            for c in cs
                suit_counts[suit(c) + 1] += 1
            end
            best_suit = argmax(suit_counts) - 1
            if maximum(suit_counts) >= 3
                penalty += 0.45 * count(c -> suit(c) == best_suit, dead)
            end
            for (r, n) in counts
                n >= 2 && (penalty += 0.35 * count(c -> rank(c) == r, dead))
            end
        end
    end

    return -penalty
end

function heuristic_board_value(board::PlayerBoard, profile::HeuristicProfile)::Float64
    if is_complete(board) && is_foul(board)
        return -1.0e9
    end

    top = row_cards(board, TOP)
    middle = row_cards(board, MIDDLE)
    bottom = row_cards(board, BOTTOM)
    value =
        profile.top_weight * partial_strength(top, TOP) +
        profile.middle_weight * partial_strength(middle, MIDDLE) +
        profile.bottom_weight * partial_strength(bottom, BOTTOM)

    value += profile.royalty_weight * (
        royalty_signal(top, TOP) +
        royalty_signal(middle, MIDDLE) +
        royalty_signal(bottom, BOTTOM)
    )
    value += profile.fantasyland_weight * fantasyland_signal(board)
    value -= profile.safety_weight * foul_risk(board)
    return value
end

function contextual_board_value(obs::Observation, board::PlayerBoard)::Float64
    return board_value(board) +
        0.45 * opponent_pressure(obs, board, BALANCED_PROFILE) +
        0.35 * discard_memory_adjustment(obs, board)
end

function contextual_heuristic_value(obs::Observation, board::PlayerBoard, profile::HeuristicProfile)::Float64
    return heuristic_board_value(board, profile) +
        0.85 * opponent_pressure(obs, board, profile) +
        0.75 * discard_memory_adjustment(obs, board)
end

function contextual_ensemble_value(obs::Observation, board::PlayerBoard)::Float64
    return sum(contextual_heuristic_value(obs, board, profile) for profile in ENSEMBLE_PROFILES)
end

function best_sampled_full_board(rng::AbstractRNG, obs::Observation, value_fn::Function, samples::Int)::PlacementAction
    best_action = random_full_board_action(rng, obs)
    best_value = value_fn(apply_action_to_board(obs.boards[Int(obs.player_id)], best_action))
    for _ in 2:max(samples, 2)
        action = random_full_board_action(rng, obs)
        candidate = apply_action_to_board(obs.boards[Int(obs.player_id)], action)
        value = value_fn(candidate)
        if value > best_value
            best_value = value
            best_action = action
        end
    end
    return best_action
end

function best_legal_action(obs::Observation, value_fn::Function)::PlacementAction
    actions = legal_actions(obs)
    isempty(actions) && throw(ArgumentError("no legal actions"))

    board = obs.boards[Int(obs.player_id)]
    best_action = actions[1]
    best_value = value_fn(apply_action_to_board(board, best_action))
    for action in actions[2:end]
        candidate = apply_action_to_board(board, action)
        value = value_fn(candidate)
        if value > best_value
            best_value = value
            best_action = action
        end
    end
    return best_action
end

function heuristic_decide(rng::AbstractRNG, obs::Observation, profile::HeuristicProfile, samples::Int)::PlacementAction
    assert_turn(obs)
    value_fn = board -> contextual_heuristic_value(obs, board, profile)
    length(pending_cards(obs.pending)) > 5 && return best_sampled_full_board(rng, obs, value_fn, samples)
    return best_legal_action(obs, value_fn)
end

function decide(player::GreedyPlayer, obs::Observation)::PlacementAction
    assert_turn(obs)
    pcards = pending_cards(obs.pending)
    value_fn = board -> contextual_board_value(obs, board)

    if length(pcards) > 5
        return best_sampled_full_board(player.rng, obs, value_fn, player.fantasyland_samples)
    end

    return best_legal_action(obs, value_fn)
end

decide(player::SafeGreedyPlayer, obs::Observation)::PlacementAction =
    heuristic_decide(player.rng, obs, SAFE_PROFILE, player.fantasyland_samples)

decide(player::RoyaltyGreedyPlayer, obs::Observation)::PlacementAction =
    heuristic_decide(player.rng, obs, ROYALTY_PROFILE, player.fantasyland_samples)

decide(player::BalancedGreedyPlayer, obs::Observation)::PlacementAction =
    heuristic_decide(player.rng, obs, BALANCED_PROFILE, player.fantasyland_samples)

function decide(player::EnsemblePlayer, obs::Observation)::PlacementAction
    assert_turn(obs)
    length(pending_cards(obs.pending)) > 5 &&
        return best_sampled_full_board(player.rng, obs, board -> contextual_ensemble_value(obs, board), player.fantasyland_samples)
    return best_legal_action(obs, board -> contextual_ensemble_value(obs, board))
end

function parse_row_token(token::AbstractString)::UInt8
    t = lowercase(strip(token))
    isempty(t) && throw(ArgumentError("empty row token"))
    c = first(t)
    c == 't' && return TOP
    c == 'm' && return MIDDLE
    c == 'b' && return BOTTOM
    c == 'd' && return UInt8(0)
    throw(ArgumentError("row token must be t, m, b, or d"))
end

function decide(::HumanPlayer, obs::Observation)::PlacementAction
    assert_turn(obs)
    pcards = pending_cards(obs.pending)

    while true
        println()
        println("Pending: ", join(["$(i):$(card_string(c))" for (i, c) in enumerate(pcards)], "  "))
        println("Enter one token per pending card: t, m, b, or d.")
        print("> ")
        line = readline()
        tokens = split(line)
        if length(tokens) != length(pcards)
            println("Expected $(length(pcards)) tokens.")
            continue
        end

        placements = Placement[]
        discards = Card[]
        try
            for (c, token) in zip(pcards, tokens)
                row = parse_row_token(token)
                row == 0 ? push!(discards, c) : push!(placements, Placement(c, row))
            end
            action = PlacementAction(placements, discards)
            Engine.validate_action(obs.boards[Int(obs.player_id)], obs.pending, action)
            return action
        catch err
            println("Invalid action: ", err)
        end
    end
end

function padded_cards(cs, width::Int)::Vector{String}
    out = card_string.(cs)
    while length(out) < width
        push!(out, "--")
    end
    return out
end

function render_board(board::PlayerBoard)::String
    top = join(padded_cards(row_cards(board, TOP), 3), " ")
    middle = join(padded_cards(row_cards(board, MIDDLE), 5), " ")
    bottom = join(padded_cards(row_cards(board, BOTTOM), 5), " ")
    return "T  $top\nM  $middle\nB  $bottom"
end

function render_state(state::GameState; reveal_pending::Bool = false)::String
    lines = String[]
    push!(lines, "Round $(state.round)/$(NORMAL_DRAW_ROUNDS), current player: $(state.current_player == 0 ? "terminal" : string(state.current_player))")
    for pid in 1:2
        push!(lines, "")
        push!(lines, "Player $pid")
        push!(lines, render_board(state.boards[pid]))
        if reveal_pending || pid == state.current_player
            pending = pending_cards(state.pending[pid])
            !isempty(pending) && push!(lines, "Pending: $(cards_string(pending))")
            discards = discard_cards(state.discards[pid])
            !isempty(discards) && push!(lines, "Discards: $(cards_string(discards))")
        else
            state.pending[pid].count > 0 && push!(lines, "Pending: $(state.pending[pid].count) hidden")
            state.discards[pid].count > 0 && push!(lines, "Discards: $(state.discards[pid].count) hidden")
        end
    end
    return join(lines, "\n")
end

function play_hand(p1::Player, p2::Player; seed::Integer = 1, fantasy_cards = (0, 0))
    state = new_hand(seed = seed, fantasy_cards = fantasy_cards)
    players = (p1, p2)
    steps = 0
    while !is_terminal(state)
        steps += 1
        steps <= 20 || throw(ErrorException("hand did not terminate after 20 actions"))
        pid = current_player(state)
        obs = view_from(state, pid)
        action = decide(players[pid], obs)
        state = Engine.apply(state, action)
    end
    return (state = state, score = score_hand(state), next_fantasy_cards = next_fantasy_cards(state))
end

play_game(p1::Player, p2::Player; seed::Integer = 1, fantasy_cards = (0, 0)) =
    play_hand(p1, p2, seed = seed, fantasy_cards = fantasy_cards)

function tournament(p1_factory::Function, p2_factory::Function, n::Integer; seed::Integer = 1)
    scores = Vector{Int}(undef, n)
    for i in 1:n
        result = play_hand(p1_factory(i), p2_factory(i), seed = seed + i - 1)
        scores[i] = result.score.total
    end
    return (mean = sum(scores) / n, scores = scores)
end

end
