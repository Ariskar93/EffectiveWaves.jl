wavenumber_low_volumefraction(ω::Number, medium::PhysicalMedium, specie::Specie; kws...) = wavenumber_low_volumefraction(ω, medium, [specie]; kws...)

wavenumber_low_volumefraction(ωs::AbstractVector{T}, medium::PhysicalMedium{T}, species::Species{T}; kws...) where T<:Number = [wavenumber_low_volumefraction(ω, medium, species; kws...) for ω in ωs]

wavenumber_low_volumefraction(ωs::AbstractVector{T}, medium::PhysicalMedium{T}, specie::Specie{T}; kws...) where T<:Number = [wavenumber_low_volumefraction(ω, medium, [specie]; kws...) for ω in ωs]

"""
    wavenumber_low_volumefraction(ω::T, medium::Acoustic{T,Dim}, species::Species{T,Dim}; basis_order::Int = 2)

Explicit formula for one effective wavenumber based on a low particle volume fraction expansion.
"""
function wavenumber_low_volumefraction(ω::T, medium::Acoustic{T,3}, species::Species{T,3};
        basis_order::Int = 2, verbose::Bool = true
    ) where T

    volfrac = sum(volume_fraction.(species))
    if volfrac >= 0.4 && verbose
    @warn("the volume fraction $(round(100*volfrac))% is too high, expect a relative error of approximately $(round(100*volfrac^3.0))%")
    end

    # background wavenumber
    k = ω / medium.c

    # total particle number density
    num_density = sum(number_density.(species))

    Ts = get_t_matrices(medium, species, ω, basis_order)

    # Non-dimensional exclusion distance between particles
    kas = k .* [s1.exclusion_distance * outer_radius(s1) + s2.exclusion_distance * outer_radius(s2) for s1 in species, s2 in species]

    # far-field pattern
    fo = sum( (2l + 1) *
        sum(
            Ts[s][l+1,l+1] * number_density(species[s])
        for s in eachindex(species))
    for l = 0:basis_order) / num_density

    # far-field multiple scattering pattern
    foo = sum(
        sqrt((2l + 1)*(2dl + 1)*(2l1 + 1)) * Complex{T}(im)^(l-dl-l1+1) * gaunt_coefficient(l,0,dl,0,l1,0) *
        sum(
            kas[s1,s2] * d3D(kas[s1,s2],l1) *
            Ts[s1][l+1,l+1] * Ts[s2][dl+1,dl+1] *
            number_density(species[s1]) * number_density(species[s2])
        for s1 in eachindex(species), s2 in eachindex(species))
    for l = 0:basis_order for dl = 0:basis_order for l1 = abs(l-dl):abs(l+dl)) / Complex{T}(2 * sqrt(4pi) * num_density^2)

    # effective wavenumber squared up too second order in particle volume fraction
    kT2::Complex{T} = k^T(2) - im * 4pi * num_density * fo / k + (4pi)^2 * num_density^2 * foo / k^4

    return (imag(sqrt(kT2)) > zero(T)) ? sqrt(kT2) : -sqrt(kT2)
end

function wavenumber_low_volumefraction(ω::T, medium::Acoustic{T,2}, species::Species{T,2}; basis_order::Int = 2, verbose::Bool = true) where T

  volfrac = sum(volume_fraction.(species))
  if volfrac >= 0.4 && verbose
    @warn("the volume fraction $(round(100*volfrac))% is too high, expect a relative error of approximately $(round(100*volfrac^3.0))%")
  end
  num_density = sum(number_density.(species))
  # Add incident wavenumber
  kT2 = (ω/medium.c)^2.0
  # Add far-field contribution
  kT2 += - 4.0im*num_density*far_field_pattern(ω, medium, species; basis_order=basis_order)(0.0)
  # Add pair-field contribution
  kT2 += - 4.0im*num_density^(2.0)*pair_field_pattern(ω, medium, species; basis_order=basis_order)(0.0)

  return (imag(sqrt(kT2)) > zero(T)) ? sqrt(kT2) : -sqrt(kT2)
end

reflection_coefficient_low_volumefraction(ωs::AbstractVector{T},psource::PlaneSource{T,2,1,Acoustic{T,2}}, material::Material{2,Halfspace{T,2}}; kws... ) where T<:Number =
    [reflection_coefficient_low_volumefraction(ω, psource, material; kws... ) for ω in ωs]

"An explicit formula for the refleciton coefficient based on a low particle volume fraction."
function reflection_coefficient_low_volumefraction(ω::T, psource::PlaneSource{T,2,1,Acoustic{T,2}}, material::Material{2,Halfspace{T,2}}; kws...) where T<:Number

    θin = transmission_angle(psource,material)
    θ_ref = T(π) - T(2)*θin
    fo = far_field_pattern(ω, psource.medium, material.species; kws...)
    dfo = diff_far_field_pattern(ω, psource.medium, material.species; kws...)
    foo = pair_field_pattern(ω, psource.medium, material.species; kws...)

    k = ω / psource.medium.c
    α = k*cos(θin)
    R1 = im*fo(θ_ref)
    R2 = im*foo(θ_ref) + T(2)*fo(zero(T)) / (α^2.0) * (sin(θin)*cos(θin)*dfo(θ_ref) - fo(θ_ref))

    num_density = sum(number_density.(material.species))
    R = (R1 + num_density*R2)*num_density/(α^2.0)
    return R
end

function wavenumber_very_low_volumefraction(ω::Number, medium::Acoustic{T,2}, species::Species{T,2}; tol=1e-6, verbose = false) where T<:Number

  volume_fraction = sum(sp.volume_fraction for sp in species)
  if volume_fraction >= 0.4
    @warn("the volume fraction $(round(100*volume_fraction))% is too high, expect a relative error of approximately $(round(100*volume_fraction^3.0))%")
  end
  kT2 = (ω/medium.c)^2.0
  next_order = 4.0im*sum(number_density(sp) * t_matrix(sp, medium, ω, 0)[1,1] for sp in species)
  basis_order=1

  # sum more hankel orders until the relative error < tol
  while abs(next_order/kT2) > tol
    kT2 += next_order
    next_order = 4.0im*sum(number_density(sp) * t_matrix(sp, medium, ω, m)[m,m] for sp in species, m in (-basis_order,basis_order))
    basis_order +=1
  end
  kT2 += next_order
  basis_order +=1
  if verbose println("max Hankel order = $basis_order") end

  return sqrt(kT2)
end
