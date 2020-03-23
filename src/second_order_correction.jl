function second_order_correction(s::Solver)
    s.p = 1
    θ_soc = θ(s.x,s)
    c_soc = s.α_max*s.c_func(s.x) + s.c_func(s.x + s.α_max*s.d[1:s.n])
    s.h[s.n .+ (1:s.m)] .= c_soc
    s.d_soc = -s.H\s.h

    s.α_soc = 1.0
    while !fraction_to_boundary_bnds(s.x,s.xl,s.xu,s.d_soc[1:s.n],s.α_soc,s.τ)
        s.α_soc *= 0.5
        println("α = $(s.α_max)")
        if s.α_soc < s.α_min
            error("α < α_min")
        end
    end

    while true
        if check_filter(θ(s.x + s.α_soc*s.d_soc[1:s.n],s),barrier(s.x + s.α_soc*s.d_soc[1:s.n],s),s)
            if (θ(s.x,s) < s.θ_min && switching_condition(s))
                if armijo(s.x + s.α_soc*s.d_soc[1:s.n],s)
                    s.update = :soc
                    s.α = s.α_soc
                    break
                end
            # case 2
            else
                if sufficient_progress(s)
                    s.update = :soc
                    s.α = s.α_soc
                    break
                end
            end
        end

        if s.p == s.opts.p_max || θ(s.x + s.α_soc*s.d_soc[1:s.n],s) > s.opts.κ_soc*θ_soc
            @warn "second order correction failure"
            break
        end

        s.p += 1

        θ_soc = θ(s.x + s.α_soc*s.d_soc[1:s.n],s)
        s.c_soc = s.α_soc*s.c_soc + s.c_func(s.x + s.α_soc*s.d_soc[1:s.n])

        s.h[s.n .+ (1:s.m)] .= c_soc
        s.d_soc = -s.H\s.h

        s.α_soc = 1.0
        while !fraction_to_boundary_bnds(s.x,s.xl,s.xu,s.d_soc[1:s.n],s.α_soc,s.τ)
            s.α_soc *= 0.5
            println("α = $(s.α_max)")
            if s.α_soc < s.α_min
                error("α_soc < α_min")
            end
        end
    end

    if s.update == :soc
        println("second order correction: success")
        return true
    else
        println("second order correction: failure")
        return false
    end
end
