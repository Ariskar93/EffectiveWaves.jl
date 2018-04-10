# Here we calculate the effective wavenumber and effective wave amplitudes, without any restriction to the volume fraction of particles and incident wave frequency.

Nn(n,x,y) = x*diffhankelh1(n,x)*besselj(n,y) - y*hankelh1(n,x)*diffbesselj(n,y)

function reflection_coefficient{T<:Number}(ω::T, medium::Medium{T}, species::Array{Specie{T}}; θ_inc::T = 0.0, kws...)
    (k_eff,θ_eff,As) = transmitted_planewave(ω, medium, species; θ_inc=θ_inc, kws...)
    θ_ref = pi - θ_eff - θ_inc
    k = ω/medium.c
    S = length(species); ho = Int((size(As,1)-1)/2)

    R = 2.0im/(k*cos(θ_inc)*(k*cos(θ_inc) + k_eff*cos(θ_eff)))
    R = R*sum(
        exp(im*n*θ_ref)*species[l].num_density*As[n+ho+1,l]*Zn(ω,species[l],medium,n)
    for n=-ho:ho, l=1:S)

    return R
end

function transmitted_planewave{T<:Number}(ω::T, medium::Medium{T}, species::Array{Specie{T}}; hankel_order = :auto, max_hankel_order = 10,
        radius_multiplier = 1.005,
        MaxTime=100., tol = 1e-8, θ_inc::T = 0.0,
        kws...)
    k = ω/medium.c
    S = length(species)
    @memoize Z_l_n(l,n) = Zn(ω,species[l],medium,n)

    as = radius_multiplier*[(s1.r + s2.r) for s1 in species, s2 in species]
    function M(keff,j,l,m,n)
        (n==m ? 1.0+im*0.0:0.0+im*0.0)*(j==l ? 1.0+im*0.0:0.0+im*0.0) + 2.0pi*species[l].num_density*Z_l_n(l,n)*
            Nn(n-m,k*as[j,l],keff*as[j,l])/(k^2.0-keff^2.0)
    end

    if hankel_order == :auto
        ho = -1 + sum([ tol .< norm([M(0.9*k + 0.1im,j,l,1,n) for j = 1:S, l = 1:S]) for n=0:max_hankel_order ])
    else ho = hankel_order
    end

    # this matrix is needed to calculate the eigenvectors
    MM(keff::Complex{T}) = reshape(
        [M(keff,j,l,m,n) for m in -ho:ho, j = 1:S, n in -ho:ho, l = 1:S]
    , ((2ho+1)*S, (2ho+1)*S))
    detMM2(keff_vec::Array{T}) = map(x -> real(x*conj(x)), det(MM(keff_vec[1]+im*keff_vec[2])))

    function detMM!(F,x)
        F[1] = abs(det(MM(x[1]+im*x[2])))
    end

    # use low frequency effective wavenumber as an initial guess
    (β_eff,ρ_eff) = effective_material_properties(medium, species)
    k0 = ω*sqrt(ρ_eff/β_eff)
    initial_k0 = [0.001*k0, 100.0*eps(T)]
    # initial_k0 = k0.*rand(2)

    # Alternative solvers
    # res = nlsolve(detMM!,initial_k_eff; iterations = 10000, factor=2.0)
    # k_eff_nl = res.zero[1] + im*res.zero[2]
    # result = optimize(detMM2, initial_k0; g_tol= tol^2.0)

    #Note that there is not a unique effective wavenumber. The root closest to k_eff = 0.0 + 0.0im seems to be the right one, the others lead to strange transmission angles and large amplitudes As.
    lower = [0.,0.]; upper = 2*[k0,k0]
    result = optimize(detMM2, initial_k0, lower, upper; g_tol = tol^2.0, f_tol = tol^4.0)

    # Check result
    k_eff = result.minimizer[1] + im*result.minimizer[2]
    MM_svd = svd(MM(k_eff))
    if last(MM_svd[2]) > tol
        warn("Local optimisation was unsucessful at finding an effective wavenumber: $(last(MM_svd[2])) was the smallest eigenvalue value (should be zero) of the effective wavenumber matrix equation.")
    end

    # calculate effective transmission angle
    snell(θ::Array{T}) = norm(k*sin(θ_inc) - k_eff*sin(θ[1] + im*θ[2]))
    result = optimize(snell, [θ_inc,0.]; g_tol= tol^2.0)
    θ_eff = result.minimizer[1] + im*result.minimizer[2]

    # calculate effective amplitudes
    A_null = MM_svd[3][:,(2ho+1)*S] # norm(MM(kef)*A_null) ~ 0
    A_null = reshape(A_null, (2*ho+1,S)) # A_null[:,j] = [A[-ho,j],A[-ho+1,j],...,A[ho,j]]

    sumAs = 2*sum(
            exp(im*n*(θ_inc - θ_eff))*Z_l_n(l,n)*species[l].num_density*A_null[n+ho+1,l]
    for n = -ho:ho, l = 1:S)
    x = im*k*cos(θ_inc)*(k_eff*cos(θ_eff) - k*cos(θ_inc))/sumAs

    (k_eff,θ_eff,A_null*x)
end
