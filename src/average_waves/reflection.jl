function reflection_coefficient_integrated(ω::T, amps::AverageWave{T}, medium::Medium, specie::Specie;
        θin::T = 0.0) where T <: AbstractFloat

    k = ω/medium.c

    M = amps.hankel_order
    σ = trap_scheme(amps.x)
    # Z = OffsetArray{Complex{T}}(-M:M);
    # for m = 0:M
    #     Z[m] = Zn(ω,specie,medium,m)
    #     Z[-m] = Z[m]
    # end
    R = T(2)*specie.num_density/(cos(θin)*k^2)*sum(
        im^T(m)*exp(-im*θin*m)*amps.amplitudes[j,m+M+1,1]*exp(im*amps.x[j]*cos(θin))*σ[j]
    for m=-M:M, j in eachindex(amps.x))

    return R
end
