include("../src/interior_point.jl")

n = 500
m = 100

x0 = ones(n)

xL = -Inf*ones(n)
xL[1] = -10.
xL[2] = -5.
xU = Inf*ones(n)
xU[5] = 20.

f_func(x) = x'*x
f, ∇f!, ∇²f! = objective_functions(f_func)

c_func(x) = x[1:m].^2 .- 1.2
c!, ∇c!, ∇²cy! = constraint_functions(c_func)

model = Model(n,m,xL,xU,f,∇f!,∇²f!,c!,∇c!,∇²cy!)

opts = Options{Float64}(kkt_solve=:symmetric,
                        iterative_refinement=true,
                        verbose=false)

s = InteriorPointSolver(x0,model,opts=opts)
@time solve!(s)

eval_step!(s.s)