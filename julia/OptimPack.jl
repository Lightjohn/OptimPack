module OptimPack

# Functions must be imported to be extended with new methods.
import Base.size
import Base.length
import Base.eltype
import Base.ndims
import Base.copy
import Base.dot

const liboptk = "libOptimPack2"

cint(i::Integer) = convert(Cint, i)
cuint(i::Integer) = convert(Cuint, i)

const OPK_SUCCESS = cint( 0)
const OPK_FAILURE = cint(-1)

typealias opkReal Union(Float32,Float64)
typealias opkTypeReal Union(Type{Float32},Type{Float64})

#------------------------------------------------------------------------------
# ERROR MANAGEMENT
#
# We must provide an appropriate error handler to OptimPack in order to throw
# an error exception and avoid aborting the program in case of misuse of the
# library.

opk_error(ptr::Ptr{Uint8}) = (ErrorException(bytestring(ptr)); nothing)

#function opk_error(str::String) = ErrorException(str)

const _opk_error = cfunction(opk_error, Void, (Ptr{Uint8},))

function opk_init()
    ccall((:opk_set_error_handler,liboptk),Ptr{Void},(Ptr{Void},),_opk_error)
    nothing
end

opk_init()

#------------------------------------------------------------------------------
# OBJECT MANAGEMENT
#
# All concrete types derived from the abstract OptimPackObject type have a
# `handle` member which stores the address of the OptimPack object.
abstract OptimPackObject
abstract OptimPackVectorSpace <: OptimPackObject
abstract OptimPackVector      <: OptimPackObject
abstract OptimPackLineSearch  <: OptimPackObject

function references(obj::OptimPackObject)
    ccall((:opk_get_object_references, liboptk), Cptrdiff_t, (Ptr{Void},), obj.handle)
end

# __hold_object__() set a reference on an OptimPack object while
# __drop_object__() discards a reference on an OptimPack object.  The argument
# is the address of the object and these functions are low-level private
# functions.

function __hold_object__(ptr::Ptr{Void})
    ccall((:opk_hold_object, liboptk), Ptr{Void}, (Ptr{Void},), ptr)
end

function __drop_object__(ptr::Ptr{Void})
    ccall((:opk_drop_object, liboptk), Void, (Ptr{Void},), ptr)
end

#------------------------------------------------------------------------------
# VECTOR SPACES
#

type OptimPackShapedVectorSpace{T,N} <: OptimPackVectorSpace
    handle::Ptr{Void}
    eltype::Type{T}
    size::NTuple{N,Int}
    length::Int
end

# Extend basic functions for arrays.
length(vsp::OptimPackShapedVectorSpace) = vsp.length
eltype(vsp::OptimPackShapedVectorSpace) = vsp.eltype
size(vsp::OptimPackShapedVectorSpace) = vsp.size
size(vsp::OptimPackShapedVectorSpace, n::Integer) = vsp.size[n]
ndims(vsp::OptimPackShapedVectorSpace) = length(vsp.size)

OptimPackShapedVectorSpace(T::opkTypeReal, dims::Int...) = OptimPackShapedVectorSpace(T, dims)

function checkdims{N}(dims::NTuple{N,Int})
    number::Int = 1
    for dim in dims
        if dim < 1
            error("invalid dimension")
        end
        number *= dim
    end
    return number
end

function OptimPackShapedVectorSpace{N}(::Type{Cfloat}, dims::NTuple{N,Int})
    length::Int = checkdims(dims)
    ptr = ccall((:opk_new_simple_float_vector_space, liboptk),
                Ptr{Void}, (Cptrdiff_t,), length)
    systemerror("failed to create vector space", ptr == C_NULL)
    obj = OptimPackShapedVectorSpace{Cfloat,N}(ptr, Cfloat, dims, length)
    finalizer(obj, obj -> __drop_object__(obj.handle))
    return obj
end

function OptimPackShapedVectorSpace{N}(::Type{Cdouble}, dims::NTuple{N,Int})
    length::Int = checkdims(dims)
    ptr = ccall((:opk_new_simple_double_vector_space, liboptk),
                Ptr{Void}, (Cptrdiff_t,), length)
    systemerror("failed to create vector space", ptr == C_NULL)
    obj = OptimPackShapedVectorSpace{Cdouble,N}(ptr, Cdouble, dims, length)
    finalizer(obj, obj -> __drop_object__(obj.handle))
    return obj
end

# Note: There are no needs to register a reference for the owner of a
# vector (it already owns one internally).
type OptimPackShapedVector{T<:opkReal,N} <: OptimPackVector
    handle::Ptr{Void}
    owner::OptimPackShapedVectorSpace{T,N}
    array::Union(Array,Nothing)
end

length(v::OptimPackShapedVector) = length(v.owner)
eltype(v::OptimPackShapedVector) = eltype(v.owner)
size(v::OptimPackShapedVector) = size(v.owner)
size(v::OptimPackShapedVector, n::Integer) = size(v.owner, n)
ndims(v::OptimPackShapedVector) = ndims(v.owner)

# FIXME: add means to wrap a Julia array around this or (better?, simpler?)
#        just use allocate a Julia array and wrap a vector around it?
function create{T<:opkReal,N<:Integer}(vspace::OptimPackShapedVectorSpace{T,N})
    ptr = ccall((:opk_vcreate, liboptk), Ptr{Void}, (Ptr{Void},), vspace.handle)
    systemerror("failed to create vector", ptr == C_NULL)
    obj = OptimPackShapedVector{T,N}(ptr, vspace, nothing)
    finalizer(obj, obj -> __drop_object__(obj.handle))
    return obj
end

function wrap{T<:Cfloat,N}(s::OptimPackShapedVectorSpace{T,N}, a::DenseArray{T,N})
    assert(size(a) == size(s))
    ptr = ccall((:opk_wrap_simple_float_vector, liboptk), Ptr{Void},
                (Ptr{Void}, Ptr{Cfloat}, Ptr{Void}, Ptr{Void}),
                s.handle, a, C_NULL, C_NULL)
    systemerror("failed to wrap vector", ptr == C_NULL)
    obj = OptimPackShapedVector{T,N}(ptr, s, a)
    finalizer(obj, obj -> __drop_object__(obj.handle))
    return obj
end

function wrap!{T<:Cfloat,N}(v::OptimPackShapedVector{T,N}, a::DenseArray{T,N})
    assert(size(a) == size(v))
    assert(v.array != nothing)
    status = ccall((:opk_rewrap_simple_float_vector, liboptk), Cint,
                   (Ptr{Void}, Ptr{Cfloat}, Ptr{Void}, Ptr{Void}),
                   v.handle, a, C_NULL, C_NULL)
    systemerror("failed to re-wrap vector", status != OPK_SUCCESS)
    v.array = a
    return v
end

function wrap{T<:Cdouble,N}(s::OptimPackShapedVectorSpace{T,N}, a::DenseArray{T,N})
    assert(size(a) == size(s))
    ptr = ccall((:opk_wrap_simple_double_vector, liboptk), Ptr{Void},
                (Ptr{Void}, Ptr{Cdouble}, Ptr{Void}, Ptr{Void}),
                s.handle, a, C_NULL, C_NULL)
    systemerror("failed to wrap vector", ptr == C_NULL)
    obj = OptimPackShapedVector{T,N}(ptr, s, a)
    finalizer(obj, obj -> __drop_object__(obj.handle))
    return obj
end

function wrap!{T<:Cdouble,N}(v::OptimPackShapedVector{T,N}, a::DenseArray{T,N})
    assert(size(a) == size(v))
    assert(v.array != nothing)
    status = ccall((:opk_rewrap_simple_double_vector, liboptk), Cint,
                   (Ptr{Void}, Ptr{Cdouble}, Ptr{Void}, Ptr{Void}),
                   v.handle, a, C_NULL, C_NULL)
    systemerror("failed to re-wrap vector", status != OPK_SUCCESS)
    v.array = a
    return v
end

#------------------------------------------------------------------------------
# OPERATIONS ON VECTORS

function norm1(vec::OptimPackVector)
    ccall((:opk_vnorm1,liboptk), Cdouble, (Ptr{Void},), vec.handle)
end

function norm2(vec::OptimPackVector)
    ccall((:opk_vnorm2,liboptk), Cdouble, (Ptr{Void},), vec.handle)
end

function norminf(vec::OptimPackVector)
    ccall((:opk_vnorminf,liboptk), Cdouble, (Ptr{Void},), vec.handle)
end

function zero(vec::OptimPackVector)
    ccall((:opk_vzero,liboptk), Void, (Ptr{Void},), vec.handle)
end

function fill(vec::OptimPackVector, val::Real)
    ccall((:opk_vfill, liboptk), Void, (Ptr{Void},Cdouble), vec.handle, val)
end

function copy(dst::OptimPackVector, src::OptimPackVector)
    ccall((:opk_vcopy,liboptk), Void, (Ptr{Void},Ptr{Void}), dst.handle, src.handle)
end

function scale(dst::OptimPackVector, alpha::Real, src::OptimPackVector)
    ccall((:opk_vscale,liboptk), Void, (Ptr{Void},Cdouble,Ptr{Void}),
          dst.handle, alpha, src.handle)
end

function swap(x::OptimPackVector, y::OptimPackVector)
    ccall((:opk_vswap,liboptk), Void, (Ptr{Void},Ptr{Void}), x.handle, y.handle)
end

function dot(x::OptimPackVector, y::OptimPackVector)
    ccall((:opk_vdot,liboptk), Cdouble, (Ptr{Void},Ptr{Void}), x.handle, y.handle)
end

function axpby(dst::OptimPackVector,
               alpha::Real, x::OptimPackVector,
               beta::Real,  y::OptimPackVector)
    ccall((:opk_vaxpby,liboptk), Void,
          (Ptr{Void},Cdouble,Ptr{Void},Cdouble,Ptr{Void}),
          dst.handle, alpha, x.handle, beta, y.handle)
end

function axpbypcz(dst::OptimPackVector,
                  alpha::Real, x::OptimPackVector,
                  beta::Real,  y::OptimPackVector,
                  gamma::Real, z::OptimPackVector)
    ccall((:opk_vaxpbypcz,liboptk), Void,
          (Ptr{Void},Cdouble,Ptr{Void},Cdouble,Ptr{Void},Cdouble,Ptr{Void}),
          dst.handle, alpha, x.handle, beta, y.handle, gamma, y.handle)
end

#------------------------------------------------------------------------------
# OPERATORS

if false
    function apply_direct(op::OptimPackOperator,
                          dst::OptimPackVector,
                          src::OptimPackVector)
        status = ccall((:opk_apply_direct,liboptk), Cint,
                       (Ptr{Void},Ptr{Void},Ptr{Void}),
                       op.handle, dst.handle, src.handle)
        if status != OPK_SUCCESS
            error("something wrong happens")
        end
        nothing
    end

    function apply_adoint(op::OptimPackOperator,
                          dst::OptimPackVector,
                          src::OptimPackVector)
        status = ccall((:opk_apply_adjoint,liboptk), Cint,
                       (Ptr{Void},Ptr{Void},Ptr{Void}),
                       op.handle, dst.handle, src.handle)
        if status != OPK_SUCCESS
            error("something wrong happens")
        end
        nothing
    end
    function apply_inverse(op::OptimPackOperator,
                           dst::OptimPackVector,
                           src::OptimPackVector)
        status = ccall((:opk_apply_inverse,liboptk), Cint,
                       (Ptr{Void},Ptr{Void},Ptr{Void}),
                       op.handle, dst.handle, src.handle)
        if status != OPK_SUCCESS
            error("something wrong happens")
        end
        nothing
    end
end

#------------------------------------------------------------------------------
# NON LINEAR OPTIMIZERS

# Codes returned by the reverse communication version of optimzation
# algorithms.
const OPK_TASK_ERROR      = cint(-1) # An error has ocurred.
const OPK_TASK_COMPUTE_FG = cint( 0) # Caller shall compute f(x) and g(x).
const OPK_TASK_NEW_X	  = cint( 1) # A new iterate is available.
const OPK_TASK_FINAL_X	  = cint( 2) # Algorithm has converged, solution is available.
const OPK_TASK_WARNING	  = cint( 3) # Algorithm terminated with a warning.
#typealias opkTask Cint

abstract OptimPackOptimizer <: OptimPackObject

#------------------------------------------------------------------------------
# NON LINEAR CONJUGATE GRADIENTS

const OPK_NLCG_FLETCHER_REEVES	      = cuint(1)
const OPK_NLCG_HESTENES_STIEFEL	      = cuint(2)
const OPK_NLCG_POLAK_RIBIERE_POLYAK   = cuint(3)
const OPK_NLCG_FLETCHER		      = cuint(4)
const OPK_NLCG_LIU_STOREY	      = cuint(5)
const OPK_NLCG_DAI_YUAN		      = cuint(6)
const OPK_NLCG_PERRY_SHANNO	      = cuint(7)
const OPK_NLCG_HAGER_ZHANG	      = cuint(8)
const OPK_NLCG_POWELL		      = cuint(1<<8) # force beta >= 0
const OPK_NLCG_SHANNO_PHUA	      = cuint(1<<9) # compute scale from previous iterations

# For instance: (OPK_NLCG_POLAK_RIBIERE_POLYAK | OPK_NLCG_POWELL) merely
# corresponds to PRP+ (Polak, Ribiere, Polyak) while (OPK_NLCG_PERRY_SHANNO |
# OPK_NLCG_SHANNO_PHUA) merely corresponds to the conjugate gradient method
# implemented in CONMIN.
#
# Default settings for non linear conjugate gradient (should correspond to
# the method which is, in general, the most successful). */
const OPK_NLCG_DEFAULT  = (OPK_NLCG_HAGER_ZHANG | OPK_NLCG_SHANNO_PHUA)

type OptimPackNLCG <: OptimPackOptimizer
    handle::Ptr{Void}
    vspace::OptimPackVectorSpace
    method::Cuint
    function OptimPackNLCG(space::OptimPackVectorSpace,
                           method::Integer=OPK_NLCG_DEFAULT)
        ptr = ccall((:opk_nlcg_new, liboptk), Ptr{Void},
                (Ptr{Void}, Cuint), space.handle, method)
        systemerror("failed to create optimizer", ptr == C_NULL)
        obj = new(ptr, space, method)
        finalizer(obj, obj -> __drop_object__(obj.handle))
        return obj
    end
end

start(opt::OptimPackNLCG) = ccall((:opk_nlcg_start, liboptk), Cint,
                                  (Ptr{Void},), opt.handle)

function iterate!(opt::OptimPackNLCG, x::OptimPackVector, f::Real, g::OptimPackVector)
    ccall((:opk_nlcg_iterate, liboptk), Cint,
          (Ptr{Void}, Ptr{Void}, Cdouble, Ptr{Void}),
          opt.handle, x.handle, f, g.handle)
end

iterations(opt::OptimPackNLCG) = ccall((:opk_nlcg_get_iterations, liboptk), Cint,
                                       (Ptr{Void},), opt.handle)
evaluations(opt::OptimPackNLCG) = ccall((:opk_nlcg_get_evaluations, liboptk), Cint,
                                        (Ptr{Void},), opt.handle)
restarts(opt::OptimPackNLCG) = ccall((:opk_nlcg_get_restarts, liboptk), Cint,
                                     (Ptr{Void},), opt.handle)

#------------------------------------------------------------------------------
# VARIABLE METRIC OPTIMIZATION METHOD

type OptimPackVMLM <: OptimPackOptimizer
    handle::Ptr{Void}
    vspace::OptimPackVectorSpace
    m::Cptrdiff_t
    function OptimPackVMLM(space::OptimPackVectorSpace,
                           m::Integer=3)
        if m < 1
            error("illegal number of memorized steps")
        end
        if m > length(space)
            m = length(space)
        end
        ptr = ccall((:opk_new_vmlm_optimizer, liboptk), Ptr{Void},
                (Ptr{Void}, Cptrdiff_t, Cdouble, Cdouble, Cdouble),
                    space.handle, m, 0.0, 0.0, 0.0)
        systemerror("failed to create optimizer", ptr == C_NULL)
        obj = new(ptr, space, m)
        finalizer(obj, obj -> __drop_object__(obj.handle))
        return obj
    end
end

start(opt::OptimPackVMLM) = ccall((:opk_vmlm_start, liboptk), Cint,
                                  (Ptr{Void},), opt.handle)

function iterate!(opt::OptimPackVMLM, x::OptimPackVector, f::Real, g::OptimPackVector)
    ccall((:opk_vmlm_iterate, liboptk), Cint,
          (Ptr{Void}, Ptr{Void}, Cdouble, Ptr{Void}),
          opt.handle, x.handle, f, g.handle)
end

iterations(opt::OptimPackVMLM) = ccall((:opk_get_vmlm_iterations, liboptk), Cint,
                                       (Ptr{Void},), opt.handle)
evaluations(opt::OptimPackVMLM) = ccall((:opk_get_vmlm_evaluations, liboptk), Cint,
                                        (Ptr{Void},), opt.handle)
restarts(opt::OptimPackVMLM) = ccall((:opk_get_vmlm_restarts, liboptk), Cint,
                                     (Ptr{Void},), opt.handle)

#------------------------------------------------------------------------------
# NON LINEAR OPTIMIZATION

# x = minimize(fg!, x0)
#
#   This driver minimizes a smooth multi-variate function.  `fg!` is a function
#   which takes two arguments, `x` and `g` and which, for the given variables x,
#   stores the gradient of the function in `g` and returns the value of the
#   function:
#
#      f = fg!(x, g)
#
#   `x0` are the initial variables, they are left unchanged, they must be a
#   single or double precision floating point array.
#
function nlcg{T,N}(fg!::Function, x0::Array{T,N},
                   method::Integer=OPK_NLCG_DEFAULT;
                   verb::Bool=false)
    #assert(T == Type{Cdouble} || T == Type{Cfloat})

    # Allocate workspaces
    dims = size(x0)
    space = OptimPackShapedVectorSpace(T, dims)
    x = copy(x0)
    g = Array(T, dims)
    wx = wrap(space, x)
    wg = wrap(space, g)
    opt = OptimPackNLCG(space, method)
    task = start(opt)
    while true
        if task == OPK_TASK_COMPUTE_FG
            f = fg!(x, g)
        elseif task == OPK_TASK_NEW_X || task == OPK_TASK_FINAL_X
            if verb
                iter = iterations(opt)
                eval = evaluations(opt)
                @printf("%4d  %4d  %.16E  %.5E\n", iter, eval, f, norm2(wg))
            end
            if task == OPK_TASK_FINAL_X
                return x
            end
        elseif task == OPK_TASK_WARNING
            @printf("some warnings...\n")
            return x
        elseif task == OPK_TASK_ERROR
            @printf("some errors...\n")
            return nothing
        else
            @printf("unexpected task...\n")
            return nothing
        end
        task = iterate!(opt, wx, f, wg)
    end
end

function vmlm{T,N}(fg!::Function, x0::Array{T,N},
                   m::Integer=3;
                   verb::Bool=false)
    #assert(T == Type{Cdouble} || T == Type{Cfloat})

    # Allocate workspaces
    dims = size(x0)
    space = OptimPackShapedVectorSpace(T, dims)
    x = copy(x0)
    g = Array(T, dims)
    wx = wrap(space, x)
    wg = wrap(space, g)
    opt = OptimPackVMLM(space, m)
    task = start(opt)
    while true
        if task == OPK_TASK_COMPUTE_FG
            f = fg!(x, g)
        elseif task == OPK_TASK_NEW_X || task == OPK_TASK_FINAL_X
            if verb
                iter = iterations(opt)
                eval = evaluations(opt)
                @printf("%4d  %4d  %.16E  %.5E\n", iter, eval, f, norm2(wg))
            end
            if task == OPK_TASK_FINAL_X
                return x
            end
        elseif task == OPK_TASK_WARNING
            @printf("some warnings...\n")
            return x
        elseif task == OPK_TASK_ERROR
            @printf("some errors...\n")
            return nothing
        else
            @printf("unexpected task...\n")
            return nothing
        end
        task = iterate!(opt, wx, f, wg)
    end
end

end
