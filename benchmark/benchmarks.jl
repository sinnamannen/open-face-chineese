using BenchmarkTools
using OpenFaceChinese.Cards
using OpenFaceChinese.HandEval
using OpenFaceChinese.Engine
using OpenFaceChinese.Players

cs(text::AbstractString) = parse_cards(split(text))

const SUITE = BenchmarkGroup()

const ROYAL = cs("Th Jh Qh Kh Ah")
const WHEEL = cs("Ah 2d 3s 4c 5h")
const TOP_PAIR = cs("Qh Qd 2c")

SUITE["eval5"]["royal"] = @benchmarkable evaluate5($ROYAL)
SUITE["eval5"]["wheel"] = @benchmarkable evaluate5($WHEEL)
SUITE["eval3"]["top-pair"] = @benchmarkable evaluate3($TOP_PAIR)
SUITE["engine"]["legal-initial"] = @benchmarkable legal_actions(new_hand(seed = 1))
SUITE["simulation"]["random-hand"] = @benchmarkable play_hand(RandomPlayer(seed = 1), RandomPlayer(seed = 2), seed = 3)
SUITE["simulation"]["greedy-hand"] = @benchmarkable play_hand(GreedyPlayer(seed = 1, fantasyland_samples = 20), RandomPlayer(seed = 2), seed = 3)
SUITE["simulation"]["safe-hand"] = @benchmarkable play_hand(SafeGreedyPlayer(seed = 1, fantasyland_samples = 20), RandomPlayer(seed = 2), seed = 3)
SUITE["simulation"]["ensemble-hand"] = @benchmarkable play_hand(EnsemblePlayer(seed = 1, fantasyland_samples = 20), RandomPlayer(seed = 2), seed = 3)
SUITE["simulation"]["mc5k16-hand"] = @benchmarkable play_hand(MCRolloutPlayer(seed = 1, n_rollouts = 5, top_k = 16), RandomPlayer(seed = 2), seed = 3)

if abspath(PROGRAM_FILE) == @__FILE__
    results = run(SUITE, verbose = true)
    display(results)
end
