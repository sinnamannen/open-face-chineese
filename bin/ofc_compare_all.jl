using OpenFaceChinese.Simulation

const DEFAULT_PLAYERS = ["random", "greedy", "safe", "royalty", "balanced", "ensemble", "mc5k16"]

function usage()
    println("Usage:")
    println("  julia --project=. bin/ofc_compare_all.jl [games] [seed] [greedy_samples]")
    println()
    println("Default: 300 1 150")
    println("The default MC entry is mc5k16: 5 rollouts over the top 16 heuristic actions.")
    println("Players: ", join(DEFAULT_PLAYERS, ", "))
end

fmt_cell(x) = lpad(string(round(x, digits = 3)), 12)

function main()
    if any(arg -> arg in ("-h", "--help"), ARGS)
        usage()
        return
    end

    games = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 300
    seed = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 1
    greedy_samples = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 150

    println("Directed round-robin, games=$games per pairing, seed=$seed, greedy_samples=$greedy_samples")
    println("Cell = mean score/hand from row player as P1 perspective")
    print(rpad("P1 \\ P2", 12))
    for p2 in DEFAULT_PLAYERS
        print(lpad(p2, 12))
    end
    println()

    means = Dict{Tuple{String, String}, Float64}()
    for p1 in DEFAULT_PLAYERS
        print(rpad(p1, 12))
        for p2 in DEFAULT_PLAYERS
            if p1 == p2
                print(lpad("--", 12))
            else
                result = run_matchup(p1, p2, games, seed = seed, greedy_samples = greedy_samples)
                summary = summarize_scores(result.records)
                means[(p1, p2)] = summary.mean
                print(fmt_cell(summary.mean))
            end
        end
        println()
    end

    println()
    println("Average directed mean vs others:")
    for p1 in DEFAULT_PLAYERS
        vals = [means[(p1, p2)] for p2 in DEFAULT_PLAYERS if p1 != p2]
        println(rpad(p1, 12), round(sum(vals) / length(vals), digits = 3))
    end
end

main()
