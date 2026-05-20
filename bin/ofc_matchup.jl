using OpenFaceChinese.Simulation

function usage()
    println("Usage:")
    println("  julia --project=. bin/ofc_matchup.jl [p1] [p2] [games] [seed] [greedy_samples]")
    println()
    println("Players: random, greedy, safe, royalty, balanced, ensemble, mc, mc<N>, mc<N>k<K>")
    println("Default: random greedy 1000 1 500")
    println("For mc, the final argument is used as rollout count unless the name is like mc100 or mc100k16.")
end

function main()
    if any(arg -> arg in ("-h", "--help"), ARGS)
        usage()
        return
    end

    p1 = length(ARGS) >= 1 ? ARGS[1] : "random"
    p2 = length(ARGS) >= 2 ? ARGS[2] : "greedy"
    games = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 1000
    seed = length(ARGS) >= 4 ? parse(Int, ARGS[4]) : 1
    greedy_samples = length(ARGS) >= 5 ? parse(Int, ARGS[5]) : 500

    result = run_matchup(p1, p2, games, seed = seed, greedy_samples = greedy_samples)
    println(format_matchup_report(result))
end

main()
