mutable struct Inertia
    n::Int  # number of positve eigenvalues
    m::Int  # number of negative eigenvalues
    z::Int  # number of zero eigenvalues
end

mutable struct Solver{T}
    model::AbstractModel

    x::Vector{T}            # primal variables (n,)
    x⁺::Vector{T}
    x_soc::Vector{T}

    xL::Vector{T}                   # lower bound
    xU::Vector{T}                   # upper bounds
    xL_bool::Vector{Bool}           # which are lower-bounded
    xU_bool::Vector{Bool}           # which are upper-bounded
    xLs_bool::Vector{Bool}          # which are upper slacks (m,)
    xUs_bool::Vector{Bool}          # which are lower slacks (m,)
    nL::Int                         # number of lower bounds
    nU::Int                         # number of upper bounds
    ΔxL::Vector{T}                  # lower bounds error (nL,)
    ΔxU::Vector{T}                  # upper bounds error (nU,)

    y::Vector{T}                    # dual variables (m,)

    zL::Vector{T}                   # duals for lower bound constraint (nL,)
    zU::Vector{T}                   # duals for upper bound constraint (nU,)

    σL::Vector{T}
    σU::Vector{T}

    f::T                            # objective value
    ∇f::Vector{T}                   # objective gradient
    ∇²f::SparseMatrixCSC{T,Int}     # objective hessian

    φ::T                            # barrier objective value
    φ⁺::T                           # next barrier objective value
    ∇φ::Vector{T}                   # gradient of barrier objective

    ∇L::Vector{T}                   # gradient of the Lagrangian?
    ∇²L::SparseMatrixCSC{T,Int}     # Hessian of the Lagrangian?

    c::Vector{T}                    # constraint values
    c_soc::Vector{T}
    c_tmp::Vector{T}
    ∇c::SparseMatrixCSC{T,Int}      # constraint Jacobian
    ∇²cy::SparseMatrixCSC{T,Int}    # second-order constraint Jacobian. Jacobian of `∇c'y`

    H::SparseMatrixCSC{T,Int}       # KKT matrix
    H_sym::SparseMatrixCSC{T,Int}   # Symmetric KKT matrix

    Hv::H_unreduced_views{T}
    Hv_sym::H_symmetric_views{T}

    h::Vector{T}                    # rhs of KKT system
    h_sym::Vector{T}                # rhs of symmetric KKT system

    LBL::Ma57{T} # ?
    inertia::Inertia

    d::Vector{T}                    # current step
    d_soc::Vector{T}

    dx::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}   # current step in the primals
    dy::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}   # current step in the duals
    dzL::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}  # current step in the slack duals
    dzU::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}  # current step in the slack duals

    Δ::Vector{T}    # ?
    res::Vector{T}  # ?

    # Line search values
    α::T
    αz::T
    α_max::T
    α_min::T
    α_soc::T
    β::T

    # Regularization
    δ::Vector{T}
    δw::T
    δw_last::T
    δc::T

    # Constraint violation
    θ::T          # 1-norm of constraint violation
    θ⁺::T
    θ_min::T
    θ_max::T
    θ_soc::T

    # Scaling factors
    sd::T
    sc::T

    # Penalty values
    μ::T
    τ::T
    filter::Vector{Tuple}

    # iteration counts
    j::Int   # central path iteration (outer loop)
    k::Int   # barrier problem iteration
    l::Int   # line search
    p::Int   # second order corrections
    t::Int
    small_search_direction_cnt::Int

    restoration::Bool
    DR::SparseMatrixCSC{T,Int}  # QUESTION: isn't this Diagonal?

    x_copy::Vector{T}
    y_copy::Vector{T}
    zL_copy::Vector{T}
    zU_copy::Vector{T}
    d_copy::Vector{T}

    Fμ::Vector{T}

    idx::Indices
    idx_r::RestorationIndices

    fail_cnt::Int

    Dx::SparseMatrixCSC{T,Int}
    df::T
    Dc::SparseMatrixCSC{T,Int}

    ρ::T
    λ::Vector{T}
    y_al::SubArray{T,1,Array{T,1},Tuple{Array{Int,1}},false}
    c_al::SubArray{T,1,Array{T,1},Tuple{Array{Int,1}},false}
    ∇c_al::SubArray{T,2,SparseMatrixCSC{T,Int},Tuple{Array{Int,1},UnitRange{Int}},false}
    c_al_idx::Vector{Bool}

    opts::Options{T}
end

function Solver(x0,model::AbstractModel;c_al_idx=ones(Bool,model.m), opts=Options{Float64}())
    # QUESTION: defaults to setting all constraints to AL constraints?

    # initialize primals
    x = zeros(model.n)
    x⁺ = zeros(model.n)
    x_soc = zeros(model.n)

    # primal bounds
    xL = copy(model.xL)
    xU = copy(model.xU)

    xL_bool = zeros(Bool,model.n)
    xU_bool = zeros(Bool,model.n)
    xLs_bool = zeros(Bool,model.n)
    xUs_bool = zeros(Bool,model.n)

    for i = 1:model.n
        # boolean bounds
        if xL[i] < -1.0*opts.bnd_tol
            xL_bool[i] = 0
        else
            xL_bool[i] = 1
        end

        if xU[i] > opts.bnd_tol
            xU_bool[i] = 0
        else
            xU_bool[i] = 1
        end

        # single bounds
        if xL_bool[i] == 1 && xU_bool[i] == 0
            xLs_bool[i] = 1
        else
            xLs_bool[i] = 0
        end

        if xL_bool[i] == 0 && xU_bool[i] == 1
            xUs_bool[i] = 1
        else
            xUs_bool[i] = 0
        end
    end

    nL = convert(Int,sum(xL_bool))
    nU = convert(Int,sum(xU_bool))

    ΔxL = zeros(nL)
    ΔxU = zeros(nU)

    if opts.relax_bnds
       # relax bounds
       for i in (1:model.n)[xL_bool]
           xL[i] = relax_bnd(xL[i],opts.ϵ_tol,:L)
       end
       for i in (1:model.n)[xU_bool]
           xU[i] = relax_bnd(xU[i],opts.ϵ_tol,:U)
       end
    end

    for i = 1:model.n
        x[i] = init_x0(x0[i],xL[i],xU[i],opts.κ1,opts.κ2)
    end

    Dx = init_Dx(model.n)
    opts.nlp_scaling ? x .= Dx*x : nothing

    zL = opts.zL0*ones(nL)
    zU = opts.zU0*ones(nU)

    H = spzeros(model.n+model.m+nL+nU,model.n+model.m+nL+nU)
    h = zeros(model.n+model.m+nL+nU)

    H_sym = spzeros(model.n+model.m,model.n+model.m)
    h_sym = zeros(model.n+model.m)

    LBL = Ma57(H_sym)
    inertia = Inertia(0,0,0)

    ∇²L = spzeros(model.n,model.n)
    σL = zeros(nL)
    σU = zeros(nU)
    ∇c = spzeros(model.m,model.n)
    model.∇c_func!(∇c,x,model)
    Dc = init_Dc(opts.g_max,∇c,model.m)

    f = model.f_func(x,model)
    ∇f = zeros(model.n)
    model.∇f_func!(∇f,x,model)
    df = init_df(opts.g_max,∇f)
    opts.nlp_scaling ? f *= df : nothing

    ∇²f = model.∇²f

    φ = 0.
    φ⁺ = 0.
    ∇φ = zeros(model.n)

    ∇L = zeros(model.n)

    c = zeros(model.m)
    model.c_func!(c,x,model)
    opts.nlp_scaling ? c .= Dc*c : nothing

    c_soc = zeros(model.m)
    c_tmp = zeros(model.m)

    ∇²cy = spzeros(model.n,model.n)

    d = zeros(model.n+model.m+nL+nU)
    d_soc = zeros(model.n+model.m+nL+nU)

    dx = view(d,1:model.n)
    dy = view(d,model.n .+ (1:model.m))
    dzL = view(d,model.n+model.m .+ (1:nL))
    dzU = view(d,model.n+model.m+nL .+ (1:nU))

    Δ = zero(d)
    res = zero(d)

    μ = copy(opts.μ0)

    α = 1.0
    αz = 1.0
    α_max = 1.0
    α_min = 1.0
    α_soc = 1.0
    β = 1.0

    τ = update_τ(μ,opts.τ_min)

    δ = zero(d)
    δw = 0.
    δw_last = 0.
    δc = 0.

    y = zeros(model.m)

    opts.y_init_ls ? init_y!(y,H_sym,h_sym,d,zL,zU,∇f,∇c,model.n,model.m,xL_bool,xU_bool,opts.y_max) : zeros(model.m)

    sd = init_sd(y,[zL;zU],model.n,model.m,opts.s_max)
    sc = init_sc([zL;zU],model.n,opts.s_max)

    filter = Tuple[]

    j = 0
    k = 0
    l = 0
    p = 0
    t = 0

    small_search_direction_cnt = 0

    restoration = false
    DR = spzeros(0,0)

    x_copy = zeros(model.n)
    y_copy = zeros(model.m)
    zL_copy = zeros(nL)
    zU_copy = zeros(nU)
    d_copy = zero(d)

    Fμ = zeros(model.n+model.m+nL+nU)

    idx = indices(model.n,model.m,nL,nU,xL_bool,xU_bool,xLs_bool,xUs_bool,c_al_idx)
    idx_r = restoration_indices()

    fail_cnt = 0

    Hv = H_unreduced_views(H,idx)
    Hv_sym = H_symmetric_views(H_sym,idx)

    ρ = 1.0/μ
    λ = zeros(sum(c_al_idx))
    y_al = view(y,c_al_idx)
    c_al = view(c,c_al_idx)
    ∇c_al = view(∇c,c_al_idx,idx.x)

    θ = norm(c,1)
    θ⁺ = copy(θ)
    θ_min = init_θ_min(θ)
    θ_max = init_θ_max(θ)

    θ_soc = 0.

    Solver(model,
           x,x⁺,x_soc,
           xL,xU,xL_bool,xU_bool,xLs_bool,xUs_bool,nL,nU,ΔxL,ΔxU,
           y,
           zL,zU,σL,σU,
           f,∇f,∇²f,
           φ,φ⁺,∇φ,
           ∇L,∇²L,
           c,c_soc,c_tmp,∇c,∇²cy,
           H,H_sym,
           Hv,Hv_sym,
           h,h_sym,
           LBL,inertia,
           d,d_soc,dx,dy,dzL,dzU,Δ,res,
           α,αz,α_max,α_min,α_soc,β,
           δ,δw,δw_last,δc,
           θ,θ⁺,θ_min,θ_max,θ_soc,
           sd,sc,
           μ,τ,
           filter,
           j,k,l,p,t,small_search_direction_cnt,
           restoration,DR,
           x_copy,y_copy,zL_copy,zU_copy,d_copy,
           Fμ,
           idx,idx_r,
           fail_cnt,
           Dx,df,Dc,
           ρ,λ,y_al,c_al,∇c_al,c_al_idx,
           opts)
end

"""
    eval_Eμ(x, y, zL, zU, ∇xL, ∇xU, c, ∇L, μ, sd, sc, ρ, λ, y_al, c_al)
    eval_Eμ(solver::Solver)

Evaluate the optimality error.
"""
function eval_Eμ(x,y,zL,zU,ΔxL,ΔxU,c,∇L,μ,sd,sc,ρ,λ,y_al,c_al)
    # QUESTION: unused x, y, zL, zU?
    return max(norm(∇L,Inf)/sd,
               norm(c,Inf),
               norm(c_al + 1.0/ρ*(λ - y_al),Inf),
               norm(ΔxL.*zL .- μ,Inf)/sc,
               norm(ΔxU.*zU .- μ,Inf)/sc)
end

eval_Eμ(μ,s::Solver) = eval_Eμ(s.x,s.y,s.zL,s.zU,s.ΔxL,s.ΔxU,s.c[s.c_al_idx .== 0],s.∇L,μ,s.sd,s.sc,s.ρ,s.λ,s.y_al,s.c_al)

"""
    eval_bounds!(s::Solver)

Evaluate the bound constraints and their sigma values
"""
function eval_bounds!(s::Solver)
    s.ΔxL .= (s.x - s.xL)[s.xL_bool]
    s.ΔxU .= (s.xU - s.x)[s.xU_bool]

    s.σL .= s.zL./s.ΔxL
    s.σU .= s.zU./s.ΔxU
    return nothing
end

"""
    eval_objective!(s::Solver)

Evaluate the objective value and it's first and second-order derivatives
"""
function eval_objective!(s::Solver)
    # QUESTION: you don't apply scaling to the derivatives?
    # TODO: when applicable, evaluate all of these with a single call to ForwardDiff
    s.f = s.opts.nlp_scaling ? s.df*s.model.f_func(s.x,s.model) : s.model.f_func(s.x,s.model)
    s.model.∇f_func!(s.∇f,s.x,s.model)
    s.model.∇²f_func!(s.∇²f,s.x,s.model)
    return nothing
end


"""
    eval_constraints!(s::Solver)

Evaluate the constraints and their first and second-order derivatives. Also compute the
constraint residual `θ`.
"""
function eval_constraints!(s::Solver)
    s.model.c_func!(s.c,s.x,s.model)
    s.opts.nlp_scaling ? (s.c .= s.Dc*s.c) : nothing

    s.model.∇c_func!(s.∇c,s.x,s.model)
    s.model.∇²cy_func!(s.∇²cy,s.x,s.y,s.model)

    s.θ = norm(s.c,1)
    return nothing
end

"""
    eval_lagrangian!(s::Solver)

Evaluate the first and second derivatives of the Lagrangian
"""
function eval_lagrangian!(s::Solver)
    s.∇L .= s.∇f
    s.∇L .+= s.∇c'*s.y
    s.∇L[s.xL_bool] -= s.zL
    s.∇L[s.xU_bool] += s.zU

    s.∇²L .= s.∇²f + s.∇²cy

    # damping
    if s.opts.single_bnds_damping
        κd = s.opts.κd
        μ = s.μ
        s.∇L[s.xLs_bool] .+= κd*μ
        s.∇L[s.xUs_bool] .-= κd*μ
    end
    return nothing
end

"""
    eval_barrier(s::Solver)

Evaluate barrier objective and it's gradient
"""
function eval_barrier!(s::Solver)
    s.φ = s.f
    s.φ -= s.μ*sum(log.(s.ΔxL))
    s.φ -= s.μ*sum(log.(s.ΔxU))

    s.φ += s.λ'*s.c_al + 0.5*s.ρ*s.c_al'*s.c_al

    s.∇φ .= s.∇f
    s.∇φ[s.xL_bool] -= s.μ./s.ΔxL
    s.∇φ[s.xU_bool] += s.μ./s.ΔxU

    s.∇φ .+= s.∇c_al'*(s.λ + s.ρ*s.c_al)

    # damping
    if s.opts.single_bnds_damping
        κd = s.opts.κd
        μ = s.μ
        s.φ += κd*μ*sum((s.x - s.xL)[s.xLs_bool])
        s.φ += κd*μ*sum((s.xU - s.x)[s.xUs_bool])
        s.∇φ[s.xLs_bool] .+= κd*μ
        s.∇φ[s.xUs_bool] .-= κd*μ
    end
    return nothing
end

"""
    eval_iterate!(s::Solver)

Evaluate all critical values for the current iterate stored in `s.x` and `s.y`, including
bound constraints, objective, constraints, Lagrangian, and barrier objective, and their
required derivatives.
"""
function eval_iterate!(s::Solver)
    eval_bounds!(s)
    eval_objective!(s)
    eval_constraints!(s)
    eval_lagrangian!(s)
    eval_barrier!(s)
    return nothing
end

"""
    init_sd(y, z, n, m, s_max)

Calculate the scaling parameter for the dual variables
"""
function init_sd(y,z,n,m,s_max)
    sd = max(s_max,(norm(y,1) + norm(z,1))/(n+m))/s_max
    return sd
end

"""
    init_sc(z, n, s+max)

Calculate the scaling parameter for the constraints
"""
function init_sc(z,n,s_max)
    sc = max(s_max,norm(z,1)/n)/s_max
    return sc
end

"""
    update_μ(μ, κμ, θμ, ϵ_tol)
    update_μ(s::Solver)

Update the penalty parameter (Eq. 7) with constants κμ ∈ (0,1), θμ ∈ (1,2)
"""
update_μ(μ, κμ, θμ, ϵ_tol) = max(ϵ_tol/10.,min(κμ*μ,μ^θμ))
function update_μ!(s::Solver)
    s.μ = update_μ(s.μ, s.opts.κμ, s.opts.θμ, s.opts.ϵ_tol)
    return nothing
end

"""
    update_τ(μ, τ_min)
    update_τ(s::Solver)

Update the "fraction-to-boundary" parameter (Eq. 8) where τ_min ∈ (0,1) is it's minimum value.
"""
update_τ(μ,τ_min) = max(τ_min,1.0-μ)
function update_τ!(s::Solver)
    s.τ = update_τ(s.μ,s.opts.τ_min)
    return nothing
end

"""
    fraction_to_boundary(x, d, α, τ)

Check if the `x` satisfies the "fraction-to-boundary" rule (Eq. 15)
"""
fraction_to_boundary(x,d,α,τ) = all(x + α*d .>= (1 - τ)*x)
function fraction_to_boundary_bnds(x,xL,xU,xL_bool,xU_bool,d,α,τ)
    # TODO: get rid of this function and call the previous one with the currect values
    return all((xU-(x + α*d))[xU_bool] .>= (1 - τ)*(xU-x)[xU_bool]) && all(((x + α*d)-xL)[xL_bool] .>= (1 - τ)*(x-xL)[xL_bool])
end

"""
    reset_z(z, x, μ, κΣ)
    reset_z(s::Solver)

Reset the bound duals `z` according to (Eq. 16) to ensure global convergence, where `κΣ` is
some constant > 1, usually very large (e.g. 10^10).
"""
reset_z(z,x,μ,κΣ) = max(min(z,κΣ*μ/x),μ/(κΣ*x))

function reset_z!(s::Solver)
    for i = 1:s.nL
        s.zL[i] = reset_z(s.zL[i],((s.x - s.xL)[s.xL_bool])[i],s.μ,s.opts.κΣ)
    end

    for i = 1:s.nU
        s.zU[i] = reset_z(s.zU[i],((s.xU - s.x)[s.xU_bool])[i],s.μ,s.opts.κΣ)
    end
    return nothing
end

function init_θ_max(θ)
    θ_max = 1.0e4*max(1.0,θ)
    return θ_max
end

function init_θ_min(θ)
    θ_min = 1.0e-4*max(1.0,θ)
    return θ_min
end

"""
    init_x0(x, xL, xU, κ1, κ2)

Initilize the primal variables with a feasible guess wrt the bound constraints, projecting
the provided guess `x0` slightly inside of the feasible region, with `κ1`, `κ2` ∈ (0,0.5)
determining how far into the interior the value is projected.
"""
function init_x0(x,xL,xU,κ1,κ2)
    # QUESTION: are these scalars?
    pl = min(κ1*max(1.0,abs(xL)),κ2*(xU-xL))
    pu = min(κ1*max(1.0,abs(xU)),κ2*(xU-xL))

    # projection
    if x < xL+pl
        x = xL+pl
    elseif x > xU-pu
        x = xU-pu
    end
    return x
end

"""
    init_y!

Solve for the initial dual variables for the equality constraints (Eq. 36)
"""
function init_y!(y,H,h,d,zL,zU,∇f,∇c,n,m,xL_bool,xU_bool,y_max)

    if m > 0
        H[CartesianIndex.((1:n),(1:n))] .= 1.0
        H[1:n,n .+ (1:m)] .= ∇c'
        H[n .+ (1:m),1:n] .= ∇c

        h[1:n] = ∇f
        h[(1:n)[xL_bool]] -= zL
        h[(1:n)[xU_bool]] += zU
        h[n+1:end] .= 0.

        LBL = Ma57(H)
        ma57_factorize(LBL)

        d[1:(n+m)] .= ma57_solve(LBL,-h)
        y .= d[n .+ (1:m)]


        if norm(y,Inf) > y_max || any(isnan.(y))
            @warn "least-squares y init failure:\n y_max = $(norm(y,Inf))"
            y .= 0.
        end
    else
        y .= 0.
    end
    H .= 0.
    return nothing
end

"""
    θ(x, s::Solver)

Calculate the 1-norm of the constraints
"""
function θ(x,s::Solver)
    s.model.c_func!(s.c_tmp, x, s.model)
    if s.opts.nlp_scaling
        s.c_tmp .= s.Dc*s.c_tmp
    end
    return norm(s.c_tmp,1)
end

"""
    barrier(x, xL, xU, xL_bool, xU_bool, xLs_bool xUs_bool, μ, κd, f, ρ, y_al, c_al)
    barrier(x, s::Solver)

Calculate the barrier objective function. When called using the solver, re-calculates the
    objective `f` and the constraints `c`.
"""
function barrier(x,xL,xU,xL_bool,xU_bool,xLs_bool,xUs_bool,μ,κd,f,ρ,y_al,c_al)
    # QUESTION:
    return (f - μ*sum(log.((x - xL)[xL_bool])) - μ*sum(log.((xU - x)[xU_bool]))
        + κd*μ*sum((x - xL)[xLs_bool]) + κd*μ*sum((xU - x)[xUs_bool])
        + y_al'*c_al + 0.5*ρ*c_al'*c_al)
end

function barrier(x,s::Solver)
    s.f = s.model.f_func(x,s.model)

    s.model.c_func!(s.c_tmp,x,s.model)
    if s.opts.nlp_scaling
        s.c_tmp .= s.Dc*s.c_tmp
    end

    return barrier(x,s.xL,s.xU,s.xL_bool,s.xU_bool,s.xLs_bool,
        s.xUs_bool,s.μ,s.opts.single_bnds_damping ? s.opts.κd : 0.,
        s.opts.nlp_scaling ? s.df*s.f : s.f,
        s.ρ,s.λ,s.c_tmp[s.c_al_idx])
end

"""
    update!(s::Solver)

Accept the current step, copying the candidate primals and duals into the current iterate.
"""
function update!(s::Solver)
    s.x .= s.x⁺

    if s.opts.nlp_scaling
        s.x .= s.Dx*s.x
    end

    s.y .= s.y + s.α*s.dy
    s.zL .= s.zL + s.αz*s.dzL
    s.zU .= s.zU + s.αz*s.dzU
    return nothing
end

"""
    small_search_direction(s::Solver)

Check if the current step is small (Sec. 3.9).
"""
function small_search_direction(s::Solver)
    return (maximum(abs.(s.dx)./(1.0 .+ abs.(s.x))) < 10.0*s.opts.ϵ_mach)
end

"""
    relax_bnd(x_bnd, ϵ, bnd_type)

Relax the bound constraint `x_bnd` by ϵ, where `x_bnd` is a scalar. `bnd_type` is either
`:L` for lower bounds or `:U` for upper bounds.
"""
function relax_bnd(x_bnd, ϵ, bnd_type)
    if bnd_type == :L
        return x_bnd - ϵ*max(1.0,abs(x_bnd))
    elseif bnd_type == :U
        return x_bnd + ϵ*max(1.0,abs(x_bnd))
    else
        error("bound type error")
    end
end

"""
    relax_bnds!(s::Solver)

Relax the bounds in the solver slightly (Sec. 3.5)
"""
function relax_bnds!(s::Solver)
    for i in s.idx.xLs
        if s.x[i] - s.xL[i] < s.opts.ϵ_mach*s.μ
            s.xL[i] -= (s.opts.ϵ_mach^0.75)*max(1.0,s.xL[i])
            @warn "lower bound needs to be relaxed"
        end
    end

    for i in s.idx.xUs
        if s.xU[i] - s.x[i] < s.opts.ϵ_mach*s.μ
            s.xU[i] += (s.opts.ϵ_mach^0.75)*max(1.0,s.xU[i])
            @warn "upper bound needs to be relaxed"
        end
    end
end

"""
    InteriorPointSolver{T}

Complete interior point solver as described by the Ipopt paper.

# Fields
- `s`: interior point solver for the original problem
- `s`: interior point solver for the restoration phase
"""
struct InteriorPointSolver{T}
    s::Solver{T}
    s̄::Solver{T}
end

function InteriorPointSolver(x0,model::AbstractModel; c_al_idx=ones(Bool,model.m),opts=Options{Float64}()) where T
    s = Solver(x0,model,c_al_idx=c_al_idx,opts=opts)
    s̄ = RestorationSolver(s)

    InteriorPointSolver(s,s̄)
end

# QUESTION: why not just use `sparse(I,n,n)?`
# QUESTION: where are these used?
function init_Dx!(Dx,n)
    for i = 1:n
        Dx[i,i] = 1.0
    end
    return nothing
end

function init_Dx(n)
    Dx = spzeros(n,n)
    init_Dx!(Dx,n)
    return Dx
end


init_df(g_max,∇f) = min(1.0,g_max/norm(∇f,Inf))

function init_Dc!(Dc,g_max,∇c,m)
    for j = 1:m
        Dc[j,j] = min(1.0,g_max/norm(∇c[j,:],Inf))
    end
end

function init_Dc(g_max,∇c,m)
    Dc = spzeros(m,m)
    init_Dc!(Dc,g_max,∇c,m)
    return Dc
end
