import Base.Test: @testset, @test, @test_throws
using EffectiveWaves

@testset "Examples from: Reflection from multi-species.., Proc.R.Soc.(2018)" begin

    include("../examples/concrete/concrete_species.jl")
    include("../examples/concrete/concrete_species_volfrac.jl")
    # include("../examples/concrete/concrete_species_large-freq.jl") # takes longer

    # Takes too long
    include("../examples/emulsion/fluid_species.jl")
    include("../examples/emulsion/fluid_species_volfrac.jl")
    # include("../examples/emulsion/fluid_species_large-freq.jl") # takes longer

    @test true
end

include("types_constructors.jl")

include("strong_low_freq_effective.jl")
include("high_frequency_effective.jl")

include("large_vol_low_freq_effective.jl")
# too heavy a test..
include("weak_scatterers_effective.jl")

include("integrated_reflection.jl")
include("average_integrand_kernel.jl")
include("match_wave.jl")
