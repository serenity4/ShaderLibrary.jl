using CompileTraces

@compile_traces verbose = false joinpath(@__DIR__, "precompilation_traces.jl")
