using OpenFaceChinese.Cards
using OpenFaceChinese.Engine
using OpenFaceChinese.Players

function main()
    seed = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 1
    human = HumanPlayer()
    bot = GreedyPlayer(seed = seed + 10_000)
    state = new_hand(seed = seed)

    println("OFC Pineapple seed: $seed")
    while !is_terminal(state)
        println()
        println(render_state(state))
        pid = current_player(state)
        player = pid == 1 ? human : bot
        action = decide(player, view_from(state, pid))
        state = OpenFaceChinese.Engine.apply(state, action)
    end

    println()
    println(render_state(state, reveal_pending = true))
    score = score_hand(state)
    println()
    println("Lines: $(score.line_points), scoop: $(score.scoop_bonus), royalties: P1 $(score.p1_royalties) / P2 $(score.p2_royalties)")
    println("Total from Player 1 perspective: $(score.total)")
    println("Next Fantasyland cards: $(next_fantasy_cards(state))")
end

main()
