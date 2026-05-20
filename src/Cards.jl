module Cards

using Random

export Card, EMPTY_CARD, FULL_DECK, RANK_CHARS, SUIT_CHARS
export card, rank, rank_value, suit, card_mask, hascard, add_card, remove_card
export cards, deck_count, fresh_deck, draw, parse_card, parse_cards, card_string, cards_string

const Card = UInt8
const EMPTY_CARD = Card(0xff)
const RANK_CHARS = "23456789TJQKA"
const SUIT_CHARS = "cdhs"
const FULL_DECK = (UInt64(1) << 52) - UInt64(1)

@inline function card(rank::Integer, suit::Integer)::Card
    0 <= rank <= 12 || throw(ArgumentError("rank must be 0..12, got $rank"))
    0 <= suit <= 3 || throw(ArgumentError("suit must be 0..3, got $suit"))
    return Card(suit * 13 + rank)
end

@inline function rank(c::Card)::Int
    c == EMPTY_CARD && throw(ArgumentError("EMPTY_CARD has no rank"))
    return Int(c % 13)
end

@inline rank_value(c::Card)::Int = rank(c) + 2

@inline function suit(c::Card)::Int
    c == EMPTY_CARD && throw(ArgumentError("EMPTY_CARD has no suit"))
    return Int(c ÷ 13)
end

@inline function card_mask(c::Card)::UInt64
    c == EMPTY_CARD && return UInt64(0)
    Int(c) < 52 || throw(ArgumentError("card must be 0..51, got $c"))
    return UInt64(1) << Int(c)
end

@inline hascard(deck::UInt64, c::Card)::Bool = (deck & card_mask(c)) != 0
@inline add_card(deck::UInt64, c::Card)::UInt64 = deck | card_mask(c)
@inline remove_card(deck::UInt64, c::Card)::UInt64 = deck & ~card_mask(c)
@inline deck_count(deck::UInt64)::Int = count_ones(deck)
@inline fresh_deck()::UInt64 = FULL_DECK

function nth_set_bit(mask::UInt64, n::Integer)::Int
    n >= 1 || throw(ArgumentError("n must be >= 1"))
    seen = 0
    for i in 0:51
        if (mask & (UInt64(1) << i)) != 0
            seen += 1
            seen == n && return i
        end
    end
    throw(ArgumentError("mask has fewer than $n set bits"))
end

function cards(mask::UInt64)::Vector{Card}
    out = Card[]
    sizehint!(out, deck_count(mask))
    for i in 0:51
        if (mask & (UInt64(1) << i)) != 0
            push!(out, Card(i))
        end
    end
    return out
end

function draw(deck::UInt64, rng::AbstractRNG, n::Integer)::Tuple{Vector{Card}, UInt64}
    n >= 0 || throw(ArgumentError("cannot draw a negative number of cards"))
    deck_count(deck) >= n || throw(ArgumentError("deck contains only $(deck_count(deck)) cards"))

    out = Vector{Card}(undef, n)
    next_deck = deck
    for i in 1:n
        bit = nth_set_bit(next_deck, rand(rng, 1:deck_count(next_deck)))
        c = Card(bit)
        out[i] = c
        next_deck = remove_card(next_deck, c)
    end
    return out, next_deck
end

function parse_card(text::AbstractString)::Card
    s = lowercase(strip(text))
    length(s) in (2, 3) || throw(ArgumentError("card must look like As, Td, or 10h; got '$text'"))

    rank_text = s[1:end-1]
    suit_char = s[end]
    rank_char = rank_text == "10" ? 't' : only(rank_text)

    r = findfirst(==(uppercase(rank_char)), RANK_CHARS)
    r === nothing && throw(ArgumentError("unknown rank in '$text'"))

    st = findfirst(==(suit_char), SUIT_CHARS)
    st === nothing && throw(ArgumentError("unknown suit in '$text'; use c, d, h, or s"))

    return card(r - 1, st - 1)
end

parse_cards(texts) = [parse_card(t) for t in texts]

function card_string(c::Card)::String
    c == EMPTY_CARD && return "--"
    return string(RANK_CHARS[rank(c) + 1], SUIT_CHARS[suit(c) + 1])
end

cards_string(cs)::String = join(card_string.(cs), " ")

end
