using Test
using Random
using OpenFaceChinese
using OpenFaceChinese.Cards
using OpenFaceChinese.HandEval
using OpenFaceChinese.Engine
using OpenFaceChinese.Players
using OpenFaceChinese.Simulation
using OpenFaceChinese.Solver
using OpenFaceChinese.Train
using OpenFaceChinese.WebUI

cs(text::AbstractString) = parse_cards(split(text))
mkboard(top::AbstractString, middle::AbstractString, bottom::AbstractString) =
    board_from_rows(cs(top), cs(middle), cs(bottom))

@testset "Cards and deck" begin
    ace_spades = parse_card("As")
    @test rank(ace_spades) == 12
    @test suit(ace_spades) == 3
    @test card_string(ace_spades) == "As"

    ten_hearts = parse_card("10h")
    @test rank(ten_hearts) == 8
    @test card_string(ten_hearts) == "Th"

    rng = Random.Xoshiro(42)
    drawn, deck = draw(fresh_deck(), rng, 17)
    @test length(drawn) == 17
    @test length(unique(drawn)) == 17
    @test deck_count(deck) == 35
    @test all(!hascard(deck, c) for c in drawn)
end

@testset "Hand evaluation" begin
    wheel = evaluate5(cs("Ah 2d 3s 4c 5h"))
    six_high = evaluate5(cs("2h 3d 4s 5c 6h"))
    broadway = evaluate5(cs("Th Jd Qs Kc Ah"))
    @test category(wheel) == STRAIGHT
    @test kicker_tuple(wheel)[1] == 3
    @test six_high > wheel
    @test broadway > six_high

    royal = evaluate5(cs("Th Jh Qh Kh Ah"))
    nine_high_sf = evaluate5(cs("5s 6s 7s 8s 9s"))
    quads = evaluate5(cs("Ac Ad Ah As Kd"))
    full_house = evaluate5(cs("Kc Kd Kh Qs Qd"))
    flush = evaluate5(cs("2c 5c 8c Jc Kc"))
    @test category(royal) == STRAIGHT_FLUSH
    @test is_royal(royal)
    @test royal > nine_high_sf > quads > full_house > flush

    top_trips = evaluate3(cs("2c 2d 2h"))
    top_pair = evaluate3(cs("Ac Ad Kh"))
    top_high = evaluate3(cs("Ac Kd Qh"))
    @test category(top_trips) == TRIPS
    @test category(top_pair) == ONE_PAIR
    @test top_trips > top_pair > top_high
end

@testset "Royalties and Fantasyland triggers" begin
    qq = mkboard("Qh Qd 2c", "3c 4d 5s 6h 7c", "Ts Js Qs Ks As")
    kk = mkboard("Kh Kd 2c", "3c 4d 5s 6h 7c", "Ts Js Qs Ks As")
    aa = mkboard("Ah Ad 2c", "3c 4d 5s 6h 7c", "Ts Js Qs Ks As")
    trips = mkboard("2c 2d 2h", "3c 4d 5s 6h 7c", "As Qs Js 9s 4s")

    @test top_royalty(row_cards(qq, TOP)) == 7
    @test middle_royalty(row_cards(qq, MIDDLE)) == 4
    @test bottom_royalty(row_cards(qq, BOTTOM)) == 25
    @test fantasyland_card_count(qq) == 14
    @test fantasyland_card_count(kk) == 15
    @test fantasyland_card_count(aa) == 16
    @test fantasyland_card_count(trips) == 17

    re_mid = mkboard("Ac Kd Qh", "2c 2d 2h 3c 3d", "4c 4d 4h 5c 5d")
    re_bot = mkboard("Ac Kd Qh", "2c 2d 3d 5h 7c", "4c 4d 4s 4h 9c")
    @test refantasy_card_count(re_mid) == 14
    @test refantasy_card_count(re_bot) == 14
end

@testset "Foul edge cases" begin
    cases = [
        ("Qh Qd 2c", "3c 4d 5s 6h 7c", "Ts Js Qs Ks As", false),
        ("Ah Kd 9c", "2h 2d 5c 7s Jc", "3h 3d 4c 4s Ac", false),
        ("Qh Qd 2c", "Kh Kd 3c 5d 7h", "As Ac 4c 6d 8h", false),
        ("2c 2d 2h", "3c 4d 5s 6h 7c", "Ah Qh Jh 9h 4h", false),
        ("As Ah 2c", "Kd Kc 3h 4d 5s", "Qh Qd Js Jc 9c", true),
        ("Ah Kd Qc", "2h 5h 8h Jh Kh", "3c 4d 5s 6c 7d", true),
        ("6c 6d Ah", "9c 9d 9h 2c 2d", "As Qs Js 8s 3s", true),
        ("Ac Ad Ah", "Kc Kd Qh Qd 2c", "3c 3d 3h 4c 4d", true),
        ("Ah Kd Qc", "As Kh Qd Jc 9s", "2h 3h 4h 5h 7h", false),
        ("Ah Kd Qc", "As Kh Jd 9c 8s", "2h 2d 3c 4s 5h", true),
        ("6c 6d Ah", "7h 7s 2c 3d 4h", "8c 8d 5c 9d Th", false),
        ("6c 6d Ah", "6h 6s Kc Qd 2c", "7h 7d 3c 4s 5h", true),
        ("Ac Kd Qh", "2c 2d 2h 3s 4c", "3c 3d 3h 5s 6c", false),
        ("2c 3d 4h", "5s 6s 7s 8s 9s", "Ah Ad Ac As Kd", true),
        ("Ah Ad 2c", "Kc Kd Qh Qd 3c", "4c 4d 4h 5s 6c", false),
        ("2c 3d 4h", "Ac Ad Kc Qd Jc", "Ah As Kh Qs Jd", false),
        ("Kc Qd Jh", "Ah 2d 3s 4c 5h", "2c 3d 4s 5c 6h", false),
        ("Kc Qd Jh", "2c 3d 4s 5c 6h", "Ah 2d 3s 4c 5h", true),
        ("Jc Jd 2h", "Qc Qd 3h 4s 5c", "Kh Kd 6h 7s 8c", false),
        ("Qc Qd 2h", "Jc Jd 3h 4s 5c", "Kh Kd 6h 7s 8c", true),
        ("Ac Kd Qh", "2c 2d 2h 3c 3d", "4c 4d 4h 5c 5d", false),
        ("Ac Kd Qh", "4c 4d 4h 5c 5d", "2c 2d 2h 3c 3d", true),
    ]

    @test length(cases) >= 20
    for (top, middle, bottom, expected) in cases
        @test is_foul(mkboard(top, middle, bottom)) == expected
    end
end

@testset "Scoring" begin
    p1 = mkboard("6c 6d Ah", "2c 3d 4h 5s 6h", "7c 8c 9c Tc Jc")
    p2 = mkboard("7d 7h Kh", "2d 3c 4d 5h 6s", "Ad Ac As 9h 9d")
    score = score_boards(p1, p2)
    @test score.fouls == (false, false)
    @test score.p1_royalties == 20
    @test score.p2_royalties == 12

    fouled = mkboard("As Ah 2c", "Kd Kc 3h 4d 5s", "Qh Qd Js Jc 9c")
    clean = mkboard("Qh Qd 2c", "3c 4d 5s 6h 7c", "Ts Js Qs Ks As")
    foul_score = score_boards(fouled, clean)
    @test foul_score.fouls == (true, false)
    @test foul_score.total == -6 - foul_score.p2_royalties
end

@testset "Engine actions and observations" begin
    state = new_hand(seed = 123)
    @test current_player(state) == 1
    @test state.pending[1].count == 5
    @test state.pending[2].count == 5
    @test deck_count(state.deck) == 42

    obs = view_from(state, 1)
    @test obs.pending.count == 5
    @test obs.opponent_pending_count == 5
    @test obs.own_discards.count == 0
    @test obs.opponent_discard_count == 0
    @test length(legal_actions(state)) == 232

    discard_state = new_hand(seed = 321)
    discard_state = apply(discard_state, legal_actions(discard_state)[1])
    discard_state = apply(discard_state, legal_actions(discard_state)[1])
    discard_action = legal_actions(discard_state)[1]
    @test length(discarded_cards(discard_action)) == 1
    discarded = discarded_cards(discard_action)[1]
    discard_state = apply(discard_state, discard_action)
    @test discard_state.discards[1].count == 1
    @test discard_cards(view_from(discard_state, 1).own_discards) == [discarded]
    @test view_from(discard_state, 2).opponent_discard_count == 1
    det = determinize_observation(view_from(discard_state, 2), Random.Xoshiro(5))
    @test det.boards == discard_state.boards
    @test det.pending[2] == discard_state.pending[2]
    @test det.discards[2] == discard_state.discards[2]
    @test det.pending[1].count == view_from(discard_state, 2).opponent_pending_count
    @test det.discards[1].count == view_from(discard_state, 2).opponent_discard_count
    @test length(OpenFaceChinese.Players.mc_candidate_actions(MCRolloutPlayer(seed = 16, n_rollouts = 1, top_k = 4), obs)) == 4

    result = play_hand(RandomPlayer(seed = 1), RandomPlayer(seed = 2), seed = 999)
    @test is_terminal(result.state)
    @test board_count(result.state.boards[1]) == 13
    @test board_count(result.state.boards[2]) == 13
    @test result.state.discards[1].count == 4
    @test result.state.discards[2].count == 4
    @test result.score.total isa Int16

    for player in (
        GreedyPlayer(seed = 10, fantasyland_samples = 5),
        SafeGreedyPlayer(seed = 11, fantasyland_samples = 5),
        RoyaltyGreedyPlayer(seed = 12, fantasyland_samples = 5),
        BalancedGreedyPlayer(seed = 13, fantasyland_samples = 5),
        EnsemblePlayer(seed = 14, fantasyland_samples = 5),
        MCRolloutPlayer(seed = 15, n_rollouts = 2, top_k = 4),
    )
        result = play_hand(player, RandomPlayer(seed = 20), seed = 300)
        @test is_terminal(result.state)
    end
end

@testset "Solver and training scaffolding" begin
    @test fantasyland_partition_count(14) == binomial(14, 3) * binomial(11, 5) * binomial(6, 5)

    state = new_hand(seed = 7)
    obs = view_from(state, 1)
    tensor = encode_observation(obs)
    @test size(tensor) == (STATE_CHANNELS, 13, 4)
    @test STATE_CHANNELS == 9
    @test sum(tensor[7, :, :]) == 5
    @test sum(tensor[8, :, :]) == 0

    artifact_root = mktempdir()
    @test basename(ensure_artifact_dirs(root = artifact_root)) == basename(artifact_root)
    @test isdir(joinpath(artifact_root, "models"))
    @test isdir(joinpath(artifact_root, "runs"))
    @test isdir(joinpath(artifact_root, "replay"))
    @test isdir(joinpath(artifact_root, "evals"))

    path = checkpoint_path("ppo seed 1", 12, root = artifact_root)
    @test occursin("ppo_seed_1", path)
    @test endswith(path, "checkpoint_step_0000000012.jls")
end

@testset "Browser display adapter" begin
    session = new_web_session(seed = 8, bot_name = "mc2k3", bot_samples = 5)
    page = render_page(session)
    @test occursin("OpenFaceChinese.jl", page)
    @test occursin("mc2k3", page)
    @test occursin("Place Cards", page)

    obs = view_from(session.state, 1)
    action = action_from_row_tokens(obs, ["t", "m", "m", "b", "b"])
    @test length(placed_cards(action)) == 5

    apply_human_action!(session, ["t", "m", "m", "b", "b"])
    @test current_player(session.state) == 1
    @test board_count(session.state.boards[1]) == 5
    @test board_count(session.state.boards[2]) == 5
end

@testset "Headless matchup reports" begin
    result = run_matchup("random", "greedy", 5, seed = 40, greedy_samples = 5)
    @test result.n == 5
    @test length(result.records) == 5
    @test result.records[1].seed == 40

    summary = summarize_scores(result.records)
    @test summary.n == 5
    @test summary.wins + summary.losses + summary.ties == 5

    report = format_matchup_report(result)
    @test occursin("random (P1)", report)
    @test occursin("Mean score/hand", report)
    @test occursin("Fantasyland", report)

    for name in ("safe", "royalty", "balanced", "ensemble")
        result = run_matchup(name, "random", 2, seed = 80, greedy_samples = 3)
        @test result.n == 2
        @test length(result.records) == 2
    end

    result = run_matchup("mc2k3", "random", 2, seed = 90, greedy_samples = 3)
    @test result.n == 2
    @test length(result.records) == 2
end
