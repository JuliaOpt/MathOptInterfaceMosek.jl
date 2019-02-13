
#### solver attributes
#MOI.get(m::Union{MosekSolver,MosekModel},::MOI.SupportsDuals) = true
#MOI.get(m::Union{MosekSolver,MosekModel},::MOI.SupportsAddConstraintAfterSolve) = true
#MOI.get(m::Union{MosekSolver,MosekModel},::MOI.SupportsAddVariableAfterSolve) = true
#MOI.get(m::Union{MosekSolver,MosekModel},::MOI.SupportsDeleteConstraint) = true
#MOI.get(m::Union{MosekSolver,MosekModel},::MOI.SupportsDeleteVariable) = true
#MOI.get(m::Union{MosekSolver,MosekModel},::MOI.SupportsConicThroughQuadratic) = false # though actually the solver does

#### objective
MOI.get(m::MosekModel,attr::MOI.ObjectiveValue) = getprimalobj(m.task,m.solutions[attr.resultindex].whichsol)

MOI.get(m::MosekModel,attr::MOI.ObjectiveBound) = getdouinf(m.task,MSK_DINF_MIO_OBJ_BOUND)

MOI.get(m::MosekModel,attr::MOI.RelativeGap) = getdouinf(m.task,MSK_DINF_MIO_OBJ_REL_GAP)

MOI.get(m::MosekModel,attr::MOI.SolveTime) = getdouinf(m.task,MSK_DINF_OPTIMIZER_TIME)


# NOTE: The MOSEK interface currently only supports Min and Max
function MOI.get(model::MosekModel, ::MOI.ObjectiveSense)
    if model.feasibility
        return MOI.FEASIBILITY_SENSE
    else
        sense = getobjsense(model.task)
        if sense == MSK_OBJECTIVE_SENSE_MINIMIZE
            MOI.MIN_SENSE
        else
            MOI.MAX_SENSE
        end
    end
end

function MOI.set(model::MosekModel,
                 attr::MOI.ObjectiveSense,
                 sense::MOI.OptimizationSense)
    if sense == MOI.MIN_SENSE
        model.feasibility = false
        putobjsense(model.task,MSK_OBJECTIVE_SENSE_MINIMIZE)
    elseif sense == MOI.MAX_SENSE
        model.feasibility = false
        putobjsense(model.task,MSK_OBJECTIVE_SENSE_MAXIMIZE)
    else
        @assert sense == MOI.FEASIBILITY_SENSE
        model.feasibility = true
        putobjsense(model.task,MSK_OBJECTIVE_SENSE_MINIMIZE)
        MOI.set(model,
                MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),
                MOI.ScalarAffineFunction(MOI.ScalarAffineTerm{Float64}[], 0.0))
    end
end

#### Solver/Solution information

function MOI.get(m::MosekModel,attr::MOI.SimplexIterations)
    miosimiter = getlintinf(m.task,MSK_LIINF_MIO_SIMPLEX_ITER)
    if miosimiter > 0
        Int(miosimiter)
    else
        Int(getintinf(m.task,MSK_IINF_SIM_PRIMAL_ITER) + getintinf(m.task,MSK_IINF_SIM_DUAL_ITER))
    end
end

function MOI.get(m::MosekModel,attr::MOI.BarrierIterations)
    miosimiter = getlintinf(m.task,MSK_LIINF_MIO_INTPNT_ITER)
    if miosimiter > 0
        Int(miosimiter)
    else
        Int(getintinf(m.task,MSK_IINF_INTPNT_ITER))
    end
end

function MOI.get(m::MosekModel,attr::MOI.NodeCount)
        Int(getintinf(m.task,MSK_IINF_MIO_NUM_BRANCH))
end

MOI.get(m::MosekModel,attr::MOI.RawSolver) = m.task

MOI.get(m::MosekModel,attr::MOI.ResultCount) = length(m.solutions)

#### Problem information

MOI.get(m::MosekModel,attr::MOI.NumberOfVariables) = m.publicnumvar

function MOI.get(m::MosekModel, ::MOI.NumberOfConstraints{F,D}) where {F,D}
    return length(select(m.constrmap, F, D))
end

function MOI.get(model::MosekModel,
                 ::MOI.ListOfConstraints)
    list = Tuple{DataType, DataType}[]
    for F in [MOI.SingleVariable, MOI.ScalarAffineFunction{Float64}]
        for D in [MOI.LessThan{Float64}, MOI.GreaterThan{Float64},
                  MOI.EqualTo{Float64}, MOI.Interval{Float64}]
            if !isempty(select(model.constrmap, F, D))
                push!(list, (F, D))
            end
        end
    end
    for F in [MOI.VectorOfVariables, MOI.VectorAffineFunction{Float64}]
        for D in [MOI.Nonpositives, MOI.Nonnegatives, MOI.Reals, MOI.Zeros,
                  MOI.SecondOrderCone, MOI.RotatedSecondOrderCone,
                  MOI.PowerCone{Float64}, MOI.DualPowerCone{Float64},
                  MOI.ExponentialCone, MOI.DualExponentialCone,
                  MOI.PositiveSemidefiniteConeTriangle]
            if !isempty(select(model.constrmap, F, D))
                push!(list, (F, D))
            end
        end
    end
    return list
end

function MOI.get(model::MosekModel,
                 ::MOI.ListOfConstraintIndices{F, D}) where {F, D}
    return MOI.ConstraintIndex{F, D}.(keys(select(model.constrmap, F, D)))
end

#### Warm start values

function MOI.set(m::MosekModel, attr::MOI.VariablePrimalStart,
                 v::MOI.VariableIndex, val::Float64)
    subj = getindex(m.x_block, ref2id(v))

    xx = Float64[val]
    for sol in [ MSK_SOL_BAS, MSK_SOL_ITG ]
        putxxslice(m.task, sol, Int(subj), Int(subj+1), xx)
    end
end

function MOI.set(m::MosekModel,attr::MOI.VariablePrimalStart, vs::Vector{MOI.VariableIndex}, vals::Vector{Float64})
    subj = Array{Int}(undef,length(vs))
    for i in 1:length(subj)
        getindexes(m.x_block, ref2id(vs[i]), subj, i)
    end

    for sol in [ MSK_SOL_BAS, MSK_SOL_ITG ]
        if solutiondef(m.task,sol)
            xx = getxx(m.task,sol)
            xx[subj] = vals
            putxx(m.task,sol,xx)
        else
            xx = zeros(Float64,getnumvar(m.task))
            xx[subj] = vals
            putxx(m.task,sol,xx)
        end
    end
end


function MOI.set(m::MosekModel, attr::MOI.VariableName,
                 index :: MOI.VariableIndex, value :: String)
    subj = getindex(m.x_block, ref2id(index))
    putvarname(m.task, subj, value)
end

# function MOI.set(m::MosekModel,attr::MOI.ConstraintDualStart, vs::Vector{MOI.ConstraintIndex}, vals::Vector{Float64})
#     subj = Array{Int}(length(vs))
#     for i in 1:length(subj)
#         getindexes(m.x_block,ref2id(vs[i]),subj,i)
#     end

#     for sol in [ MSK_SOL_BAS, MSK_SOL_ITG ]
#         if solutiondef(m.task,sol)
#             xx = getxx(m.task,sol)
#             xx[subj] = vals
#             putxx(m.task,sol,xx)
#         else
#             xx = zeros(Float64,getnumvar(m.task))
#             xx[subj] = vals
#             putxx(m.task,sol,xx)
#         end
#     end
# end



#### Variable solution values

function MOI.get!(output::Vector{Float64}, m::MosekModel,
                  attr::MOI.VariablePrimal, vs::Vector{MOI.VariableIndex})
    subj = Array{Int}(undef,length(vs))
    for i in 1:length(subj)
        getindexes(m.x_block, ref2id(vs[i]), subj, i)
    end

    output[1:length(output)] = m.solutions[attr.N].xx[subj]
end

function MOI.get(m::MosekModel, attr::MOI.VariablePrimal,
                 vs::Vector{MOI.VariableIndex})
    output = Vector{Float64}(undef,length(vs))
    MOI.get!(output, m, attr, vs)
    return output
end

function MOI.get(m::MosekModel, attr::MOI.VariablePrimal,
                 vref::MOI.VariableIndex)
    subj = getindex(m.x_block,ref2id(vref))
    m.solutions[attr.N].xx[subj]
end






#### Constraint solution values

function MOI.get(
    m     ::MosekModel,
    attr  ::MOI.ConstraintPrimal,
    cref  ::MOI.ConstraintIndex{MOI.SingleVariable,D}) where D

    conid = ref2id(cref)
    idx  = getindex(m.xc_block, conid)
    subj  = m.xc_idxs[idx]

    m.solutions[attr.N].xx[subj]
end

# Semidefinite domain for a variable
function MOI.get!(
    output::Vector{Float64},
    m     ::MosekModel,
    attr  ::MOI.ConstraintPrimal,
    cref  ::MOI.ConstraintIndex{MOI.VectorOfVariables,MOI.PositiveSemidefiniteConeTriangle})

    whichsol = getsolcode(m,attr.N)
    cid = ref2id(cref)
    @assert(cid < 0)

    # It is in fact a real constraint and cid is the id of an ordinary constraint
    barvaridx = - m.c_block_slack[-cid]
    output[1:length(output)] = sympackedLtoU(getbarxj(m.task,whichsol,barvaridx))
end

# Any other domain for variable vector
function MOI.get!(
    output::Vector{Float64},
    m     ::MosekModel,
    attr  ::MOI.ConstraintPrimal,
    cref  ::MOI.ConstraintIndex{MOI.VectorOfVariables,D}) where D

    xcid = ref2id(cref)
    @assert(xcid > 0)

    mask = m.xc_bounds[xcid]
    idxs = getindexes(m.xc_block, xcid)
    subj = m.xc_idxs[idxs]

    output[1:length(output)] = m.solutions[attr.N].xx[subj]
end

function MOI.get(m     ::MosekModel,
                 attr  ::MOI.ConstraintPrimal,
                 cref  ::MOI.ConstraintIndex{MOI.ScalarAffineFunction{Float64},D}) where D
    cid = ref2id(cref)
    subi = getindex(m.c_block,cid)
    m.solutions[attr.N].xc[subi] + m.c_constant[subi]
end



function MOI.get!(
    output::Vector{Float64},
    m     ::MosekModel,
    attr  ::MOI.ConstraintPrimal,
    cref  ::MOI.ConstraintIndex{MOI.VectorAffineFunction{Float64},D}) where D

    cid = ref2id(cref)
    subi = getindexes(m.c_block, cid)

    if     m.c_block_slack[cid] == 0 # no slack
        output[1:length(output)] = m.solutions[attr.N].xc[subi] + m.c_constant[subi]
    elseif m.c_block_slack[cid] >  0 # qcone slack
        xid = m.c_block_slack[cid]
        xsubj = getindexes(m.x_block, xid)
        output[1:length(output)] = m.solutions[attr.N].xx[xsubj]
    else # psd slack
        xid = - m.c_block_slack[cid]
        output[1:length(output)] = sympackedLtoU(getbarxj(m.task,m.solutions[attr.N].whichsol,Int32(xid)))
    end
end













function MOI.get(
    m     ::MosekModel,
    attr  ::MOI.ConstraintDual,
    cref  ::MOI.ConstraintIndex{MOI.SingleVariable,D}) where { D <: MOI.AbstractSet }


    xcid = ref2id(cref)
    idx = getindex(m.xc_block, xcid) # variable id

    @assert(blocksize(m.xc_block,xcid) > 0)

    subj  = getindex(m.x_block, m.xc_idxs[idx])
    if (getobjsense(m.task) == MSK_OBJECTIVE_SENSE_MINIMIZE)
        if     m.xc_bounds[xcid] & boundflag_lower != 0 && m.xc_bounds[xcid] & boundflag_upper != 0
            m.solutions[attr.N].slx[subj] - m.solutions[attr.N].sux[subj]
        elseif (m.xc_bounds[xcid] & boundflag_lower) != 0
            m.solutions[attr.N].slx[subj]
        elseif (m.xc_bounds[xcid] & boundflag_upper) != 0
            - m.solutions[attr.N].sux[subj]
        elseif (m.xc_bounds[xcid] & boundflag_cone) != 0
            m.solutions[attr.N].snx[subj]
        else
            error("Dual value available for this constraint")
        end
    else
        if     m.xc_bounds[xcid] & boundflag_lower != 0 && m.xc_bounds[xcid] & boundflag_upper != 0
            m.solutions[attr.N].sux[subj] - m.solutions[attr.N].slx[subj]
        elseif (m.xc_bounds[xcid] & boundflag_lower) != 0
            - m.solutions[attr.N].slx[subj]
        elseif (m.xc_bounds[xcid] & boundflag_upper) != 0
            m.solutions[attr.N].sux[subj]
        elseif (m.xc_bounds[xcid] & boundflag_cone) != 0
            - m.solutions[attr.N].snx[subj]
        else
            error("Dual value available for this constraint")
        end
    end
end

getsolcode(m::MosekModel, N) = m.solutions[N].whichsol

# Semidefinite domain for a variable
function MOI.get!(
    output::Vector{Float64},
    m     ::MosekModel,
    attr  ::MOI.ConstraintDual,
    cref  ::MOI.ConstraintIndex{MOI.VectorOfVariables,MOI.PositiveSemidefiniteConeTriangle})

    whichsol = getsolcode(m,attr.N)
    cid = ref2id(cref)
    @assert(cid < 0)

    # It is in fact a real constraint and cid is the id of an ordinary constraint
    barvaridx = - m.c_block_slack[-cid]
    dual = sympackedLtoU(getbarsj(m.task,whichsol,barvaridx))
    if (getobjsense(m.task) == MSK_OBJECTIVE_SENSE_MINIMIZE)
        output[1:length(output)] = dual
    else
        output[1:length(output)] = -dual
    end
end

# Any other domain for variable vector
function MOI.get!(
    output::Vector{Float64},
    m     ::MosekModel,
    attr  ::MOI.ConstraintDual,
    cref  ::MOI.ConstraintIndex{MOI.VectorOfVariables,D}) where D

    xcid = ref2id(cref)
    @assert(xcid > 0)

    mask = m.xc_bounds[xcid]
    idxs = getindexes(m.xc_block,xcid)
    subj = m.xc_idxs[idxs]

    if (getobjsense(m.task) == MSK_OBJECTIVE_SENSE_MINIMIZE)
        if     mask & boundflag_lower != 0 && mask & boundflag_upper != 0
            output[1:length(output)] = m.solutions[attr.N].slx[subj] - m.solutions[attr.N].sux[subj]
        elseif (mask & boundflag_lower) != 0
            output[1:length(output)] = m.solutions[attr.N].slx[subj]
        elseif (mask & boundflag_upper) != 0
            output[1:length(output)] = - m.solutions[attr.N].sux[subj]
        elseif (mask & boundflag_cone) != 0
            output[1:length(output)] = m.solutions[attr.N].snx[subj]
        else
            error("Dual value available for this constraint")
        end
    else
        if     mask & boundflag_lower != 0 && mask & boundflag_upper != 0
            output[1:length(output)] = m.solutions[attr.N].sux[subj] - m.solutions[attr.N].slx[subj]
        elseif (mask & boundflag_lower) != 0
            output[1:length(output)] = - m.solutions[attr.N].slx[subj]
        elseif (mask & boundflag_upper) != 0
            output[1:length(output)] = m.solutions[attr.N].sux[subj]
        elseif (mask & boundflag_cone) != 0
            output[1:length(output)] = - m.solutions[attr.N].snx[subj]
        else
            error("Dual value available for this constraint")
        end
    end
end

function MOI.get(m     ::MosekModel,
                 attr  ::MOI.ConstraintDual,
                 cref  ::MOI.ConstraintIndex{MOI.ScalarAffineFunction{Float64},D}) where D

    cid = ref2id(cref)
    subi = getindex(m.c_block, cid)

    if getobjsense(m.task) == MSK_OBJECTIVE_SENSE_MINIMIZE
        m.solutions[attr.N].y[subi]
    else
        - m.solutions[attr.N].y[subi]
    end
end


function MOI.get!(
    output::Vector{Float64},
    m     ::MosekModel,
    attr  ::MOI.ConstraintDual,
    cref  ::MOI.ConstraintIndex{MOI.VectorAffineFunction{Float64},D}) where { D <: MOI.AbstractSet }

    cid = ref2id(cref)
    subi = getindexes(m.c_block, cid)

    if getobjsense(m.task) == MSK_OBJECTIVE_SENSE_MINIMIZE
        if     m.c_block_slack[cid] == 0 # no slack
            output[1:length(output)] = m.solutions[attr.N].y[subi]
        elseif m.c_block_slack[cid] >  0 # qcone slack
            xid = m.c_block_slack[cid]
            xsubj = getindexes(m.x_block, xid)
            output[1:length(output)] = m.solutions[attr.N].snx[xsubj]
        else # psd slack
            whichsol = getsolcode(m,attr.N)
            xid = - m.c_block_slack[cid]
            output[1:length(output)] = sympackedLtoU(getbarsj(m.task,whichsol,Int32(xid)))
        end
    else
        if     m.c_block_slack[cid] == 0 # no slack
            output[1:length(output)] = - m.solutions[attr.N].y[subi]
        elseif m.c_block_slack[cid] >  0 # qcone slack
            xid = m.c_block_slack[cid]
            subj = getindexes(m.x_block, xid)
            output[1:length(output)] = - m.solutions[attr.N].snx[subj]
        else # psd slack
            whichsol = getsolcode(m,attr.N)
            xid = - m.c_block_slack[cid]
            output[1:length(output)] = sympackedLtoU(- getbarsj(m.task,whichsol,Int32(xid)))
        end
    end
end














solsize(m::MosekModel, cref :: MOI.ConstraintIndex{<:MOI.AbstractScalarFunction}) = 1
function solsize(m::MosekModel, cref :: MOI.ConstraintIndex{MOI.VectorOfVariables})
    cid = ref2id(cref)
    if cid < 0
        blocksize(m.c_block,-cid)
    else
        blocksize(m.xc_block,cid)
    end
end

function solsize(m::MosekModel, cref :: MOI.ConstraintIndex{<:MOI.VectorAffineFunction})
    cid = ref2id(cref)
    blocksize(m.c_block,cid)
end

function MOI.get(m::MosekModel, attr::Union{MOI.ConstraintPrimal, MOI.ConstraintDual}, cref :: MOI.ConstraintIndex{F,D}) where {F <: MOI.AbstractVectorFunction,D}
    cid = ref2id(cref)
    output = Vector{Float64}(undef,solsize(m,cref))
    MOI.get!(output,m,attr,cref)
    output
end






#### Status codes
function MOI.get(m::MosekModel,attr::MOI.TerminationStatus)
    if     m.trm === nothing
        MOI.OPTIMIZE_NOT_CALLED
    elseif m.trm == MSK_RES_OK
        if any(sol -> sol.solsta == MSK_SOL_STA_PRIM_INFEAS_CER, m.solutions)
            MOI.INFEASIBLE
        elseif any(sol -> sol.solsta == MSK_SOL_STA_DUAL_INFEAS_CER,
                   m.solutions)
            MOI.DUAL_INFEASIBLE
        else
            MOI.OPTIMAL
        end
    elseif m.trm == MSK_RES_TRM_MAX_ITERATIONS
        MOI.ITERATION_LIMIT
    elseif m.trm == MSK_RES_TRM_MAX_TIME
        MOI.TIME_LIMIT
    elseif m.trm == MSK_RES_TRM_OBJECTIVE_RANGE
        MOI.OBJECTIVE_LIMIT
    elseif m.trm == MSK_RES_TRM_MIO_NEAR_REL_GAP
        MOI.ALMOST_OPTIMAL
    elseif m.trm == MSK_RES_TRM_MIO_NEAR_ABS_GAP
        MOI.ALMOST_OPTIMAL
    elseif m.trm == MSK_RES_TRM_MIO_NUM_RELAXS
        MOI.OTHER_LIMIT
    elseif m.trm == MSK_RES_TRM_MIO_NUM_BRANCHES
        MOI.NODE_LIMIT
    elseif m.trm == MSK_RES_TRM_NUM_MAX_NUM_INT_SOLUTIONS
        MOI.SOLUTION_LIMIT
    elseif m.trm == MSK_RES_TRM_STALL
        println("STALL")
        MOI.SLOW_PROGRESS
    elseif m.trm == MSK_RES_TRM_USER_CALLBACK
        MOI.INTERRUPTED
    elseif m.trm == MSK_RES_TRM_MAX_NUM_SETBACKS
        MOI.OTHER_LIMIT
    elseif m.trm == MSK_RES_TRM_NUMERICAL_PROBLEM
        println("NUMERICAL_PROBLEM")
        MOI.SLOW_PROGRESS
    elseif m.trm == MSK_RES_TRM_INTERNAL
        MOI.OTHER_ERROR
    elseif m.trm == MSK_RES_TRM_INTERNAL_STOP
        MOI.OTHER_ERROR
    else
        MOI.OTHER_ERROR
    end
end

function MOI.get(m::MosekModel, attr::MOI.PrimalStatus)
    solsta = m.solutions[attr.N].solsta
    if     solsta == MSK_SOL_STA_UNKNOWN
        MOI.UNKNOWN_RESULT_STATUS
    elseif solsta == MSK_SOL_STA_OPTIMAL
        MOI.FEASIBLE_POINT
    elseif solsta == MSK_SOL_STA_PRIM_FEAS
        MOI.FEASIBLE_POINT
    elseif solsta == MSK_SOL_STA_DUAL_FEAS
        MOI.UNKNOWN_RESULT_STATUS
    elseif solsta == MSK_SOL_STA_PRIM_AND_DUAL_FEAS
        MOI.FEASIBLE_POINT
    elseif solsta == MSK_SOL_STA_PRIM_INFEAS_CER
        MOI.NO_SOLUTION
    elseif solsta == MSK_SOL_STA_DUAL_INFEAS_CER
        MOI.INFEASIBILITY_CERTIFICATE
    elseif solsta == MSK_SOL_STA_PRIM_ILLPOSED_CER
        MOI.NO_SOLUTION
    elseif solsta == MSK_SOL_STA_DUAL_ILLPOSED_CER
        MOI.REDUCTION_CERTIFICATE
    elseif solsta == MSK_SOL_STA_INTEGER_OPTIMAL
        MOI.FEASIBLE_POINT
    else
        MOI.UNKNOWN_RESULT_STATUS
    end
end

function MOI.get(m::MosekModel,attr::MOI.DualStatus)
    solsta = m.solutions[attr.N].solsta
    if     solsta == MSK_SOL_STA_UNKNOWN
        MOI.UNKNOWN_RESULT_STATUS
    elseif solsta == MSK_SOL_STA_OPTIMAL
        MOI.FEASIBLE_POINT
    elseif solsta == MSK_SOL_STA_PRIM_FEAS
        MOI.UNKNOWN_RESULT_STATUS
    elseif solsta == MSK_SOL_STA_DUAL_FEAS
        MOI.FEASIBLE_POINT
    elseif solsta == MSK_SOL_STA_PRIM_AND_DUAL_FEAS
        MOI.FEASIBLE_POINT
    elseif solsta == MSK_SOL_STA_PRIM_INFEAS_CER
        MOI.INFEASIBILITY_CERTIFICATE
    elseif solsta == MSK_SOL_STA_DUAL_INFEAS_CER
        MOI.NO_SOLUTION
    elseif solsta == MSK_SOL_STA_PRIM_ILLPOSED_CER
        MOI.REDUCTION_CERTIFICATE
    elseif solsta == MSK_SOL_STA_DUAL_ILLPOSED_CER
        MOI.NO_SOLUTION
    elseif solsta == MSK_SOL_STA_INTEGER_OPTIMAL
        MOI.NO_SOLUTION
    else
        MOI.UNKNOWN_RESULT_STATUS
    end
end
