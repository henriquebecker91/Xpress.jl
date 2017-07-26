# Constraints

function MOI.ConstraintReference(m::XpressSolverInstance, func::F, set::S) where {F<:MOI.ScalarAffineFunction{Float64}, S}
    m.last_constraint_reference += 1
    ref = MOI.ConstraintReference{F, S}(m.last_constraint_reference)
    constraint_storage(m,F,S)[ref] = length(m.constraint_mapping)+1
    return ref
end

function MOI.addconstraint!(m::XpressSolverInstance, func::Linear, set::T) where T
    rejectnonzeroconstant(func)
    addlinearconstraint!(m, func, set)
    push!(m.constraint_rhs, value(set))
    return MOI.ConstraintReference(m, func, set)
end
function addlinearconstraint!(m::XpressSolverInstance, func::MOI.ScalarAffineFunction{Float64}, set::MOI.EqualTo{Float64}) 
    add_constr!(m.inner, getcols(m,func.variables), func.coefficients, '=', value(set))
end
function addlinearconstraint!(m::XpressSolverInstance, func::MOI.ScalarAffineFunction{Float64}, set::MOI.GreaterThan{Float64}) 
    add_constr!(m.inner, getcols(m,func.variables), func.coefficients, '>', value(set))
end
function addlinearconstraint!(m::XpressSolverInstance, func::MOI.ScalarAffineFunction{Float64}, set::MOI.LessThan{Float64}) 
    add_constr!(m.inner, getcols(m,func.variables), func.coefficients, '<', value(set))
end

# TODO
# getters

# struct ConstraintFunction <: AbstractConstraintAttribute end
MOI.cangetattribute(m::XpressSolverInstance, ::MOI.ConstraintFunction, ::MOI.ConstraintReference{MOI.ScalarQuadraticFunction{Float64},S}) where S = false
MOI.cangetattribute(m::XpressSolverInstance, ::MOI.ConstraintFunction, ::MOI.ConstraintReference{MOI.ScalarAffineFunction{Float64},S}) where S = false
function MOI.getattribute(m::XpressSolverInstance, ::MOI.ConstraintFunction, c::MOI.ConstraintReference{F,S}) where {F<:MOI.ScalarAffineFunction{Float64},S}
    idx = constraint_storage(m, F, S)[c]
    A = get_rows(m.inner, idx, idx)'
    v = key_from_value.(m.variable_mapping, A.rowval)
    coefs = A.nzval
    return MOI.ScalarAffineFunction(v, coefs, 0.0)
end

MOI.cangetattribute(m::XpressSolverInstance, ::MOI.ConstraintSet, ::MOI.ConstraintReference{MOI.ScalarAffineFunction{Float64},S}) where S = true
function MOI.getattribute(m::XpressSolverInstance, ::MOI.ConstraintSet, c::MOI.ConstraintReference{F,S}) where {F<:MOI.ScalarAffineFunction{Float64},S}
    idx = constraint_storage(m, F, S)[c]
    return S(m.constraint_rhs[idx])
end

# TODO
# function addconstraints! end

# TODO
# function modifyconstraint! end
function MOI.modifyconstraint!(m::XpressSolverInstance, c::MOI.ConstraintReference{F,S}, mod::MOI.ScalarCoefficientChange{Float64}) where {F<:MOI.ScalarAffineFunction{Float64},S}
    idx = constraint_storage(m, F, S)[c]
    chg_coeffs!(m.inner, idx, getcol(m, mod.variable), mod.new_coefficient)
end

# Variable bounds

function MOI.ConstraintReference(m::XpressSolverInstance, v::F, set::S) where {F<:MOI.SingleVariable, S}
    # bound ref number is the variable number
    ref = MOI.ConstraintReference{F, S}(v.variable.value)
    savevariablebound!(m, v, set)
    addboundconstraint!(m, v, set)
    return ref
end

function MOI.addconstraint!(m::XpressSolverInstance, v::MOI.SingleVariable, set::S) where S
    ref = MOI.ConstraintReference(m,v,set)
    ref
end

function savevariablebound!(m::XpressSolverInstance, v::MOI.SingleVariable, set::MOI.GreaterThan{Float64})
    var = m.variable_mapping[v.variable]
    if m.variable_bound[var] == Upper
        m.variable_bound[var] = LowerAndUpper
    else
        m.variable_bound[var] = Lower
    end
    m.variable_lb[var] = value(set)
end
function savevariablebound!(m::XpressSolverInstance, v::MOI.SingleVariable, set::MOI.LessThan{Float64})
    var = m.variable_mapping[v.variable]
    if m.variable_bound[var] == Lower
        m.variable_bound[var] = LowerAndUpper
    else
        m.variable_bound[var] = Upper
    end
    m.variable_ub[var] = value(set)
end
function savevariablebound!(m::XpressSolverInstance, v::MOI.SingleVariable, set::MOI.Interval{Float64})
    var = m.variable_mapping[v.variable]
    m.variable_bound[var] = Interval
    m.variable_lb[var] = set.lower
    m.variable_ub[var] = set.upper
end
function savevariablebound!(m::XpressSolverInstance, v::MOI.SingleVariable, set::MOI.EqualTo{Float64})
    var = m.variable_mapping[v.variable]
    m.variable_bound[var] = Fixed
    m.variable_lb[var] = value(set)
    m.variable_ub[var] = value(set)
end

addboundconstraint!(m::XpressSolverInstance, v::MOI.SingleVariable, set::MOI.GreaterThan{Float64}) = set_lb!(m.inner, Int32[getcol(m,v)], Float64[value(set)])
addboundconstraint!(m::XpressSolverInstance, v::MOI.SingleVariable, set::MOI.LessThan{Float64}) = set_ub!(m.inner, Int32[getcol(m,v)], Float64[value(set)])
function addboundconstraint!(m::XpressSolverInstance, v::MOI.SingleVariable, set::MOI.EqualTo{Float64}) 
    set_lb!(m.inner, Int32[getcol(m,v)], Float64[value(set)])
    set_ub!(m.inner, Int32[getcol(m,v)], Float64[value(set)])
end
function addboundconstraint!(m::XpressSolverInstance, v::MOI.SingleVariable, set::MOI.Interval{Float64}) 
    set_lb!(m.inner, Int32[getcol(m,v)], Float64[set.lower])
    set_ub!(m.inner, Int32[getcol(m,v)], Float64[set.upper])
end

# struct ConstraintFunction <: AbstractConstraintAttribute end
MOI.cangetattribute(m::XpressSolverInstance, ::MOI.ConstraintFunction, ::MOI.ConstraintReference{MOI.SingleVariable,S}) where S = true
function MOI.getattribute(m::XpressSolverInstance, ::MOI.ConstraintFunction, c::MOI.ConstraintReference{MOI.SingleVariable,S}) where S
    MOI.SingleVariable(MOI.VariableReference(c.value))
end

# struct ConstraintSet <: AbstractConstraintAttribute end
MOI.cangetattribute(m::XpressSolverInstance, ::MOI.ConstraintSet, ::MOI.ConstraintReference{MOI.SingleVariable,MOI.GreaterThan{Float64}}) = true
MOI.getattribute(m::XpressSolverInstance, ::MOI.ConstraintSet, c::MOI.ConstraintReference{MOI.SingleVariable,MOI.GreaterThan{Float64}}) = MOI.GreaterThan(m.variable_lb[getcol(m,c)])
MOI.cangetattribute(m::XpressSolverInstance, ::MOI.ConstraintSet, ::MOI.ConstraintReference{MOI.SingleVariable,MOI.LessThan{Float64}}) = true
MOI.getattribute(m::XpressSolverInstance, ::MOI.ConstraintSet, c::MOI.ConstraintReference{MOI.SingleVariable,MOI.LessThan{Float64}}) = MOI.LessThan(m.variable_ub[getcol(m,c)])
MOI.cangetattribute(m::XpressSolverInstance, ::MOI.ConstraintSet, ::MOI.ConstraintReference{MOI.SingleVariable,MOI.Interval{Float64}}) = true
MOI.getattribute(m::XpressSolverInstance, ::MOI.ConstraintSet, c::MOI.ConstraintReference{MOI.SingleVariable,MOI.Interval{Float64}}) = MOI.Interval(m.variable_lb[getcol(m,c)],m.variable_ub[getcol(m,c)])
MOI.cangetattribute(m::XpressSolverInstance, ::MOI.ConstraintSet, ::MOI.ConstraintReference{MOI.SingleVariable,MOI.EqualTo{Float64}}) = true
MOI.getattribute(m::XpressSolverInstance, ::MOI.ConstraintSet, c::MOI.ConstraintReference{MOI.SingleVariable,MOI.EqualTo{Float64}}) = MOI.Interval(m.variable_ub[getcol(m,c)])

# TODO
# function addconstraints! end

# TODO
# function modifyconstraint! end


# TODO
## Constraint attributes

# """
#     ConstraintPrimalStart()
# An initial assignment of the constraint primal values that the solver may use to warm-start the solve.
# """
# struct ConstraintPrimalStart <: AbstractConstraintAttribute end

# """
#     ConstraintDualStart()
# An initial assignment of the constraint duals that the solver may use to warm-start the solve.
# """
# struct ConstraintDualStart <: AbstractConstraintAttribute end

# ConstraintPrimal() = ConstraintPrimal(1)
MOI.cangetattribute(m::XpressSolverInstance, ::MOI.ConstraintPrimal, ::MOI.ConstraintReference{F,S}) where {F<:MOI.ScalarAffineFunction,S} = true
function MOI.getattribute(m::XpressSolverInstance, ::MOI.ConstraintPrimal, c::MOI.ConstraintReference{F,S}) where {F<:MOI.ScalarAffineFunction{Float64},S}
    idx = constraint_storage(m, F, S)[c]
    return -m.constraint_slack[idx]+m.constraint_rhs[idx]
end

# """
#     ConstraintDual(N)
#     ConstraintDual()
# The assignment to the constraint dual values in result `N`.
# If `N` is omitted, it is 1 by default.
# """
# struct ConstraintDual <: AbstractConstraintAttribute
#     N::Int
# end
# ConstraintDual() = ConstraintDual(1)
MOI.cangetattribute(m::XpressSolverInstance, ::MOI.ConstraintDual, ::MOI.ConstraintReference{MOI.SingleVariable,S}) where S = false
MOI.cangetattribute(m::XpressSolverInstance, ::MOI.ConstraintDual, ::Vector{MOI.ConstraintReference{MOI.SingleVariable,S}}) where S = false
MOI.cangetattribute(m::XpressSolverInstance, ::MOI.ConstraintDual, ::Vector{MOI.ConstraintReference{MOI.ScalarAffineFunction,S}}) where S = false
function MOI.getattribute(m::XpressSolverInstance, ::MOI.ConstraintDual, c::MOI.ConstraintReference{MOI.ScalarAffineFunction,S}) where S
    idx = constraint_storage(m, F, S)[c]
    return m.constraint_dual[idx]
end
function MOI.getattribute(m::XpressSolverInstance, ::MOI.ConstraintDual, c::MOI.ConstraintReference{MOI.SingleVariable,S}) where S
    idx = getcol(c)
    return m.variable_redcost[idx]
end
function MOI.getattribute(m::XpressSolverInstance, T::MOI.ConstraintDual, c::Vector{MOI.ConstraintReference{F,S}}) where {F,S}#where F<:MOI.ScalarAffineFunction
    return MOI.getattribute.(m,T,c)
end


# """
#     ConstraintBasisStatus()
# Returns the `BasisStatusCode` of a given constraint, with respect to an available optimal solution basis.
# """
# struct ConstraintBasisStatus <: AbstractConstraintAttribute end

# """
#     ConstraintFunction()
# Return the `AbstractFunction` object used to define the constraint.
# It is guaranteed to be equivalent but not necessarily identical to the function provided by the user.
# """
# struct ConstraintFunction <: AbstractConstraintAttribute end

# """
#     ConstraintSet()
# Return the `AbstractSet` object used to define the constraint.
# """
# struct ConstraintSet <: AbstractConstraintAttribute end
