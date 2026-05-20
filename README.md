# OpenFaceChinese.jl

A Julia engine for heads-up Open-Face Chinese Pineapple, built first for correctness and deterministic simulation, then for bots and training.

The current rules are locked in [RULES.md](RULES.md). The implementation is organized as:

- `Cards`: `UInt8` card encoding and `UInt64` deck masks.
- `HandEval`: 3-card and 5-card poker evaluators plus royalties.
- `Engine`: immutable game state, legal actions, scoring, and Fantasyland triggers.
- `Players`: random, greedy, and terminal players plus text rendering.
- `Solver`: Fantasyland partition scaffolding.
- `Train`: lightweight state encoder scaffolding.

Run tests:

```powershell
julia --project=. -e "using Pkg; Pkg.test()"
```

Play a terminal hand against the greedy bot:

```powershell
julia --project=. bin/ofc_cli.jl
```

Pass an integer argument to choose a different deterministic seed.

Play in a browser against the greedy bot:

```powershell
julia --project=. bin/ofc_web.jl
```

Then open <http://127.0.0.1:8088/>. You can pass `seed`, `port`, and bot name:

```powershell
julia --project=. bin/ofc_web.jl 123 8090 mc5k16
```

Run a headless bot matchup:

```powershell
julia --project=. bin/ofc_matchup.jl random greedy 1000
```

Arguments are `p1 p2 games seed greedy_samples`. Players are `random`, `greedy`, `safe`, `royalty`, `balanced`, `ensemble`, `mc`, `mc<N>` such as `mc100`, and `mc<N>k<K>` such as `mc100k16`. The `k` value is the heuristic shortlist size for MC rollouts. Scores are reported from Player 1's perspective.

Compare all code baselines in a directed round-robin:

```powershell
julia --project=. bin/ofc_compare_all.jl 300 1 150
```

The broad comparison uses `mc5k16` by default because MC rollout is still expensive. Use `bin/ofc_matchup.jl mc100k16 safe 100` for targeted higher-budget MC tests.

Generated models, checkpoints, replay buffers, and eval reports belong under `artifacts/`. Large files in that tree are ignored by git; see [artifacts/README.md](artifacts/README.md).
