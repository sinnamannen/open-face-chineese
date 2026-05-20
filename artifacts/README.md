# Generated Artifacts

This folder is for local training outputs and evaluation artifacts. Large generated files are ignored by git.

- `models/`: exported named models or promoted snapshots.
- `runs/`: per-run checkpoints, metrics, configs, and logs.
- `replay/`: replay buffers or self-play data.
- `evals/`: tournament reports and baseline comparisons.

The current `RandomPlayer`, `GreedyPlayer`, and Greedy+ bots are code baselines in `src/Players.jl`, not saved neural-network checkpoints.

Suggested checkpoint path from Julia:

```julia
using OpenFaceChinese.Train

ensure_artifact_dirs()
checkpoint_path("ppo_seed_1", 10_000)
```

That returns a path like:

```text
artifacts/runs/ppo_seed_1/checkpoint_step_0000010000.jls
```
