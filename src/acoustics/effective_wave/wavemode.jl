
"returns a number a, such that a*As_eff will cancel an incident wave plane wave with incident angle θin."
function scale_mode_amplitudes(ω::T, wave_eff::EffectivePlaneWaveMode{T}, psource::PlaneSource{T,Dim,1,Acoustic{T,Dim}}, material::Material{Dim,Halfspace{T,Dim}}; tol = 1e-8) where {T<:Number,Dim}

    k = ω/psource.medium.c

    θ_eff = wave_eff.θ_eff

    ho = wave_eff.basis_order
    amps = wave_eff.amplitudes
    S = length(material.species)

    sumAs = T(2)*sum(
            exp(im*n*(θin - θ_eff))*number_density(material.species[l])*amps[n+ho+1,l]
    for n = -ho:ho, l = 1:S)
    a = im*k*cos(θin)*(k_eff*cos(θ_eff) - k*cos(θin))/sumAs

    return a
end


function effective_wavemode(ω::T, k_eff::Complex{T}, psource::PlaneSource{T,Dim,1,Acoustic{T,Dim}}, material::Material{Dim,Halfspace{T,Dim}};
        tol::T = 1e-6, #θin::T = 0.0,
        method::Symbol = :none,
        extinction_rescale::Bool = true,
        kws...
    ) where {T<:AbstractFloat,Dim}

    k = ω/medium.c

    # θ_eff = transmission_angle(k, k_eff, θin; tol = tol)
    k_vec = transmission_wavevector(k_eff, psource.wavevector, material.normal)

    if method == :WienerHopf
        amps = wienerhopf_mode_amplitudes(ω, k_eff, psource, species; tol = tol, kws...)
    else
        amps = mode_amplitudes(ω, k_eff, psource, material; tol = tol, kws...)
    end
    plane_mode = EffectivePlaneWaveMode(ω, k_eff, k_vec, amps)

    if extinction_rescale && method != :WienerHopf
        amps = amps.*scale_mode_amplitudes(ω, plane_mode, psource.medium, material.species; tol = tol, θin=θin)
    end

    return EffectivePlaneWaveMode(ω, k_eff, k_vec, plane_mode.basis_order, amps)
end



function wienerhopf_mode_amplitudes(ω::T, k_eff::Complex{T}, psource::PlaneSource{T,2,1,Acoustic{T,2}}, species::Species{T}; kws...) where T<:AbstractFloat
    return wienerhopf_mode_amplitudes(ω, [k_eff], psource, species; kws...)
end


"The average effective transmitted wavemodes according to the Wiener-Hopf method.
The function returns an array A, where
AA(x,y,0,1) = A[1,1]*exp(im*k_eff*(cos(θ_eff)*x + sin(θin)*y))
where (x,y) are coordinates in the halfspace  and AA is the ensemble average scattering coefficient. Method currently only implemented for 1 species and for monopole scatterers."
function wienerhopf_mode_amplitudes(ω::T, k_effs::Vector{Complex{T}}, psource::PlaneSource{T,2,1,Acoustic{T,2}}, species::Species{T};
        tol::T = 1e-6,
        basis_order::Int = 0,
        num_coefs::Int = 10000,
        maxZ::T = T(100)*maximum(outer_radius(s) * s.exclusion_distance for s in species) + T(100),
        kws...
    ) where T<:AbstractFloat

    medium = psource.medium
    θin = atan(psource.wavevector[2],psource.wavevector[1])

    k = ω/medium.c
    ho = basis_order

    if ho > 0
        error("the Wiener Hopf method has not been implemented for `basis_order` = $(basis_order). Method currently only works for basis_order = 0, i.e. monopole scatterers. ")
    end

    t_vecs = get_t_matrices(medium, species, ω, basis_order)

    # t_vecs = t_vectors(ω, medium, species; basis_order = ho)
    as = [
        (outer_radius(s1) * s1.exclusion_distance + outer_radius(s2) * s2.exclusion_distance)
    for s1 in species, s2 in species]

    # differentiate in S ( = a[j,l] k_eff ) and evaluate at S
    function dSQ0_eff(S,j,l)
        m = 0

        T(2) / (S^T(2) - (k*as[j,l])^T(2)) * (
            S +
            pi * as[j,l]^T(2) * number_density(species[l]) * t_vecs[l][m+ho+1,m+ho+1] * (
                k*as[j,l]*diffhankelh1(0,k*as[j,l])*diffbesselj(0,S) -
                hankelh1(0,k*as[j,l])*diffbesselj(0,S) -
                S*hankelh1(0,k*as[j,l])*diffbesselj(0,S,2)
            )
        )
    end

    # kernelN(0,k*a12,Z) = k*a12*diffhankelh1(0,k*a12)*besselj(0,Z) - Z*hankelh1(0,k*a12)*diffbesselj(0,Z)
    # DZkernelN(0,k*a12,Z) = k*a12*diffhankelh1(0,k*a12)*diffbesselj(0,Z) - Z*hankelh1(0,k*a12)*diffbesselj(0,Z,2) -

    sToS(s,j::Int,l::Int) = (real(s) >= 0) ? sqrt(s^2 + (k*as[j,l]*sin(θin))^2) : -sqrt(s^2 + (k*as[j,l]*sin(θin))^2)

    function q(s,j,l,m,n)
        (n == m ? T(1) : T(0)) * (j == l ? T(1) : T(0)) +
        T(2) * pi * as[j,l]^T(2) * number_density(species[l]) * t_vecs[l][m+ho+1,m+ho+1] *
        kernelN(n-m, k*as[j,l], sToS(s,j,l)) / (s^T(2) - (k*as[j,l]*cos(θin))^T(2))
    end

    Zs = LinRange(T(100),1/(10*tol),3000)
    maxZ = Zs[findfirst(Z -> abs(log(q(Z,1,1,0,0))) < 10*tol, Zs)]

    function Ψp(s, maxZ::T = maxZ, num_coefs::Int = num_coefs)
        Q(z) = log(q(z,1,1,0,0))/(z - s)
        xp = as[1,1]*k*cos(θin)*(-1.0+1.0im)
        (s + k*as[1,1]*cos(θin)) * exp(
            (T(1.0)/(T(2)*pi*im)) * (
                sum(Fun(Q, Segment(-maxZ,xp), num_coefs)) +
                sum(Fun(Q, Segment(xp,-xp), num_coefs)) +
                sum(Fun(Q, Segment(-xp,maxZ), num_coefs))
            )
        )
    end

    Ψp_a = Ψp(k*as[1,1]*cos(θin))
    # has been tested against Mathematica for at least one k_eff
    dSΨ00(S) = (S^2 - (k*as[1,1])^2)*dSQ0_eff(S,1,1) # + T(2) * S * Q0(S,1,1,0,0)
    # last term left out becuase Q0(k_eff,1,1,0,0) = 0.

    return map(k_effs) do k_eff
        θ_eff = transmission_angle(k, k_eff, θin; tol = tol)
        Ψp_eff = Ψp(k_eff*as[1,1]*cos(θ_eff))
        t_vecs[1][ho+1,ho+1] * T(2)*k*as[1,1]*(cos(θin)/cos(θ_eff))*(Ψp_eff/Ψp_a)/dSΨ00(k_eff*as[1,1])
    end
end