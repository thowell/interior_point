mutable struct Inertia
    n::Int  # number of positve eigenvalues
    m::Int  # number of negative eigenvalues
    z::Int  # number of zero eigenvalues
end

mutable struct Solver{T}
    model::AbstractModel

    x::Vector{T}            # primal variables (n,)
    x⁺::Vector{T}
                       # number of upper bounds
    ΔxL::Vector{T}                  # lower bounds error (nL,)
    ΔxU::Vector{T}                  # upper bounds error (nU,)

    y::Vector{T}                    # dual variables (m,)

    zL::Vector{T}                   # duals for lower bound constraint (nL,)
    zU::Vector{T}                   # duals for upper bound constraint (nU,)

    σL::Vector{T}
    σU::Vector{T}

    φ::T                            # barrier objective value
    φ⁺::T                           # next barrier objective value
    ∇φ::Vector{T}                   # gradient of barrier objective

    ∇L::Vector{T}                   # gradient of the Lagrangian
    ∇²L::SparseMatrixCSC{T,Int}     # Hessian of the Lagrangian

    c::Vector{T}                    # constraint values
    c_soc::Vector{T}
    c_tmp::Vector{T}

    H::SparseMatrixCSC{T,Int}       # KKT matrix
    H_sym::SparseMatrixCSC{T,Int}   # Symmetric KKT matrix

    Hv::H_fullspace_views{T}
    Hv_sym::H_symmetric_views{T}

    h::Vector{T}                    # rhs of KKT system
    h_sym::Vector{T}                # rhs of symmetric KKT system

    LBL::Ma57{T} # ?
    inertia::Inertia

    d::Vector{T}                    # current step
    dx::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}   # current step in the primals
    dxL::SubArray{T,1,Array{T,1},Tuple{Array{Int,1}},false}   # current step in the primals with lower bounds
    dxU::SubArray{T,1,Array{T,1},Tuple{Array{Int,1}},false}   # current step in the primals with upper bounds
    dy::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}   # current step in the duals
    dxy::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}
    dzL::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}  # current step in the slack duals
    dzU::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}  # current step in the slack duals

    d_soc::Vector{T}
    dx_soc::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}   # current step in the primals
    dxL_soc::SubArray{T,1,Array{T,1},Tuple{Array{Int,1}},false}   # current step in the primals with lower bounds
    dxU_soc::SubArray{T,1,Array{T,1},Tuple{Array{Int,1}},false}   # current step in the primals with upper bounds
    dy_soc::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}   # current step in the duals
    dxy_soc::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}
    dzL_soc::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}  # current step in the slack duals
    dzU_soc::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}  # current step in the slack duals

    Δ::Vector{T}    # iterative refinement step
    Δ_xL::SubArray{T,1,Array{T,1},Tuple{Array{Int,1}},false}
    Δ_xU::SubArray{T,1,Array{T,1},Tuple{Array{Int,1}},false}
    Δ_xy::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}
    Δ_zL::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}
    Δ_zU::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}

    res::Vector{T}  # iterative refinement residual
    res_xL::SubArray{T,1,Array{T,1},Tuple{Array{Int,1}},false}
    res_xU::SubArray{T,1,Array{T,1},Tuple{Array{Int,1}},false}
    res_xy::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}
    res_zL::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}
    res_zU::SubArray{T,1,Array{T,1},Tuple{UnitRange{Int}},true}

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
    yA::SubArray{T,1,Array{T,1},Tuple{Array{Int,1}},false}
    cA::SubArray{T,1,Array{T,1},Tuple{Array{Int,1}},false}
    ∇cA::SubArray{T,2,SparseMatrixCSC{T,Int},Tuple{Array{Int,1},UnitRange{Int}},false}

    opts::Options{T}
end

function Solver(x0,model::AbstractModel;opts=Options{Float64}())
    n = model.n
    m = model.m
    mI = model.mI
    mE = model.mE
    mA = model.mA
    cI_idx = model.cI_idx
    cE_idx = model.cE_idx
    cA_idx = model.cA_idx
    xL = model.xL
    xU = model.xU
    xL_bool = model.xL_bool
    xU_bool = model.xU_bool
    xLs_bool = model.xLs_bool
    xUs_bool = model.xUs_bool
    nL = model.nL
    nU = model.nU

    # initialize primals
    x = zeros(n)
    x⁺ = zeros(n)

    ΔxL = zeros(nL)
    ΔxU = zeros(nU)

    if opts.relax_bnds
       relax_bounds_init!(xL,xU,xL_bool,xU_bool,n,opts.ϵ_tol)
    end

    for i = 1:n
        x[i] = init_x0(x0[i],xL[i],xU[i],opts.κ1,opts.κ2)
    end

    Dx = init_Dx(n)
    opts.nlp_scaling ? x .= Dx*x : nothing

    zL = opts.zL0*ones(nL)
    zU = opts.zU0*ones(nU)

    H = spzeros(n+m+nL+nU,n+m+nL+nU)
    h = zeros(n+m+nL+nU)

    H_sym = spzeros(n+m,n+m)
    h_sym = zeros(n+m)

    LBL = Ma57(H_sym)
    inertia = Inertia(0,0,0)

    ∇²L = spzeros(n,n)
    σL = zeros(nL)
    σU = zeros(nU)
    eval_∇c!(model,x)
    Dc = init_Dc(opts.g_max,get_∇c(model),m)

    μ = copy(opts.μ0)
    ρ = 1.0/μ
    λ = zeros(mA)
    τ = update_τ(μ,opts.τ_min)

    eval_∇f!(model,x)
    df = init_df(opts.g_max,get_∇f(model))

    φ = 0.
    φ⁺ = 0.
    ∇φ = zeros(n)

    ∇L = zeros(n)

    c = zeros(m)
    c_soc = zeros(m)
    c_tmp = zeros(m)

    eval_c!(model,x)
    get_c_scaled!(c,model,Dc,opts.nlp_scaling)


    d = zeros(n+m+nL+nU)
    d_soc = zeros(n+m+nL+nU)

    α = 1.0
    αz = 1.0
    α_max = 1.0
    α_min = 1.0
    α_soc = 1.0
    β = 1.0

    δ = zero(d)
    δw = 0.
    δw_last = 0.
    δc = 0.

    y = zeros(m)

    opts.y_init_ls ? init_y!(y,H_sym,h_sym,d,zL,zU,get_∇f(model),get_∇c(model),n,m,xL_bool,xU_bool,opts.y_max) : zeros(m)

    sd = init_sd(y,[zL;zU],n,m,opts.s_max)
    sc = init_sc([zL;zU],n,opts.s_max)

    filter = Tuple[]

    j = 0
    k = 0
    l = 0
    p = 0
    t = 0

    small_search_direction_cnt = 0

    restoration = false
    DR = spzeros(0,0)

    x_copy = zeros(n)
    y_copy = zeros(m)
    zL_copy = zeros(nL)
    zU_copy = zeros(nU)
    d_copy = zero(d)

    Fμ = zeros(n+m+nL+nU)

    idx = indices(n,m,nL,nU,
            xL_bool,xU_bool,xLs_bool,xUs_bool,
            n,
            m,mI,mE,mA,
            cI_idx,cE_idx,cA_idx)

    idx_r = restoration_indices()

    fail_cnt = 0

    Hv = H_fullspace_views(H,idx)
    Hv_sym = H_symmetric_views(H_sym,idx)


    yA = view(y,cA_idx)
    cA = view(c,cA_idx)
    ∇cA = view(model.∇c,cA_idx,idx.x)

    θ = norm(c,1)
    θ⁺ = copy(θ)
    θ_min = init_θ_min(θ)
    θ_max = init_θ_max(θ)

    θ_soc = 0.

    dx = view(d,idx.x)
    dxL = view(d,idx.xL)
    dxU = view(d,idx.xU)
    dy = view(d,idx.y)
    dxy = view(d,idx.xy)
    dzL = view(d,idx.zL)
    dzU = view(d,idx.zU)

    dx_soc = view(d_soc,idx.x)
    dxL_soc = view(d_soc,idx.xL)
    dxU_soc = view(d_soc,idx.xU)
    dy_soc = view(d_soc,idx.y)
    dxy_soc = view(d_soc,idx.xy)
    dzL_soc = view(d_soc,idx.zL)
    dzU_soc = view(d_soc,idx.zU)

    Δ = zero(d)
    Δ_xL = view(Δ,idx.xL)
    Δ_xU = view(Δ,idx.xU)
    Δ_xy = view(Δ,idx.xy)
    Δ_zL = view(Δ,idx.zL)
    Δ_zU = view(Δ,idx.zU)

    res = zero(d)
    res_xL = view(res,idx.xL)
    res_xU = view(res,idx.xU)
    res_xy = view(res,idx.xy)
    res_zL = view(res,idx.zL)
    res_zU = view(res,idx.zU)

    Solver(model,
           x,x⁺,
           ΔxL,ΔxU,
           y,
           zL,zU,σL,σU,
           φ,φ⁺,∇φ,
           ∇L,∇²L,
           c,c_soc,c_tmp,
           H,H_sym,
           Hv,Hv_sym,
           h,h_sym,
           LBL,inertia,
           d,dx,dxL,dxU,dy,dxy,dzL,dzU,
           d_soc,dx_soc,dxL_soc,dxU_soc,dy_soc,dxy_soc,dzL_soc,dzU_soc,
           Δ,Δ_xL,Δ_xU,Δ_xy,Δ_zL,Δ_zU,
           res,res_xL,res_xU,res_xy,res_zL,res_zU,
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
           ρ,λ,yA,cA,∇cA,
           opts)
end

"""
    eval_Eμ(x, y, zL, zU, ∇xL, ∇xU, c, ∇L, μ, sd, sc, ρ, λ, yA, cA)
    eval_Eμ(solver::Solver)

Evaluate the optimality error.
"""
function eval_Eμ(zL,zU,ΔxL,ΔxU,c,∇L,μ,sd,sc,ρ,λ,yA,cA)
    return max(norm(∇L,Inf)/sd,
               norm(c,Inf),
               norm(cA + 1.0/ρ*(λ - yA),Inf),
               norm(ΔxL.*zL .- μ,Inf)/sc,
               norm(ΔxU.*zU .- μ,Inf)/sc)
end

eval_Eμ(μ,s::Solver) = eval_Eμ(s.zL,s.zU,s.ΔxL,s.ΔxU,s.c[s.model.cA_idx .== 0],s.∇L,μ,s.sd,s.sc,s.ρ,s.λ,s.yA,s.cA)

"""
    eval_bounds!(s::Solver)

Evaluate the bound constraints and their sigma values
"""
function eval_bounds!(s::Solver)
    s.ΔxL .= (s.x - s.model.xL)[s.model.xL_bool]
    s.ΔxU .= (s.model.xU - s.x)[s.model.xU_bool]

    s.σL .= s.zL./s.ΔxL
    s.σU .= s.zU./s.ΔxU
    return nothing
end

"""
    eval_objective!(s::Solver)

Evaluate the objective value and it's first and second-order derivatives
"""
function eval_objective!(s::Solver)
    eval_∇f!(s.model,s.x)
    eval_∇²f!(s.model,s.x)
    return nothing
end

function get_f_scaled(x,s::Solver)
    s.opts.nlp_scaling ? s.df*get_f(s.model,x) : get_f(s.model,x)
end


"""
    eval_constraints!(s::Solver)

Evaluate the constraints and their first and second-order derivatives. Also compute the
constraint residual `θ`.
"""
function eval_constraints!(s::Solver)
    eval_c!(s.model,s.x)
    get_c_scaled!(s.c,s)

    eval_∇c!(s.model,s.x)
    eval_∇²cy!(s.model,s.x,s.y)

    s.θ = norm(s.c,1)
    return nothing
end

function get_c_scaled!(c,model,Dc,nlp_scaling)
    nlp_scaling && c .= Dc*get_c(model)
    return nothing
end
function get_c_scaled!(c,s::Solver)
    get_c_scaled!(c,s.model,s.Dc,s.opts.nlp_scaling)
end

"""
    eval_lagrangian!(s::Solver)

Evaluate the first and second derivatives of the Lagrangian
"""
function eval_lagrangian!(s::Solver)
    s.∇L .= get_∇f(s.model)
    s.∇L .+= get_∇c(s.model)'*s.y
    s.∇L[s.idx.xL] -= s.zL
    s.∇L[s.idx.xU] += s.zU

    s.∇²L .= get_∇²f(s.model) + get_∇²cy(s.model)

    # damping
    if s.opts.single_bnds_damping
        κd = s.opts.κd
        μ = s.μ
        s.∇L[s.idx.xLs] .+= κd*μ
        s.∇L[s.idx.xUs] .-= κd*μ
    end
    return nothing
end

"""
    eval_barrier(s::Solver)

Evaluate barrier objective and it's gradient
"""
function eval_barrier!(s::Solver)
    s.φ = get_f_scaled(s.x,s)
    s.φ -= s.μ*sum(log.(s.ΔxL))
    s.φ -= s.μ*sum(log.(s.ΔxU))

    s.φ += s.λ'*s.cA + 0.5*s.ρ*s.cA'*s.cA

    s.∇φ .= get_∇f(s.model)
    s.∇φ[s.idx.xL] -= s.μ./s.ΔxL
    s.∇φ[s.idx.xU] += s.μ./s.ΔxU

    s.∇φ .+= s.∇cA'*(s.λ + s.ρ*s.cA)

    # damping
    if s.opts.single_bnds_damping
        κd = s.opts.κd
        μ = s.μ
        s.φ += κd*μ*sum((s.x - s.model.xL)[s.idx.xLs])
        s.φ += κd*μ*sum((s.model.xU - s.x)[s.idx.xUs])
        s.∇φ[s.idx.xLs] .+= κd*μ
        s.∇φ[s.idx.xUs] .-= κd*μ
    end
    return nothing
end

"""
    eval_step!(s::Solver)

Evaluate all critical values for the current iterate stored in `s.x` and `s.y`, including
bound constraints, objective, constraints, Lagrangian, and barrier objective, and their
required derivatives.
"""
function eval_step!(s::Solver)
    eval_bounds!(s)
    eval_objective!(s)
    eval_constraints!(s)
    eval_lagrangian!(s)
    eval_barrier!(s)
    return nothing
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
    s.ΔxL .= (s.x - s.model.xL)[s.model.xL_bool]
    s.ΔxU .= (s.model.xU - s.x)[s.model.xU_bool]

    for i = 1:s.model.nL
        s.zL[i] = reset_z(s.zL[i],s.ΔxL[i],s.μ,s.opts.κΣ)
    end

    for i = 1:s.model.nU
        s.zU[i] = reset_z(s.zU[i],s.ΔxU[i],s.μ,s.opts.κΣ)
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
    # QUESTION: are these scalars? -yes
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
    eval_c!(s.model,x)
    get_c_scaled!(s.c_tmp,s)
    return norm(s.c_tmp,1)
end

"""
    barrier(x, xL, xU, xL_bool, xU_bool, xLs_bool xUs_bool, μ, κd, f, ρ, yA, cA)
    barrier(x, s::Solver)

Calculate the barrier objective function. When called using the solver, re-calculates the
    objective `f` and the constraints `c`.
"""
function barrier(x,xL,xU,xL_bool,xU_bool,xLs_bool,xUs_bool,μ,κd,f,ρ,yA,cA)
    # QUESTION:
    return (f - μ*sum(log.((x - xL)[xL_bool])) - μ*sum(log.((xU - x)[xU_bool]))
        + κd*μ*sum((x - xL)[xLs_bool]) + κd*μ*sum((xU - x)[xUs_bool])
        + yA'*cA + 0.5*ρ*cA'*cA)
end

function barrier(x,s::Solver)
    eval_c!(s.model,x)
    get_c_scaled!(s.c_tmp,s)

    return barrier(x,s.model.xL,s.model.xU,s.model.xL_bool,s.model.xU_bool,s.model.xLs_bool,
        s.model.xUs_bool,s.μ,s.opts.single_bnds_damping ? s.opts.κd : 0.,
        get_f_scaled(x,s),
        s.ρ,s.λ,s.c_tmp[s.model.cA_idx])
end

"""
    accept_step!(s::Solver)

Accept the current step, copying the candidate primals and duals into the current iterate.
"""
function accept_step!(s::Solver)
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

function relax_bounds!(s::Solver)
    for i in s.idx.xLs
        if s.x[i] - s.model.xL[i] < s.opts.ϵ_mach*s.μ
            s.model.xL[i] -= (s.opts.ϵ_mach^0.75)*max(1.0,s.model.xL[i])
            @warn "lower bound needs to be relaxed"
        end
    end

    for i in s.idx.xUs
        if s.model.xU[i] - s.x[i] < s.opts.ϵ_mach*s.μ
            s.model.xU[i] += (s.opts.ϵ_mach^0.75)*max(1.0,s.model.xU[i])
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

function InteriorPointSolver(x0,model::AbstractModel;opts=Options{Float64}()) where T
    s = Solver(x0,model,opts=opts)
    s̄ = RestorationSolver(s)

    InteriorPointSolver(s,s̄)
end
