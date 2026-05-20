module Engine

using Random
using ..Cards
using ..HandEval

export TOP, MIDDLE, BOTTOM, ROW_NAMES, NORMAL_DRAW_ROUNDS
export PlayerBoard, PendingCards, DiscardPile, Placement, PlacementAction, Observation, GameState, ScoreBreakdown
export row_capacity, row_name, row_cards, all_board_cards, board_count, board_mask
export empty_board, board_from_rows, place_card, apply_action_to_board, is_complete, is_foul
export pending_cards, discard_cards, placed_cards, discarded_cards, make_action, full_board_action
export new_hand, current_player, legal_actions, apply, is_terminal, view_from
export compare_line, score_boards, score_hand, fantasyland_card_count, refantasy_card_count, next_fantasy_cards

const TOP = UInt8(1)
const MIDDLE = UInt8(2)
const BOTTOM = UInt8(3)
const ROW_NAMES = ("top", "middle", "bottom")
const NORMAL_DRAW_ROUNDS = UInt8(4)
const MAX_PENDING = 17
const MAX_PLACEMENTS = 13
const MAX_DISCARDS = 4
const MAX_TOTAL_DISCARDS = 4

@inline row_capacity(row::Integer)::Int =
    row == TOP ? 3 : row == MIDDLE ? 5 : row == BOTTOM ? 5 :
    throw(ArgumentError("row must be TOP, MIDDLE, or BOTTOM"))

@inline row_name(row::Integer)::String = ROW_NAMES[Int(row)]

struct PlayerBoard
    top::NTuple{3, Card}
    middle::NTuple{5, Card}
    bottom::NTuple{5, Card}
    top_count::UInt8
    middle_count::UInt8
    bottom_count::UInt8
end

const EMPTY_TOP = (EMPTY_CARD, EMPTY_CARD, EMPTY_CARD)
const EMPTY_FIVE = (EMPTY_CARD, EMPTY_CARD, EMPTY_CARD, EMPTY_CARD, EMPTY_CARD)

empty_board() = PlayerBoard(EMPTY_TOP, EMPTY_FIVE, EMPTY_FIVE, 0, 0, 0)
PlayerBoard() = empty_board()

struct PendingCards
    cards::NTuple{MAX_PENDING, Card}
    count::UInt8
end

function PendingCards(cs::AbstractVector{Card})
    length(cs) <= MAX_PENDING || throw(ArgumentError("too many pending cards: $(length(cs))"))
    tuple_cards = ntuple(i -> i <= length(cs) ? cs[i] : EMPTY_CARD, MAX_PENDING)
    return PendingCards(tuple_cards, UInt8(length(cs)))
end

PendingCards() = PendingCards(Card[])
pending_cards(p::PendingCards)::Vector{Card} = [p.cards[i] for i in 1:Int(p.count)]

struct DiscardPile
    cards::NTuple{MAX_TOTAL_DISCARDS, Card}
    count::UInt8
end

function DiscardPile(cs::AbstractVector{Card})
    length(cs) <= MAX_TOTAL_DISCARDS || throw(ArgumentError("too many discarded cards: $(length(cs))"))
    tuple_cards = ntuple(i -> i <= length(cs) ? cs[i] : EMPTY_CARD, MAX_TOTAL_DISCARDS)
    return DiscardPile(tuple_cards, UInt8(length(cs)))
end

DiscardPile() = DiscardPile(Card[])
discard_cards(p::DiscardPile)::Vector{Card} = [p.cards[i] for i in 1:Int(p.count)]

function append_discards(pile::DiscardPile, cs::AbstractVector{Card})::DiscardPile
    isempty(cs) && return pile
    current = discard_cards(pile)
    append!(current, cs)
    length(unique(current)) == length(current) || throw(ArgumentError("discard pile contains duplicate cards"))
    return DiscardPile(current)
end

struct Placement
    card::Card
    row::UInt8
end

const EMPTY_PLACEMENT = Placement(EMPTY_CARD, UInt8(0))

struct PlacementAction
    placements::NTuple{MAX_PLACEMENTS, Placement}
    nplacements::UInt8
    discards::NTuple{MAX_DISCARDS, Card}
    ndiscards::UInt8
end

function PlacementAction(placements::AbstractVector{Placement}, discards::AbstractVector{Card} = Card[])
    length(placements) <= MAX_PLACEMENTS || throw(ArgumentError("too many placements: $(length(placements))"))
    length(discards) <= MAX_DISCARDS || throw(ArgumentError("too many discards: $(length(discards))"))

    placement_tuple = ntuple(i -> i <= length(placements) ? placements[i] : EMPTY_PLACEMENT, MAX_PLACEMENTS)
    discard_tuple = ntuple(i -> i <= length(discards) ? discards[i] : EMPTY_CARD, MAX_DISCARDS)
    return PlacementAction(placement_tuple, UInt8(length(placements)), discard_tuple, UInt8(length(discards)))
end

placed_cards(a::PlacementAction)::Vector{Card} = [a.placements[i].card for i in 1:Int(a.nplacements)]
discarded_cards(a::PlacementAction)::Vector{Card} = [a.discards[i] for i in 1:Int(a.ndiscards)]

function make_action(pairs::AbstractVector{Tuple{Card, UInt8}}, discards::AbstractVector{Card} = Card[])
    return PlacementAction([Placement(c, row) for (c, row) in pairs], discards)
end

function full_board_action(top, middle, bottom, discards = Card[])
    placements = Placement[]
    append!(placements, Placement(c, TOP) for c in top)
    append!(placements, Placement(c, MIDDLE) for c in middle)
    append!(placements, Placement(c, BOTTOM) for c in bottom)
    return PlacementAction(placements, Card[discards...])
end

row_cards(board::PlayerBoard, row::Integer)::Vector{Card} =
    row == TOP ? [board.top[i] for i in 1:Int(board.top_count)] :
    row == MIDDLE ? [board.middle[i] for i in 1:Int(board.middle_count)] :
    row == BOTTOM ? [board.bottom[i] for i in 1:Int(board.bottom_count)] :
    throw(ArgumentError("row must be TOP, MIDDLE, or BOTTOM"))

function all_board_cards(board::PlayerBoard)::Vector{Card}
    out = Card[]
    append!(out, row_cards(board, TOP))
    append!(out, row_cards(board, MIDDLE))
    append!(out, row_cards(board, BOTTOM))
    return out
end

@inline board_count(board::PlayerBoard)::Int =
    Int(board.top_count) + Int(board.middle_count) + Int(board.bottom_count)

function mask_of(cs)::UInt64
    mask = UInt64(0)
    for c in cs
        bit = card_mask(c)
        (mask & bit) == 0 || throw(ArgumentError("duplicate card $(card_string(c))"))
        mask |= bit
    end
    return mask
end

board_mask(board::PlayerBoard)::UInt64 = mask_of(all_board_cards(board))

function push3(t::NTuple{3, Card}, count::Integer, c::Card)::NTuple{3, Card}
    count < 3 || throw(ArgumentError("top row is full"))
    return ntuple(i -> i == count + 1 ? c : t[i], 3)
end

function push5(t::NTuple{5, Card}, count::Integer, c::Card, label::AbstractString)::NTuple{5, Card}
    count < 5 || throw(ArgumentError("$label row is full"))
    return ntuple(i -> i == count + 1 ? c : t[i], 5)
end

function place_card(board::PlayerBoard, row::Integer, c::Card)::PlayerBoard
    c == EMPTY_CARD && throw(ArgumentError("cannot place EMPTY_CARD"))
    hascard(board_mask(board), c) && throw(ArgumentError("card $(card_string(c)) is already on the board"))

    if row == TOP
        return PlayerBoard(push3(board.top, board.top_count, c), board.middle, board.bottom,
            board.top_count + UInt8(1), board.middle_count, board.bottom_count)
    elseif row == MIDDLE
        return PlayerBoard(board.top, push5(board.middle, board.middle_count, c, "middle"), board.bottom,
            board.top_count, board.middle_count + UInt8(1), board.bottom_count)
    elseif row == BOTTOM
        return PlayerBoard(board.top, board.middle, push5(board.bottom, board.bottom_count, c, "bottom"),
            board.top_count, board.middle_count, board.bottom_count + UInt8(1))
    else
        throw(ArgumentError("row must be TOP, MIDDLE, or BOTTOM"))
    end
end

function apply_action_to_board(board::PlayerBoard, action::PlacementAction)::PlayerBoard
    next = board
    for placement in action.placements[1:Int(action.nplacements)]
        next = place_card(next, placement.row, placement.card)
    end
    return next
end

function board_from_rows(top, middle, bottom)::PlayerBoard
    length(top) <= 3 || throw(ArgumentError("top has $(length(top)) cards"))
    length(middle) <= 5 || throw(ArgumentError("middle has $(length(middle)) cards"))
    length(bottom) <= 5 || throw(ArgumentError("bottom has $(length(bottom)) cards"))

    board = PlayerBoard()
    for c in top
        board = place_card(board, TOP, c)
    end
    for c in middle
        board = place_card(board, MIDDLE, c)
    end
    for c in bottom
        board = place_card(board, BOTTOM, c)
    end
    return board
end

is_complete(board::PlayerBoard)::Bool =
    board.top_count == 3 && board.middle_count == 5 && board.bottom_count == 5

function row_score(board::PlayerBoard, row::Integer)::UInt32
    cs = row_cards(board, row)
    row == TOP && return evaluate3(cs)
    return evaluate5(cs)
end

function is_foul(board::PlayerBoard)::Bool
    is_complete(board) || throw(ArgumentError("cannot foul-check an incomplete board"))
    top_score = row_score(board, TOP)
    middle_score = row_score(board, MIDDLE)
    bottom_score = row_score(board, BOTTOM)
    return middle_score < top_score || bottom_score < middle_score
end

struct Observation
    player_id::UInt8
    boards::NTuple{2, PlayerBoard}
    pending::PendingCards
    own_discards::DiscardPile
    opponent_pending_count::UInt8
    opponent_discard_count::UInt8
    current_player::UInt8
    round::UInt8
    fantasy_cards::NTuple{2, UInt8}
end

struct GameState
    boards::NTuple{2, PlayerBoard}
    deck::UInt64
    pending::NTuple{2, PendingCards}
    discards::NTuple{2, DiscardPile}
    current_player::UInt8
    round::UInt8
    fantasy_cards::NTuple{2, UInt8}
    rng::Random.Xoshiro
end

current_player(state::GameState)::Int = Int(state.current_player)

function normalize_fantasy_cards(fantasy_cards)::NTuple{2, UInt8}
    length(fantasy_cards) == 2 || throw(ArgumentError("fantasy_cards must have two entries"))
    return (UInt8(fantasy_cards[1]), UInt8(fantasy_cards[2]))
end

function new_hand(; seed::Integer = 1, fantasy_cards = (0, 0))::GameState
    rng = Random.Xoshiro(seed)
    deck = fresh_deck()
    fc = normalize_fantasy_cards(fantasy_cards)

    pending = Vector{PendingCards}(undef, 2)
    for pid in 1:2
        n = fc[pid] > 0 ? Int(fc[pid]) : 5
        hand, deck = draw(deck, rng, n)
        pending[pid] = PendingCards(hand)
    end

    return GameState((PlayerBoard(), PlayerBoard()), deck, (pending[1], pending[2]),
        (DiscardPile(), DiscardPile()), UInt8(1), 0, fc, rng)
end

function view_from(state::GameState, player_id::Integer)::Observation
    player_id in (1, 2) || throw(ArgumentError("player_id must be 1 or 2"))
    opp = 3 - player_id
    return Observation(UInt8(player_id), state.boards, state.pending[player_id],
        state.discards[player_id], state.pending[opp].count, state.discards[opp].count,
        state.current_player, state.round, state.fantasy_cards)
end

function remaining_capacity(board::PlayerBoard)::NTuple{3, Int}
    return (
        3 - Int(board.top_count),
        5 - Int(board.middle_count),
        5 - Int(board.bottom_count),
    )
end

remaining_slots(board::PlayerBoard)::Int = 13 - board_count(board)

function placed_index_sets(n::Int, nplace::Int)::Vector{Vector{Int}}
    n == nplace && return [collect(1:n)]
    sets = Vector{Vector{Int}}()
    current = Int[]
    function rec(start::Int)
        if length(current) == nplace
            push!(sets, copy(current))
            return
        end
        for i in start:n
            push!(current, i)
            rec(i + 1)
            pop!(current)
        end
    end
    rec(1)
    return sets
end

function legal_actions_for(board::PlayerBoard, pending::PendingCards)::Vector{PlacementAction}
    pcards = pending_cards(pending)
    n = length(pcards)
    n == 0 && return PlacementAction[]
    n > 5 && throw(ArgumentError("Fantasyland action enumeration is too large; construct a full_board_action instead"))

    slots = remaining_slots(board)
    nplace =
        n == slots ? n :
        n == 5 && board_count(board) == 0 ? 5 :
        n == 3 && slots >= 2 ? 2 :
        throw(ArgumentError("unsupported pending count $n with $slots open slots"))

    actions = PlacementAction[]
    for idxs in placed_index_sets(n, nplace)
        placed = [pcards[i] for i in idxs]
        discards = Card[pcards[i] for i in 1:n if !(i in idxs)]
        used = [0, 0, 0]
        rows = Vector{UInt8}(undef, nplace)
        cap = remaining_capacity(board)

        function assign(k::Int)
            if k > nplace
                push!(actions, PlacementAction([Placement(placed[i], rows[i]) for i in 1:nplace], discards))
                return
            end

            for row in 1:3
                if used[row] < cap[row]
                    used[row] += 1
                    rows[k] = UInt8(row)
                    assign(k + 1)
                    used[row] -= 1
                end
            end
        end
        assign(1)
    end
    return actions
end

legal_actions(obs::Observation)::Vector{PlacementAction} =
    legal_actions_for(obs.boards[Int(obs.player_id)], obs.pending)

function legal_actions(state::GameState)::Vector{PlacementAction}
    state.current_player == 0 && return PlacementAction[]
    return legal_actions(view_from(state, state.current_player))
end

function validate_action(board::PlayerBoard, pending::PendingCards, action::PlacementAction)::Nothing
    pcards = pending_cards(pending)
    n = length(pcards)
    n == 0 && throw(ArgumentError("there are no pending cards"))

    nplace_required =
        n > 5 ? 13 :
        n == remaining_slots(board) ? n :
        n == 5 && board_count(board) == 0 ? 5 :
        n == 3 && remaining_slots(board) >= 2 ? 2 :
        throw(ArgumentError("unsupported pending count $n"))

    action.nplacements == nplace_required ||
        throw(ArgumentError("expected $nplace_required placements, got $(action.nplacements)"))
    action.ndiscards == n - nplace_required ||
        throw(ArgumentError("expected $(n - nplace_required) discards, got $(action.ndiscards)"))

    placed = placed_cards(action)
    discards = discarded_cards(action)
    combined = Card[]
    append!(combined, placed)
    append!(combined, discards)

    length(combined) == count_ones(mask_of(combined)) ||
        throw(ArgumentError("action contains duplicate cards"))

    mask_of(combined) == mask_of(pcards) ||
        throw(ArgumentError("action cards must exactly match pending cards"))

    existing = board_mask(board)
    for c in placed
        (existing & card_mask(c)) == 0 || throw(ArgumentError("card $(card_string(c)) is already on board"))
    end

    counts = [Int(board.top_count), Int(board.middle_count), Int(board.bottom_count)]
    for placement in action.placements[1:Int(action.nplacements)]
        placement.row in (TOP, MIDDLE, BOTTOM) || throw(ArgumentError("invalid row $(placement.row)"))
        counts[Int(placement.row)] += 1
        counts[Int(placement.row)] <= row_capacity(placement.row) ||
            throw(ArgumentError("too many cards in $(row_name(placement.row)) row"))
    end
    return nothing
end

function set_board(boards::NTuple{2, PlayerBoard}, player_id::Integer, board::PlayerBoard)
    player_id == 1 && return (board, boards[2])
    player_id == 2 && return (boards[1], board)
    throw(ArgumentError("player_id must be 1 or 2"))
end

function set_pending(pending::NTuple{2, PendingCards}, player_id::Integer, value::PendingCards)
    player_id == 1 && return (value, pending[2])
    player_id == 2 && return (pending[1], value)
    throw(ArgumentError("player_id must be 1 or 2"))
end

function set_discards(discards::NTuple{2, DiscardPile}, player_id::Integer, value::DiscardPile)
    player_id == 1 && return (value, discards[2])
    player_id == 2 && return (discards[1], value)
    throw(ArgumentError("player_id must be 1 or 2"))
end

function next_pending_player(pending::NTuple{2, PendingCards}, after::Integer)::UInt8
    for offset in 1:2
        pid = ((after - 1 + offset) % 2) + 1
        pending[pid].count > 0 && return UInt8(pid)
    end
    return UInt8(0)
end

function deal_next_round(state::GameState)::GameState
    state.round < NORMAL_DRAW_ROUNDS ||
        throw(ArgumentError("cannot deal past Pineapple round $(NORMAL_DRAW_ROUNDS)"))

    rng = copy(state.rng)
    deck = state.deck
    pending = [PendingCards(), PendingCards()]
    for pid in 1:2
        if !is_complete(state.boards[pid])
            hand, deck = draw(deck, rng, 3)
            pending[pid] = PendingCards(hand)
        end
    end

    current = next_pending_player((pending[1], pending[2]), 2)
    return GameState(state.boards, deck, (pending[1], pending[2]), state.discards, current,
        state.round + UInt8(1), state.fantasy_cards, rng)
end

function advance_after_action(state::GameState, previous_player::Integer)::GameState
    next_player = next_pending_player(state.pending, previous_player)
    next_player != 0 && return GameState(state.boards, state.deck, state.pending, state.discards,
        next_player, state.round, state.fantasy_cards, state.rng)

    all(is_complete, state.boards) && return GameState(state.boards, state.deck, state.pending, state.discards,
        UInt8(0), state.round, state.fantasy_cards, state.rng)

    return deal_next_round(state)
end

function apply(state::GameState, action::PlacementAction)::GameState
    state.current_player != 0 || throw(ArgumentError("cannot act in a terminal state"))
    pid = Int(state.current_player)
    board = state.boards[pid]
    pending = state.pending[pid]
    validate_action(board, pending, action)

    next_board = apply_action_to_board(board, action)
    next_boards = set_board(state.boards, pid, next_board)
    next_pending = set_pending(state.pending, pid, PendingCards())
    next_discards = set_discards(state.discards, pid,
        append_discards(state.discards[pid], discarded_cards(action)))
    cleared = GameState(next_boards, state.deck, next_pending, next_discards, UInt8(0),
        state.round, state.fantasy_cards, state.rng)
    return advance_after_action(cleared, pid)
end

is_terminal(state::GameState)::Bool = state.current_player == 0 && all(is_complete, state.boards)

function compare_line(a::PlayerBoard, b::PlayerBoard, row::Integer)::Int
    ascore = row_score(a, row)
    bscore = row_score(b, row)
    return ascore > bscore ? 1 : ascore < bscore ? -1 : 0
end

function board_royalties(board::PlayerBoard)::Int
    return total_royalties(row_cards(board, TOP), row_cards(board, MIDDLE), row_cards(board, BOTTOM))
end

struct ScoreBreakdown
    line_points::NTuple{3, Int8}
    scoop_bonus::Int8
    p1_royalties::Int16
    p2_royalties::Int16
    total::Int16
    fouls::NTuple{2, Bool}
end

function score_boards(a::PlayerBoard, b::PlayerBoard)::ScoreBreakdown
    is_complete(a) && is_complete(b) || throw(ArgumentError("both boards must be complete"))
    a_foul = is_foul(a)
    b_foul = is_foul(b)

    if a_foul && b_foul
        return ScoreBreakdown((0, 0, 0), 0, 0, 0, 0, (true, true))
    end

    if a_foul
        b_royalties = Int16(board_royalties(b))
        total = Int16(-6 - b_royalties)
        return ScoreBreakdown((-1, -1, -1), -3, 0, b_royalties, total, (true, false))
    end

    if b_foul
        a_royalties = Int16(board_royalties(a))
        total = Int16(6 + a_royalties)
        return ScoreBreakdown((1, 1, 1), 3, a_royalties, 0, total, (false, true))
    end

    lines = (
        Int8(compare_line(a, b, TOP)),
        Int8(compare_line(a, b, MIDDLE)),
        Int8(compare_line(a, b, BOTTOM)),
    )
    scoop = all(==(Int8(1)), lines) ? Int8(3) : all(==(Int8(-1)), lines) ? Int8(-3) : Int8(0)
    a_royalties = Int16(board_royalties(a))
    b_royalties = Int16(board_royalties(b))
    total = Int16(sum(lines) + scoop + a_royalties - b_royalties)
    return ScoreBreakdown(lines, scoop, a_royalties, b_royalties, total, (false, false))
end

function score_hand(state::GameState)::ScoreBreakdown
    is_terminal(state) || throw(ArgumentError("state is not terminal"))
    return score_boards(state.boards[1], state.boards[2])
end

function fantasyland_card_count(board::PlayerBoard)::UInt8
    is_foul(board) && return UInt8(0)
    top_score = row_score(board, TOP)
    cat = category(top_score)
    ks = kicker_tuple(top_score)

    cat == TRIPS && return UInt8(17)
    cat == ONE_PAIR || return UInt8(0)

    pair_rank = Int(ks[1])
    pair_rank >= 12 && return UInt8(16)
    pair_rank == 11 && return UInt8(15)
    pair_rank == 10 && return UInt8(14)
    return UInt8(0)
end

function refantasy_card_count(board::PlayerBoard)::UInt8
    is_foul(board) && return UInt8(0)
    count = UInt8(0)

    top_score = row_score(board, TOP)
    if category(top_score) == TRIPS
        count = max(count, UInt8(17))
    end

    middle_score = row_score(board, MIDDLE)
    if category(middle_score) >= FULL_HOUSE
        count = max(count, fantasyland_card_count(board), UInt8(14))
    end

    bottom_score = row_score(board, BOTTOM)
    if category(bottom_score) >= QUADS
        count = max(count, fantasyland_card_count(board), UInt8(14))
    end

    return count
end

function next_fantasy_cards(state::GameState)::NTuple{2, UInt8}
    return ntuple(2) do pid
        state.fantasy_cards[pid] > 0 ?
            refantasy_card_count(state.boards[pid]) :
            fantasyland_card_count(state.boards[pid])
    end
end

end
