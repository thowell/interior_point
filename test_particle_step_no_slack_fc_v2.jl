include("src/interior_point.jl")

nc = 1
nf = 2
nq = 3
nu = 2
nβ = nc*nf

nx = nq+nu+nc+nβ+nc+nc+2nc
np = nq+nβ+5nc

dt = 0.1

M(q) = 1.0*Matrix(I,nq,nq)
P(q) = [1. 0. 0.;0. 1. 0.]
G(q) = [0; 0; 9.8]

# P(q) = [1. 0. 0.;
#      0. 1. 0.;
#      -1. 0. 0.;
#      0. -1. 0.]

N(q) = [0; 0; 1]

qpp = [0., 0., .15]
v0 = [0., 0., 0.]
v1 = v0 - G(qpp)*dt
qp = qpp + 0.5*dt*(v0 + v1)

v2 = v1 - G(qp)*dt
q1 = qp + 0.5*dt*(v1 + v2)

qf = [0.; 0.; 0.]
uf = [0.; 0.]

W = 10.0*Matrix(I,nq,nq)
w = -W*qf
R = 1.0e-1*Matrix(I,nu,nu)
r = -R*uf
obj_c = 0.5*qf'*W*qf + 0.5*uf'*R*uf

function unpack(x)
    q = x[1:nq]
    u = x[nq .+ (1:nu)]
    λ = x[nq+nu+nc]
    β = x[nq+nu+nc .+ (1:nβ)]
    ψ = x[nq+nu+nc+nβ+nc]
    η = x[nq+nu+nc+nβ+nc+nc]
    sϕ = x[nq+nu+nc+nβ+nc+nc+nc]
    sfc = x[nq+nu+nc+nβ+nc+nc+2nc]

    return q,u,λ,β,ψ,η,sϕ,sfc
end

function f_func(x)
    q,u,λ,β,ψ,η,sϕ,sfc = unpack(x)
    return 0.5*q'*W*q + w'*q + 0.5*u'*R*u + r'*u + obj_c
end
f, ∇f!, ∇²f! = objective_functions(f_func)

function c_func(x)
    q,u,λ,β,ψ,η,sϕ,sfc = unpack(x)
    [M(q)*(2*qp - qpp - q)/dt - G(q)*dt + B(q)*u + P(q)'*β + N(q)*λ;
     P(q)*(q-qp)/dt + 2.0*β*ψ;
     sϕ - N(q)'*q;
     sfc - ((0.5*λ)^2 - β'*β);
     ψ - η;
     λ*sϕ;
     sfc*η]
end
c!, ∇c!, ∇²cλ! = constraint_functions(c_func)

n = nx
m = np
xL = zeros(nx)
xL[1:(nq+nu)] .= -Inf
xL[nq+nu+nc .+ (1:nβ)] .= -Inf
xL[nq+nu+nc+nβ+nc] = -Inf
xU = Inf*ones(nx)

model = Model(n,m,xL,xU,f,∇f!,∇²f!,c!,∇c!,∇²cλ!)

c_relax = ones(Bool,model.m)
c_relax[1:nq+nβ+nc+nc+nc] .= 0
q0 = q1
u0 = 1.0e-3*rand(nu)
λ0 = 1.0e-3*rand(1)[1]
β0 = 1.0e-3*rand(nβ)
ψ0 = 1.0e-3*rand(1)[1]
η0 = 1.0e-3*rand(nβ)
s0 = 1.0e-3*rand(1)[1]
x0 = [q0;u0;λ0;β0;ψ0;η0; N(q0)'*q0;(0.5*λ0)^2 - β0'*β0]

opts = Options{Float64}(kkt_solve=:symmetric,
                        iterative_refinement=true,
                        max_iter=500,
                        relax_bnds=true,
                        λ_init_ls=true,
                        ϵ_tol=1.0e-8)

s = InteriorPointSolver(x0,model,c_relax=c_relax,opts=opts)
@time solve!(s,verbose=true)
norm(c_func(s.s.x)[c_relax .== 0],1)
norm(c_func(s.s.x)[c_relax],1)

# s_new = InteriorPointSolver(s.s.x,model,c_relax=c_relax,opts=opts)
# s_new.s.λ .= s.s.λ
# s_new.s.λ_al .= s.s.λ_al + s.s.ρ*s.s.c[c_relax]
# s_new.s.ρ = s.s.ρ*10.0
# solve!(s_new,verbose=true)
# s = s_new
# norm(c_func(s.s.x)[c_relax .== 0],1)
# norm(c_func(s.s.x)[c_relax],1)

q,u,λ,β,ψ,η,sϕ,sfc = unpack(s.s.x)
λ
β
(0.5*λ)^2 - β'*β
sfc
sϕ

(q-q1)./norm(q-q1)
β./norm(β)