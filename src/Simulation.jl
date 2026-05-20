module Simulation

using ..Engine
using ..Players

export GameRecord, MatchupResult
export player_factory, run_matchup, summarize_scores, format_matchup_report

struct GameRecord
    index::Int
    seed::Int
    score::Int
    line_points::NTuple{3, Int8}
    scoop_bonus::Int8
    p1_royalties::Int16
    p2_royalties::Int16
    fouls::NTuple{2, Bool}
    next_fantasy_cards::NTuple{2, UInt8}
end

struct MatchupResult
    p1_name::String
    p2_name::String
    n::Int
    seed::Int
    elapsed_seconds::Float64
    records::Vector{GameRecord}
end

function parse_mc_rollout_name(key::AbstractString, default_rollouts::Integer)
    key in ("mc", "mcrollout", "mc-rollout") && return (Int(default_rollouts), 16)

    m = match(r"^mc(?:rollout)?[-_]?([0-9]+)(?:k([0-9]+))?$", key)
    m === nothing && return nothing

    n_rollouts = parse(Int, m.captures[1])
    top_k = m.captures[2] === nothing ? 16 : parse(Int, m.captures[2])
    return (n_rollouts, top_k)
end

function player_factory(name::AbstractString; seed_offset::Integer = 0, greedy_samples::Integer = 500)
    key = lowercase(strip(name))
    if key in ("random", "rand")
        return i -> RandomPlayer(seed = 10_000_000 + seed_offset + i)
    elseif key in ("greedy", "greedyplayer")
        return i -> GreedyPlayer(seed = 20_000_000 + seed_offset + i, fantasyland_samples = greedy_samples)
    elseif key in ("safe", "safegreedy", "safe-greedy")
        return i -> SafeGreedyPlayer(seed = 30_000_000 + seed_offset + i, fantasyland_samples = greedy_samples)
    elseif key in ("royalty", "royaltygreedy", "royalty-greedy")
        return i -> RoyaltyGreedyPlayer(seed = 40_000_000 + seed_offset + i, fantasyland_samples = greedy_samples)
    elseif key in ("balanced", "balancedgreedy", "balanced-greedy")
        return i -> BalancedGreedyPlayer(seed = 50_000_000 + seed_offset + i, fantasyland_samples = greedy_samples)
    elseif key in ("ensemble", "greedy+", "greedyplus")
        return i -> EnsemblePlayer(seed = 60_000_000 + seed_offset + i, fantasyland_samples = greedy_samples)
    end

    mc_config = parse_mc_rollout_name(key, greedy_samples)
    if mc_config !== nothing
        n_rollouts, top_k = mc_config
        return i -> MCRolloutPlayer(seed = 70_000_000 + seed_offset + i, n_rollouts = n_rollouts, top_k = top_k)
    end

    throw(ArgumentError("unknown player '$name'; use random, greedy, safe, royalty, balanced, ensemble, mc, mc<N>, or mc<N>k<K>"))
end

function make_record(i::Int, seed::Int, result)::GameRecord
    score = result.score
    return GameRecord(
        i,
        seed,
        Int(score.total),
        score.line_points,
        score.scoop_bonus,
        score.p1_royalties,
        score.p2_royalties,
        score.fouls,
        result.next_fantasy_cards,
    )
end

function run_matchup(p1_factory::Function, p2_factory::Function, n::Integer;
    seed::Integer = 1, p1_name::AbstractString = "Player 1", p2_name::AbstractString = "Player 2")

    n > 0 || throw(ArgumentError("number of games must be positive"))
    records = Vector{GameRecord}(undef, n)
    start = time_ns()
    for i in 1:n
        hand_seed = Int(seed + i - 1)
        result = play_hand(p1_factory(i), p2_factory(i), seed = hand_seed)
        records[i] = make_record(i, hand_seed, result)
    end
    elapsed = (time_ns() - start) / 1.0e9
    return MatchupResult(String(p1_name), String(p2_name), Int(n), Int(seed), elapsed, records)
end

function run_matchup(p1_name::AbstractString, p2_name::AbstractString, n::Integer;
    seed::Integer = 1, greedy_samples::Integer = 500)

    p1 = player_factory(p1_name, seed_offset = 0, greedy_samples = greedy_samples)
    p2 = player_factory(p2_name, seed_offset = 5_000_000, greedy_samples = greedy_samples)
    return run_matchup(p1, p2, n, seed = seed, p1_name = p1_name, p2_name = p2_name)
end

function mean_value(xs)::Float64
    isempty(xs) && return NaN
    return sum(xs) / length(xs)
end

function sample_std(xs, mean_score::Float64)::Float64
    length(xs) <= 1 && return 0.0
    acc = 0.0
    for x in xs
        acc += (x - mean_score)^2
    end
    return sqrt(acc / (length(xs) - 1))
end

function summarize_scores(records::AbstractVector{GameRecord})
    scores = [r.score for r in records]
    n = length(scores)
    mean_score = mean_value(scores)
    std_score = sample_std(scores, mean_score)
    stderr = n > 0 ? std_score / sqrt(n) : NaN
    ci95 = 1.96 * stderr
    wins = count(>(0), scores)
    losses = count(<(0), scores)
    ties = count(==(0), scores)

    p1_fouls = count(r -> r.fouls[1] && !r.fouls[2], records)
    p2_fouls = count(r -> !r.fouls[1] && r.fouls[2], records)
    both_foul = count(r -> r.fouls[1] && r.fouls[2], records)
    p1_fl = count(r -> r.next_fantasy_cards[1] > 0, records)
    p2_fl = count(r -> r.next_fantasy_cards[2] > 0, records)

    return (
        n = n,
        total = sum(scores),
        mean = mean_score,
        std = std_score,
        stderr = stderr,
        ci95 = ci95,
        min = minimum(scores),
        max = maximum(scores),
        wins = wins,
        losses = losses,
        ties = ties,
        p1_fouls = p1_fouls,
        p2_fouls = p2_fouls,
        both_foul = both_foul,
        p1_fantasyland = p1_fl,
        p2_fantasyland = p2_fl,
    )
end

percent(part::Integer, total::Integer)::Float64 = total == 0 ? 0.0 : 100 * part / total
fmt(x::Real; digits::Integer = 3)::String = string(round(Float64(x), digits = digits))
signed_fmt(x::Real; digits::Integer = 3)::String = x >= 0 ? "+" * fmt(x, digits = digits) : fmt(x, digits = digits)

function format_matchup_report(result::MatchupResult)::String
    s = summarize_scores(result.records)
    games_per_sec = result.elapsed_seconds > 0 ? result.n / result.elapsed_seconds : Inf
    ci_low = s.mean - s.ci95
    ci_high = s.mean + s.ci95
    p1_rate = percent(s.wins, s.n)
    p2_rate = percent(s.losses, s.n)
    tie_rate = percent(s.ties, s.n)

    lines = String[]
    push!(lines, "OFC Pineapple matchup")
    push!(lines, "Players: $(result.p1_name) (P1) vs $(result.p2_name) (P2)")
    push!(lines, "Games: $(result.n), seeds: $(result.seed)-$(result.seed + result.n - 1)")
    push!(lines, "Elapsed: $(fmt(result.elapsed_seconds, digits = 2))s ($(fmt(games_per_sec, digits = 1)) games/sec)")
    push!(lines, "")
    push!(lines, "Score is from P1 perspective.")
    push!(lines, "Total score: $(s.total)")
    push!(lines, "Mean score/hand: $(signed_fmt(s.mean))")
    push!(lines, "95% CI: [$(signed_fmt(ci_low)), $(signed_fmt(ci_high))]")
    push!(lines, "Std dev: $(fmt(s.std)), min/max: $(s.min) / $(s.max)")
    push!(lines, "")
    push!(lines, "Outcomes by hand:")
    push!(lines, "  P1 wins: $(s.wins) ($(fmt(p1_rate, digits = 1))%)")
    push!(lines, "  P2 wins: $(s.losses) ($(fmt(p2_rate, digits = 1))%)")
    push!(lines, "  Ties: $(s.ties) ($(fmt(tie_rate, digits = 1))%)")
    push!(lines, "")
    push!(lines, "Rule events:")
    push!(lines, "  Fouls: P1 $(s.p1_fouls), P2 $(s.p2_fouls), both $(s.both_foul)")
    push!(lines, "  Fantasyland next hand: P1 $(s.p1_fantasyland), P2 $(s.p2_fantasyland)")
    return join(lines, "\n")
end

end
