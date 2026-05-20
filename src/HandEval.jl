module HandEval

using ..Cards

export HIGH_CARD, ONE_PAIR, TWO_PAIR, TRIPS, STRAIGHT, FLUSH, FULL_HOUSE, QUADS, STRAIGHT_FLUSH
export CATEGORY_NAMES, evaluate5, evaluate3, category, kicker_tuple
export compare5, compare3, top_royalty, middle_royalty, bottom_royalty
export line_royalty, total_royalties, is_royal

const HIGH_CARD = 0
const ONE_PAIR = 1
const TWO_PAIR = 2
const TRIPS = 3
const STRAIGHT = 4
const FLUSH = 5
const FULL_HOUSE = 6
const QUADS = 7
const STRAIGHT_FLUSH = 8

const CATEGORY_NAMES = (
    "High card",
    "One pair",
    "Two pair",
    "Trips",
    "Straight",
    "Flush",
    "Full house",
    "Quads",
    "Straight flush",
)

const SCORE_BASE = UInt32(13)
const SCORE_SCALE = UInt32(13^5)

@inline function pack_score(cat::Integer, ranks)::UInt32
    length(ranks) == 5 || throw(ArgumentError("score rank tuple must have 5 entries"))
    score = UInt32(cat)
    @inbounds for r in ranks
        score = score * SCORE_BASE + UInt32(r)
    end
    return score
end

@inline category(score::UInt32)::Int = Int(score ÷ SCORE_SCALE)

function kicker_tuple(score::UInt32)::NTuple{5, UInt8}
    rest = score % SCORE_SCALE
    out = Vector{UInt8}(undef, 5)
    for i in 5:-1:1
        out[i] = UInt8(rest % SCORE_BASE)
        rest ÷= SCORE_BASE
    end
    return (out[1], out[2], out[3], out[4], out[5])
end

function rank_histogram(cs)::NTuple{13, UInt8}
    counts = zeros(UInt8, 13)
    for c in cs
        counts[rank(c) + 1] += UInt8(1)
    end
    return Tuple(counts)
end

function ranks_desc(cs)::Vector{UInt8}
    rs = UInt8[UInt8(rank(c)) for c in cs]
    sort!(rs, rev = true)
    return rs
end

function straight_high_from_counts(counts::NTuple{13, UInt8})::Int
    # Wheel: A-2-3-4-5, with 5 as the high rank (rank index 3).
    if counts[13] > 0 && counts[1] > 0 && counts[2] > 0 && counts[3] > 0 && counts[4] > 0
        return 3
    end

    for high in 12:-1:4
        ok = true
        for r in (high - 4):high
            if counts[r + 1] == 0
                ok = false
                break
            end
        end
        ok && return high
    end
    return -1
end

function grouped_ranks(counts::NTuple{13, UInt8}, n::Integer)::Vector{UInt8}
    out = UInt8[]
    for r in 12:-1:0
        counts[r + 1] == n && push!(out, UInt8(r))
    end
    return out
end

function evaluate5(cs)::UInt32
    length(cs) == 5 || throw(ArgumentError("5-card evaluator got $(length(cs)) cards"))

    counts = rank_histogram(cs)
    flush = all(suit(c) == suit(cs[1]) for c in cs)
    straight_high = straight_high_from_counts(counts)

    if flush && straight_high >= 0
        return pack_score(STRAIGHT_FLUSH, (UInt8(straight_high), 0, 0, 0, 0))
    end

    quads = grouped_ranks(counts, 4)
    if !isempty(quads)
        kicker = first(grouped_ranks(counts, 1))
        return pack_score(QUADS, (quads[1], kicker, 0, 0, 0))
    end

    trips = grouped_ranks(counts, 3)
    pairs = grouped_ranks(counts, 2)
    if !isempty(trips) && !isempty(pairs)
        return pack_score(FULL_HOUSE, (trips[1], pairs[1], 0, 0, 0))
    end

    if flush
        rs = ranks_desc(cs)
        return pack_score(FLUSH, (rs[1], rs[2], rs[3], rs[4], rs[5]))
    end

    if straight_high >= 0
        return pack_score(STRAIGHT, (UInt8(straight_high), 0, 0, 0, 0))
    end

    if !isempty(trips)
        kickers = grouped_ranks(counts, 1)
        return pack_score(TRIPS, (trips[1], kickers[1], kickers[2], 0, 0))
    end

    if length(pairs) == 2
        kicker = first(grouped_ranks(counts, 1))
        return pack_score(TWO_PAIR, (pairs[1], pairs[2], kicker, 0, 0))
    end

    if length(pairs) == 1
        kickers = grouped_ranks(counts, 1)
        return pack_score(ONE_PAIR, (pairs[1], kickers[1], kickers[2], kickers[3], 0))
    end

    rs = ranks_desc(cs)
    return pack_score(HIGH_CARD, (rs[1], rs[2], rs[3], rs[4], rs[5]))
end

function evaluate3(cs)::UInt32
    length(cs) == 3 || throw(ArgumentError("3-card evaluator got $(length(cs)) cards"))

    counts = rank_histogram(cs)
    trips = grouped_ranks(counts, 3)
    if !isempty(trips)
        return pack_score(TRIPS, (trips[1], 0, 0, 0, 0))
    end

    pairs = grouped_ranks(counts, 2)
    if !isempty(pairs)
        kicker = first(grouped_ranks(counts, 1))
        return pack_score(ONE_PAIR, (pairs[1], kicker, 0, 0, 0))
    end

    rs = ranks_desc(cs)
    return pack_score(HIGH_CARD, (rs[1], rs[2], rs[3], 0, 0))
end

@inline compare5(a, b)::Int = sign(Int(evaluate5(a)) - Int(evaluate5(b)))
@inline compare3(a, b)::Int = sign(Int(evaluate3(a)) - Int(evaluate3(b)))

function is_royal(score::UInt32)::Bool
    category(score) == STRAIGHT_FLUSH || return false
    return kicker_tuple(score)[1] == UInt8(12)
end

function top_royalty(cs)::Int
    length(cs) == 3 || return 0
    counts = rank_histogram(cs)

    for r in 12:-1:0
        if counts[r + 1] == 3
            return 10 + r
        end
    end

    for r in 12:-1:4
        if counts[r + 1] == 2
            return r - 3
        end
    end

    return 0
end

function middle_royalty(cs)::Int
    length(cs) == 5 || return 0
    score = evaluate5(cs)
    cat = category(score)
    if is_royal(score)
        return 50
    elseif cat == STRAIGHT_FLUSH
        return 30
    elseif cat == QUADS
        return 20
    elseif cat == FULL_HOUSE
        return 12
    elseif cat == FLUSH
        return 8
    elseif cat == STRAIGHT
        return 4
    elseif cat == TRIPS
        return 2
    else
        return 0
    end
end

function bottom_royalty(cs)::Int
    length(cs) == 5 || return 0
    score = evaluate5(cs)
    cat = category(score)
    if is_royal(score)
        return 25
    elseif cat == STRAIGHT_FLUSH
        return 15
    elseif cat == QUADS
        return 10
    elseif cat == FULL_HOUSE
        return 6
    elseif cat == FLUSH
        return 4
    elseif cat == STRAIGHT
        return 2
    else
        return 0
    end
end

function line_royalty(row::Integer, cs)::Int
    row == 1 && return top_royalty(cs)
    row == 2 && return middle_royalty(cs)
    row == 3 && return bottom_royalty(cs)
    throw(ArgumentError("row must be 1, 2, or 3"))
end

total_royalties(top, middle, bottom)::Int =
    top_royalty(top) + middle_royalty(middle) + bottom_royalty(bottom)

end
