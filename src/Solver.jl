module Solver

using ..Cards
using ..HandEval
using ..Engine

export fantasyland_partition_count, foreach_fantasyland_partition, solve_fantasyland

fantasyland_partition_count(n::Integer)::Int =
    13 <= n <= 17 ? binomial(n, 3) * binomial(n - 3, 5) * binomial(n - 8, 5) :
    throw(ArgumentError("Fantasyland card count must be 13..17, got $n"))

function combinations_indices(n::Int, k::Int, f::Function)
    current = Vector{Int}(undef, k)

    function rec(start::Int, depth::Int)
        if depth > k
            f(current)
            return
        end

        stop = n - (k - depth)
        for i in start:stop
            current[depth] = i
            rec(i + 1, depth + 1)
        end
    end

    rec(1, 1)
    return nothing
end

function complement_indices(n::Int, idxs)::Vector{Int}
    used = falses(n)
    for i in idxs
        used[i] = true
    end
    return [i for i in 1:n if !used[i]]
end

function foreach_fantasyland_partition(cards::AbstractVector{Card}, f::Function)
    n = length(cards)
    fantasyland_partition_count(n)

    combinations_indices(n, 3) do top_idxs
        rem_after_top = complement_indices(n, top_idxs)
        combinations_indices(length(rem_after_top), 5) do middle_local
            middle_idxs = [rem_after_top[i] for i in middle_local]
            rem_after_middle = [idx for idx in rem_after_top if !(idx in middle_idxs)]
            combinations_indices(length(rem_after_middle), 5) do bottom_local
                bottom_idxs = [rem_after_middle[i] for i in bottom_local]
                discard_idxs = [idx for idx in rem_after_middle if !(idx in bottom_idxs)]

                top = [cards[i] for i in top_idxs]
                middle = [cards[i] for i in middle_idxs]
                bottom = [cards[i] for i in bottom_idxs]
                discards = [cards[i] for i in discard_idxs]
                f(board_from_rows(top, middle, bottom), discards)
            end
        end
    end

    return nothing
end

function default_fantasyland_value(board::PlayerBoard)::Int
    is_foul(board) && return typemin(Int)
    return top_royalty(row_cards(board, TOP)) +
        middle_royalty(row_cards(board, MIDDLE)) +
        bottom_royalty(row_cards(board, BOTTOM))
end

function solve_fantasyland(cards::AbstractVector{Card}; value_fn::Function = default_fantasyland_value)
    best_board = Ref{Union{Nothing, PlayerBoard}}(nothing)
    best_discards = Ref(Card[])
    best_value = Ref(typemin(Int))

    foreach_fantasyland_partition(cards) do board, discards
        value = value_fn(board)
        if value > best_value[]
            best_board[] = board
            best_discards[] = discards
            best_value[] = value
        end
    end

    best_board[] === nothing && throw(ArgumentError("no Fantasyland partitions available"))
    return (board = best_board[]::PlayerBoard, discards = best_discards[], value = best_value[])
end

end
