"""
   xvert, fvert, qcoef = qfit(xm=>fm, x0=>f0, xp=>fp)

Given three points `xm < x0 < xp ` and three corresponding
values `fm`, `f0`, and `fp`, fit a quadratic. Returns the position `xvert` of the vertex,
the quadratic's value `fvert` at `xvert`, and the coefficient `qcoef` of the quadratic term.
`xvert` is a minimum if `qcoef > 0`.

Note that if the three points lie on a line, `qcoef == 0` and both `xvert` and `fvert` will
be infinite.
"""
function qfit(xfm, xf0, xfp)
    xm, fm = xfm
    x0, f0 = xf0
    xp, fp = xfp
    @assert(xp > x0 && x0 > xm && isfinite(xm) && isfinite(xp))
    cm = fm/((xm-x0)*(xm-xp))  # coefficients of Lagrange polynomial
    c0 = f0/((x0-xm)*(x0-xp))
    cp = fp/((xp-xm)*(xp-x0))
    qcoef = cm+c0+cp
    qvalue(x) = cm*(x-x0)*(x-xp) + c0*(x-xm)*(x-xp) + cp*(x-xm)*(x-x0)
    if fm == f0 == fp
        return x0, f0, zero(qcoef)
    end
    xvert = (cm*(x0+xp) + c0*(xm+xp) + cp*(xm+x0))/(2*qcoef)
    return xvert, qvalue(xvert), qcoef
end

## Minimum Edge List utilities
Base.empty!(mel::MELink) = (mel.next = mel; return mel)

function dropnext!(prev, next)
    if next != next.next
        # Drop the next item from the list
        next = next.next
        prev.next = next
    else
        # Drop the last item from the list
        prev.next = prev
        next = prev
    end
    return next
end

function Base.insert!(mel::MELink, w, lf::Pair)
    l, f = lf
    prev, next = mel, mel.next
    while prev != next && w > next.w
        if f <= next.f
            next = dropnext!(prev, next)
        else
            prev = next
            next = next.next
        end
    end
    if w == next.w
        f >= next.f && return mel
        next = dropnext!(prev, next)
    end
    if prev == next
        # we're at the end of the list
        prev.next = typeof(mel)(l, w, f)
    else
        if f < next.f
            prev.next = typeof(mel)(l, w, f, next)
        end
    end
    return mel
end

Base.start(mel::MELink) = mel
Base.done(mel::MELink, state::MELink) = state == state.next
Base.next(mel::MELink, state::MELink) = (state.next, state.next)

function Base.show(io::IO, mel::MELink)
    print(io, "List(")
    next = mel.next
    while mel != next
        print(io, '(', next.w, ", ", next.l, "=>", next.f, "), ")
        mel = next
        next = next.next
    end
    print(io, ')')
end


## Box utilities
function Base.show(io::IO, box::Box)
    x = fill(NaN, ndims(box))
    position!(x, box)
    print(io, "Box@", x)
end

function treeprint(io::IO, f::Function, root::Box)
    show(io, root)
    y = f(root)
    y != nothing && print(io, y)
    if !isleaf(root)
        print(io, '(')
        treeprint(io, f, root.children[1])
        print(io, ", ")
        treeprint(io, f, root.children[2])
        print(io, ", ")
        treeprint(io, f, root.children[3])
        print(io, ')')
    end
end
treeprint(io::IO, root::Box) = treeprint(io, x->nothing, root)

function add_children!(parent::Box, splitdim, xvalues, fvalues, u::Real, v::Real)
    isleaf(parent) || error("cannot add children to non-leaf node")
    (length(xvalues) == 3 && xvalues[1] < xvalues[2] < xvalues[3]) || throw(ArgumentError("xvalues must be monotonic, got $xvalues"))
    parent.splitdim = splitdim
    p = find_parent_with_splitdim(parent, splitdim)
    if isroot(p)
        parent.minmax = (u, v)
    else
        parent.minmax = boxbounds(p)
    end
    parent.xvalues = xvalues
    parent.fvalues = fvalues
    for i = 1:3
        Box(parent, i)  # creates the children of parent
    end
    parent
end

function cycle_free(box)
    p = parent(box)
    while !isroot(p)
        p == box && return false
        p = p.parent
    end
    return true
end

function find_parent_with_splitdim(box::Box, splitdim::Integer)
    while !isroot(box)
        p = parent(box)
        if p.splitdim == splitdim
            return box
        end
        box = p
    end
    return box
end

function find_smallest_child_leaf(box::Box)
    # Not guaranteed to be the smallest function value, it's the smallest that can be
    # reached stepwise
    while !isleaf(box)
        idx = indmin(box.fvalues)
        box = box.children[idx]
    end
    box
end

function boxbounds(box::Box)
    isroot(box) && error("cannot compute bounds on root Box")
    p = parent(box)
    if box.parent_cindex == 1
        return (p.minmax[1], (p.xvalues[1]+p.xvalues[2])/2)
    elseif box.parent_cindex == 2
        return ((p.xvalues[1]+p.xvalues[2])/2, (p.xvalues[2]+p.xvalues[3])/2)
    elseif box.parent_cindex == 3
        return ((p.xvalues[2]+p.xvalues[3])/2, p.minmax[2])
    end
    error("invalid parent_cindex $(box.parent_cindex)")
end
function boxbounds(box::Box, lower::Real, upper::Real)
    isroot(box) && return (lower, upper)
    return boxbounds(box)
end

position(box::Box) = position!(fill(NaN, ndims(box)), box)
function position(box::Box, x0::AbstractVector)
    x = fill(NaN, ndims(box))
    flag = falses(length(x0))
    position!(x, flag, box)
    default_position!(x, flag, x0)
end
function position!(x, box::Box)
    flag = falses(length(x))
    position!(x, flag, box)
    return x
end
function position!(x, flag, box::Box)
    fill!(flag, false)
    nfilled = 0
    while !isroot(box) && nfilled < length(x)
        i = box.parent.splitdim
        if !flag[i]
            x[i] = box.parent.xvalues[box.parent_cindex]
            flag[i] = true
            nfilled += 1
        end
        box = box.parent
    end
    x
end
function default_position!(x, flag, xdefault)
    length(x) == length(flag) == length(xdefault) || throw(DimensionMismatch("all three inputs must have the same length"))
    for i = 1:length(x)
        if !flag[i]
            x[i] = xdefault[i]
        end
    end
    x
end

function boxbounds!(bb, box::Box)
    flag = falses(ndims(box))
    boxbounds!(bb, flag, box)
    return bb
end
function boxbounds!(bb, flag, box::Box)
    fill!(flag, false)
    if isleaf(box)
        bb[box.parent.splitdim] = boxbounds(box)
        flag[box.parent.splitdim] = true
    else
        bb[box.splitdim] = box.minmax
        flag[box.splitdim] = true
    end
    nfilled = 1
    while !isroot(box) && nfilled < ndims(box)
        i = box.parent.splitdim
        if !flag[i]
            bb[i] = boxbounds(box)
            flag[i] = true
            nfilled += 1
        end
        box = box.parent
    end
    bb
end
function boxbounds(box::Box{T}, lower::AbstractVector, upper::AbstractVector) where T
    bb = [(T(lower[i]), T(upper[i])) for i = 1:2]
    QuadDIRECT.boxbounds!(bb, box)
end

function width(box::Box, splitdim::Integer, xdefault::Real, lower::Real, upper::Real)
    p = find_parent_with_splitdim(box, splitdim)
    bb = boxbounds(p, lower, upper)
    x = isroot(p) ? xdefault : p.parent.xvalues[p.parent_cindex]
    max(x-bb[1], bb[2]-x)
end
width(box::Box, splitdim::Integer, xdefault, lower, upper) =
    width(box, splitdim, xdefault[splitdim], lower[splitdim], upper[splitdim])

function Base.extrema(root::Box)
    isleaf(root) && error("tree is empty")
    minv, maxv = extrema(root.fvalues)
    for bx in root
        isleaf(bx) && continue
        mn, mx = extrema(bx.fvalues)
        minv = min(minv, mn)
        maxv = max(maxv, mx)
    end
    minv, maxv
end

## Tree traversal
function get_root(box::Box)
    while !isroot(box)
        box = parent(box)
    end
    box
end

abstract type DepthFirstIterator end

struct DepthFirstLeafIterator{T} <: DepthFirstIterator
    root::Box{T}
end

struct VisitorBool{T}
    box::Box{T}
    done::Bool
end

function visit_leaves(root::Box)
    DepthFirstLeafIterator(root)
end

function Base.start(iter::DepthFirstLeafIterator)
    find_next_leaf(iter, VisitorBool(iter.root, false))
end
Base.start(root::Box) = VisitorBool(root, false)

Base.done(iter::DepthFirstLeafIterator, state::VisitorBool) = state.done
Base.done(root::Box, state::VisitorBool) = state.done

function Base.next(iter::DepthFirstLeafIterator, state::VisitorBool)
    @assert(isleaf(state.box))
    return (state.box, find_next_leaf(iter, state))
end
function find_next_leaf(iter::DepthFirstLeafIterator, state::VisitorBool)
    _, state = next(iter.root, state)
    while !isleaf(state.box) && !state.done
        _, state = next(iter.root, state)
    end
    return state
end

function Base.next(root::Box, state::VisitorBool)
    item, done = state.box, state.done
    if isleaf(item)
        box, i = up(item, root)
        if i <= length(box.children)
            return (item, VisitorBool(box.children[i], false))
        end
        @assert(box == root)
        return (item, VisitorBool(root, true))
    end
    return (item, VisitorBool(item.children[1], false))
end

function up(box, root)
    local i
    while true
        box, i = box.parent, box.parent_cindex+1
        box == root && return (box, i)
        i <= length(box.children) && break
    end
    return (box, i)
end

## Utilities for working with both mutable and immutable vectors
replacecoordinate!(x, i::Integer, val) = (x[i] = val; x)

replacecoordinate!(x::SVector{N,T}, i::Integer, val) where {N,T} =
    SVector{N,T}(_rpc(Tuple(x), i-1, T(val)))
@inline _rpc(t, i, val) = (ifelse(i == 0, val, t[1]), _rpc(tail(t), i-1, val)...)
_rps(::Tuple{}, i, val) = ()

ipcopy!(dest, src) = copy!(dest, src)
ipcopy!(dest::SVector, src) = src

## Other utilities
lohi(x, y) = x <= y ? (x, y) : (y, x)
function lohi(x, y, z)
    @assert(x <= y)
    z <= x && return z, x, y
    z <= y && return x, z, y
    return x, y, z
end

function biggest_interval(a, b, c, d)
    ab, bc, cd = b-a, c-b, d-c
    if ab <= bc && ab <= cd
        return (a, b)
    elseif bc <= ab && bc <= cd
        return (b, c)
    end
    return (c, d)
end
