"""
    inertia_correction!(s::Solver)

Implementation of Algorithm IC. Increase the regularization of the symmetric KKT system
until it has the correct inertia.
"""
function inertia_correction!(s::Solver)

    initialize_regularization!(s.linear_solver,s)

    # IC-1
    factorize_regularized_matrix!(s)

    if inertia(s)
        return nothing
    end

    # IC-2
    if s.linear_solver.inertia.zero != 0
        s.options.verbose ? (@warn "$(s.linear_solver.inertia.zero) zero eigen values - rank deficient constraints") : nothing
        s.dual_regularization = s.options.dual_regularization * s.central_path^s.options.exponent_dual_regularization
    end

    # IC-3
    if s.primal_regularization_last == 0.
        s.primal_regularization = s.options.primal_regularization_initial
    else
        s.primal_regularization = max(s.options.min_regularization, s.options.scaling_regularization_last * s.primal_regularization_last)
    end

    while !inertia(s)

        # IC-4
        factorize_regularized_matrix!(s)

        if inertia(s)
            break
        else
            # IC-5
            if s.primal_regularization_last == 0
                s.primal_regularization = s.options.scaling_regularization_initial * s.primal_regularization
            else
                s.primal_regularization = s.options.scaling_regularization * s.primal_regularization
            end
        end

        # IC-6
        if s.primal_regularization > s.options.max_regularization
            # TODO: handle inertia correction failure gracefully
            error("inertia correction failure")
        end
    end

    s.primal_regularization_last = s.primal_regularization

    return nothing
end

"""
    factorize_kkt!(s::Solver)

Compute the LDL factorization of the symmetric KKT matrix and update the inertia values.
Uses the Ma57 algorithm from HSL.
"""
function factorize_regularized_matrix!(s::Solver)
    s.regularization[s.idx.x] .= s.primal_regularization
    s.regularization[s.idx.y] .= -s.dual_regularization

    s.σL .= s.ΔzL./(s.ΔxL .- s.dual_regularization)

    kkt_hessian_symmetric!(s)
    factorize!(s.linear_solver, s.H_sym + Diagonal(view(s.regularization, s.idx.xy)))
    compute_inertia!(s.linear_solver, s)

    return nothing
end

"""
    inertia(s::Solver)

Check if the inertia of the symmetric KKT system is correct. The inertia is defined as the
    tuple `(n,m,z)` where
- `n` is the number of postive eigenvalues. Should be equal to the number of primal variables.
- `m` is the number of negative eignvalues. Should be equal to the number of dual variables
- `z` is the number of zero eigenvalues. Should be 0.
"""
inertia(s::Solver) = (s.linear_solver.inertia.negative == s.model.n
                   && s.linear_solver.inertia.positive == s.model.m
                   && s.linear_solver.inertia.zero     == 0)
