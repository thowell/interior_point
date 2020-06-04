using Test
using BenchmarkTools
using NLPModels
using CUTEst
using Ipopt

include("../src/interior_point.jl")
include("test_utils.jl")

opts = Options{Float64}(kkt_solve=:symmetric,
                        max_iter=1000,
                        verbose=false,
                        iterative_refinement=false)

include("cutest_tests.jl")
include("complementarity_tests.jl")
include("contact_tests.jl")
include("nlp_tests.jl")
