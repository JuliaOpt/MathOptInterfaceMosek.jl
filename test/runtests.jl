using MathOptInterfaceMosek

using Base.Test

using MathOptInterfaceTests
const MOIT = MathOptInterfaceTests

const solver = () -> MosekInstance(QUIET = true)
const config = MOIT.TestConfig(1e-7, 1e-7, true, false, true, true)
const configlowtol = MOIT.TestConfig(1e-4, 1e-4, true, false, true, true)

@testset "Continuous linear problems" begin
    # linear11 is failing because the following are not implemented:
    # * MOI.cantransformconstraint(instance, c2, MOI.LessThan(2.0))
    # * MOI.get(instance, MathOptInterface.ConstraintFunction())
    MOIT.contlineartest(solver, config, ["linear11"])
end

# include("contquadratic.jl")
# @testset "Continuous quadratic problems" begin
#     # contquadratictest(GurobiSolver())
# end

@testset "Continuous conic problems" begin
    # lin1 and soc1 are failing because ListOfConstraints is not implemented
    # sdp2 is failing because MOI.get(instance, MOI.ConstraintPrimal(), c1) returns -10 instead of 0
    MOIT.contconictest(solver, config, ["lin1v", "lin1f", "soc1", "geomean", "exp", "sdp2"])
    MOIT.exptest(solver, configlowtol)
    MOIT.geomeantest(solver, configlowtol)
end

@testset "Mixed-integer linear problems" begin
    MOIT.intlineartest(solver, config, ["int2"])
end

#include("test_jump.jl")
