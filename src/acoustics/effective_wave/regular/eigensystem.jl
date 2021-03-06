# The eigensystem when no symmetry is present
function eigensystem(ω::T, medium::PhysicalMedium{T,3}, species::Species{T,3}, ::WithoutSymmetry{3};
        basis_order::Int = 2,
        basis_field_order::Int = 2*basis_order,
        kws...) where {T<:AbstractFloat}

    k = real(ω/medium.c)
    sps = species

    S = length(sps)
    L = basis_order
    L1 = basis_field_order
    len = (L1+1)^2 * (L+1)^2 * S
    MM_mat = Matrix{Complex{T}}(undef,len,len)

    t_matrices = get_t_matrices(medium, sps, ω, L)

    as = [
        s1.exclusion_distance * outer_radius(s1) + s2.exclusion_distance * outer_radius(s2)
    for s1 in sps, s2 in sps]

    function M_component(keff,Ns,l,m,l2,m2,s1,dl,dm,l1,m1,s2)::Complex{T}
        minl3 = max(abs(m1-m2),abs(dl-l),abs(l1-l2))
        maxl3 = min(abs(dl+l),abs(l1+l2))

        (m == dm && l == dl && m1 == m2 && l1 == l2 && s1 == s2 ? 1.0 : 0.0) +
        if minl3 <= maxl3
            as[s1,s2] * number_density(sps[s2]) * t_matrices[s1][l+1,l+1] *
            sum(l3 ->
                gaunt_coefficient(l,m,dl,dm,l3,m1-m2) *
                gaunt_coefficient(l1,m1,l2,m2,l3,m1-m2) * Ns[l3+1,s1,s2]
            , minl3:maxl3)
        else
            zero(Complex{T})
        end
    end

    function MM(keff::Complex{T})::Matrix{Complex{T}}
        Ns = [
            kernelN3D(l3,k*as[s1,s2],keff*as[s1,s2])
        for l3 = 0:min(2L1,2L), s1 = 1:S, s2 = 1:S] ./  (keff^2.0 - k^2.0)

        # The order of the indices below is important
        ind2 = 1
        for s2 = 1:S for dl = 0:L for dm = -dl:dl for l1 = 0:L1 for m1 = -l1:l1
            ind1 = 1
            for s1 = 1:S for l = 0:L for m = -l:l for l2 = 0:L1 for m2 = -l2:l2
                MM_mat[ind1, ind2] = M_component(keff,Ns,l,m,l2,m2,s1,dl,dm,l1,m1,s2)
                ind1 += 1
            end end end end end
            ind2 += 1
        end end end end end
        return MM_mat
    end

    return MM
end

function eigensystem(ω::T, medium::PhysicalMedium{T,3}, species::Species{T,3}, ::AbstractAzimuthalSymmetry;
        basis_order::Int = 2,
        basis_field_order::Int = 2*basis_order,
        kws...) where {T<:AbstractFloat}

    k = real(ω/medium.c)
    sps = species

    S = length(sps)
    L = basis_order
    L1 = basis_field_order

    len = Int(1 - L*(2 + L)*(L - 3*L1 - 2)/3 + L1) * S
    MM_mat = Matrix{Complex{T}}(undef,len,len)

    t_matrices = get_t_matrices(medium, sps, ω, L)

    as = [
        s1.exclusion_distance * outer_radius(s1) + s2.exclusion_distance * outer_radius(s2)
    for s1 in sps, s2 in sps]

    # the index for the T-matrix below needs to be changed when seperating correctly the 2D and 3D case.
    function M_component(keff,Ns,l,m,l2,s1,dl,dm,l1,s2)::Complex{T}
        minl3 = max(abs(m-dm),abs(dl-l),abs(l1-l2))
        maxl3 = min(dl+l,l1+l2)

        (m == dm && l == dl && l1 == l2 && s1 == s2 ? 1.0 : 0.0) +
        if minl3 <= maxl3
            as[s1,s2] * number_density(species[s2]) * t_matrices[s1][l+1,l+1] *
            sum(l3 ->
                gaunt_coefficient(l,m,dl,dm,l3,m-dm) *
                gaunt_coefficient(l1,-dm,l2,-m,l3,m-dm) * Ns[l3+1,s1,s2]
            , minl3:maxl3)
        else
            zero(Complex{T})
        end
    end

    # The order of the indices below is important
    function MM(keff::Complex{T})::Matrix{Complex{T}}
        Ns = [
            kernelN3D(l3,k*as[s1,s2],keff*as[s1,s2])
        for l3 = 0:min(2L1,2L), s1 = 1:S, s2 = 1:S] ./ (keff^2.0 - k^2.0)

        ind2 = 1
        for s2 = 1:S for dl = 0:L for dm = -dl:dl for l1 = abs(dm):L1
            ind1 = 1
            for s1 = 1:S for l = 0:L for m = -l:l for l2 = abs(m):L1
                MM_mat[ind1, ind2] = M_component(keff,Ns,l,m,l2,s1,dl,dm,l1,s2)
                ind1 += 1
            end end end end
            ind2 += 1
        end end end end
        return MM_mat
    end

    return MM
end
