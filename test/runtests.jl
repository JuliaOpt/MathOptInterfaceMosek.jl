# To ensure that tests can run on travis we have to do a little
# hackadoodle here. The tests require a license file. We include
# a license file that is only valid for one day (the day when
# change is submitted).
# If there is no valid license file, we default to that file.

using MathOptInterfaceMosek


using Test

using MathOptInterface
const MOI = MathOptInterface
const MOIT = MOI.Test
const MOIU = MOI.Utilities
const MOIB = MOI.Bridges

const optimizer = Mosek.Optimizer(QUIET = true, service = "mosek://solve.mosek.com:30080")
# 1e-3 needed for rotatedsoc3 test
const config = MOIT.TestConfig(atol=1e-3, rtol=1e-3, query=false)

# Mosek does not support names
MOIU.@model(Model,
            (MOI.Integer,),
            (MOI.EqualTo, MOI.LessThan, MOI.GreaterThan),
            (MOI.Zeros, MOI.Nonnegatives, MOI.Nonpositives, MOI.RotatedSecondOrderCone),
            (),
            (MOI.SingleVariable,),
            (MOI.ScalarAffineFunction,),
            (MOI.VectorOfVariables,),
            (MOI.VectorAffineFunction,))

@testset "SolverName" begin
    @test MOI.get(optimizer, MOI.SolverName()) == "Mosek"
end

@testset "Copy" begin
    # Currently does not work because get is missing for ConstraintSet
    # and ConstraintFunction, see https://github.com/JuliaOpt/MathOptInterfaceMosek.jl/issues/50
    #MOIT.copytest(optimizer, Model{Float64}())
end

@testset "Unit" begin
    # Mosek does not support names
    cached = MOIU.CachingOptimizer(Model{Float64}(), optimizer)
    MOIT.unittest(MOIB.QuadtoSOC{Float64}(MOIB.SplitInterval{Float64}(cached)),
                  config,
                  [# Does not support quadratic objective yet, needs
                   # https://github.com/JuliaOpt/MathOptInterface.jl/issues/529
                   "solve_qp_edge_cases",
                   # Find objective bound of 0.0 which is lower than 4.0
                   "solve_objbound_edge_cases",
                   # Cannot put multiple bound sets of the same type on a variable
                   "solve_integer_edge_cases"
                  ])
end

@testset "Continuous linear problems" begin
    # linear1 is failing for two reasons
    # * it does not remove constraints using a variable if this variable is deleted, see https://github.com/JuliaOpt/MathOptInterface.jl/issues/511
    # * it does not support duplicated terms, see https://github.com/JuliaOpt/MathOptInterfaceMosek.jl/issues/41
    MOIT.contlineartest(optimizer, config, ["linear1"])
end

# include("contquadratic.jl")
# @testset "Continuous quadratic problems" begin
#     # contquadratictest(GurobiSolver())
# end

@testset "Continuous conic problems" begin
    MOIT.contconictest(MOIB.SquarePSD{Float64}(MOIB.RootDet{Float64}(MOIB.GeoMean{Float64}(optimizer))),
                       config, ["exp", "rootdets", "logdet"])
end

@testset "Mixed-integer linear problems" begin
    MOIT.intlineartest(optimizer, config, ["int2"])
end

#include("test_jump.jl")
