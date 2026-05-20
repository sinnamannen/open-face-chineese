using OpenFaceChinese.WebUI

function main()
    args = filter(arg -> arg != "--no-open", ARGS)
    seed = length(args) >= 1 ? parse(Int, args[1]) : 1
    port = length(args) >= 2 ? parse(Int, args[2]) : 8088
    bot_name = length(args) >= 3 ? args[3] : "greedy"
    bot_samples = length(args) >= 4 ? parse(Int, args[4]) : 500
    no_open = any(==("--no-open"), ARGS)
    serve(seed = seed, port = port, bot_name = bot_name, bot_samples = bot_samples, open = !no_open)
end

main()
