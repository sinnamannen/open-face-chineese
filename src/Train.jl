module Train

using ..Cards
using ..Engine

export STATE_CHANNELS, DEFAULT_ARTIFACT_ROOT, ARTIFACT_SUBDIRS
export ensure_artifact_dirs, model_dir, run_dir, checkpoint_path, encode_observation

const STATE_CHANNELS = 9
const DEFAULT_ARTIFACT_ROOT = "artifacts"
const ARTIFACT_SUBDIRS = ("models", "runs", "replay", "evals")

function safe_artifact_id(value)::String
    text = string(value)
    isempty(text) && throw(ArgumentError("artifact id cannot be empty"))
    return replace(text, r"[^A-Za-z0-9_.-]" => "_")
end

function ensure_artifact_dirs(; root::AbstractString = DEFAULT_ARTIFACT_ROOT)::String
    mkpath(root)
    for subdir in ARTIFACT_SUBDIRS
        mkpath(joinpath(root, subdir))
    end
    return abspath(root)
end

function model_dir(; root::AbstractString = DEFAULT_ARTIFACT_ROOT)::String
    ensure_artifact_dirs(root = root)
    return joinpath(abspath(root), "models")
end

function run_dir(run_id; root::AbstractString = DEFAULT_ARTIFACT_ROOT)::String
    ensure_artifact_dirs(root = root)
    path = joinpath(abspath(root), "runs", safe_artifact_id(run_id))
    mkpath(path)
    return path
end

function checkpoint_path(run_id, step::Integer; root::AbstractString = DEFAULT_ARTIFACT_ROOT, ext::AbstractString = ".jls")::String
    step >= 0 || throw(ArgumentError("checkpoint step must be non-negative"))
    extension = startswith(ext, ".") ? ext : ".$ext"
    filename = "checkpoint_step_$(lpad(step, 10, '0'))$extension"
    return joinpath(run_dir(run_id, root = root), filename)
end

function mark_cards!(tensor, channel::Integer, cs)
    for c in cs
        tensor[channel, rank(c) + 1, suit(c) + 1] = 1.0f0
    end
    return tensor
end

function encode_observation(obs::Observation)
    tensor = zeros(Float32, STATE_CHANNELS, 13, 4)
    own = Int(obs.player_id)
    opp = 3 - own

    mark_cards!(tensor, 1, row_cards(obs.boards[own], TOP))
    mark_cards!(tensor, 2, row_cards(obs.boards[own], MIDDLE))
    mark_cards!(tensor, 3, row_cards(obs.boards[own], BOTTOM))
    mark_cards!(tensor, 4, row_cards(obs.boards[opp], TOP))
    mark_cards!(tensor, 5, row_cards(obs.boards[opp], MIDDLE))
    mark_cards!(tensor, 6, row_cards(obs.boards[opp], BOTTOM))
    mark_cards!(tensor, 7, pending_cards(obs.pending))
    mark_cards!(tensor, 8, discard_cards(obs.own_discards))

    if obs.current_player == obs.player_id
        tensor[9, :, :] .= 1.0f0
    end

    return tensor
end

end
