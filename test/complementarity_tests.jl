include("complementarity_problems.jl")
opts = Options{Float64}(kkt_solve=:symmetric,
                        max_iter=1000,
                        verbose=false)
@testset "Complementarity problems" begin
    opts.verbose=false
    solver = InteriorPointSolver(knitro_comp()...,opts=opts)
    solve!(solver)
    @test eval_Eμ(0.0,solver.s) <= solver.s.opts.ϵ_tol
end
