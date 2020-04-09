#######################################################################
# Onsite/Hopping selectors
#######################################################################
abstract type Selector{M,S} end

struct OnsiteSelector{M,S} <: Selector{M,S}
    region::M
    sublats::S  # NTuple{N,NameType} (unresolved) or Vector{Int} (resolved on a lattice)
    forcehermitian::Bool
end

struct HoppingSelector{M,S,D,T} <: Selector{M,S}
    region::M
    sublats::S  # NTuple{N,Tuple{NameType,NameType}} (unres) or Vector{Tuple{Int,Int}} (res)
    dns::D
    range::T
    forcehermitian::Bool
end

"""
    onsiteselector(; region = missing, sublats = missing, forcehermitian = true)

Specifies a subset of onsites energies in a given hamiltonian. Only sites at position `r` in
sublattice with name `s::NameType` will be selected if `region(r) && s in sublats` is true.
Any missing `region` or `sublat` will not be used to constraint the selection. The keyword
`forcehermitian` specifies whether an `OnsiteTerm` applied to a selected site should be made
hermitian.

# See also:
    `hoppingselector`, `onsite`, `hopping`
"""
onsiteselector(; region = missing, sublats = missing, forcehermitian = true) =
    OnsiteSelector(region, sanitize_sublats(sublats), forcehermitian)

"""
    hoppingselector(; region = missing, sublats = missing, dn = missing, range = missing, forcehermitian = true)

Specifies a subset of hoppings in a given hamiltonian. Only hoppings between two sites at
positions `r₁ = r - dr/2` and `r₂ = r + dr`, belonging to unit cells at integer distance
`dn´` and to sublattices `s₁` and `s₂` will be selected if: `region(r, dr) && s in sublats
&& dn´ in dn && norm(dr) <= range`. If any of these is `missing` it will not be used to
constraint the selection. The keyword `forcehermitian` specifies whether a `HoppingTerm`
applied to a selected hopping should be made hermitian.

# See also:
    `onsiteselector`, `onsite`, `hopping`
"""
hoppingselector(; region = missing, sublats = missing, dn = missing, range = missing, forcehermitian = true) =
    HoppingSelector(region, sanitize_sublatpairs(sublats), sanitize_dn(dn), sanitize_range(range), forcehermitian)

sanitize_sublats(s::Missing) = missing
sanitize_sublats(s::Integer) = (nametype(s),)
sanitize_sublats(s::NameType) = (s,)
sanitize_sublats(s::Tuple) = nametype.(s)
sanitize_sublats(s::Tuple{}) = ()
sanitize_sublats(n) = throw(ErrorException(
    "`sublats` for `onsite` must be either `missing`, an `s` or a tuple of `s`s, with `s::$NameType` is a sublattice name"))

sanitize_sublatpairs(s::Missing) = missing
sanitize_sublatpairs((s1, s2)::NTuple{2,Union{Integer,NameType}}) = ((nametype(s1), nametype(s2)),)
sanitize_sublatpairs((s2, s1)::Pair) = sanitize_sublatpairs((s1, s2))
sanitize_sublatpairs(s::Union{Integer,NameType}) = sanitize_sublatpairs((s,s))
sanitize_sublatpairs(s::NTuple{N,Any}) where {N} =
    ntuple(n -> first(sanitize_sublatpairs(s[n])), Val(N))
sanitize_sublatpairs(s) = throw(ErrorException(
    "`sublats` for `hopping` must be either `missing`, a tuple `(s₁, s₂)`, or a tuple of such tuples, with `sᵢ::$NameType` a sublattice name"))

sanitize_dn(dn::Missing) = missing
sanitize_dn(dn::Tuple{Vararg{NTuple{N}}}) where {N} = SVector{N,Int}.(dn)
sanitize_dn(dn::Tuple{Vararg{Number,N}}) where {N} = (SVector{N,Int}(dn),)
sanitize_dn(dn::Tuple{}) = ()

sanitize_range(::Missing) = missing
sanitize_range(range::Real) = isfinite(range) ? float(range) + sqrt(eps(float(range))) : float(range)

sublats(s::OnsiteSelector{<:Any,Missing}, lat::AbstractLattice) = collect(1:nsublats(lat))

function sublats(s::OnsiteSelector{<:Any,<:Tuple}, lat::AbstractLattice)
    names = lat.unitcell.names
    ss = Int[]
    for name in s.sublats
        i = findfirst(isequal(name), names)
        i !== nothing && push!(ss, i)
    end
    return ss
end

sublats(s::HoppingSelector{<:Any,Missing}, lat::AbstractLattice) =
    vec(collect(Iterators.product(1:nsublats(lat), 1:nsublats(lat))))

function sublats(s::HoppingSelector{<:Any,<:Tuple}, lat::AbstractLattice)
    names = lat.unitcell.names
    ss = Tuple{Int,Int}[]
    for (n1, n2) in s.sublats
        i1 = findfirst(isequal(n1), names)
        i2 = findfirst(isequal(n2), names)
        i1 !== nothing && i2 !== nothing && push!(ss, (i1, i2))
    end
    return ss
end

# selector already resolved for a lattice
sublats(s::Selector{<:Any,<:Vector}, lat) = s.sublats

# API

resolve(s::HoppingSelector, lat::AbstractLattice) =
    HoppingSelector(s.region, sublats(s, lat), _checkdims(s.dns, lat), s.range, s.forcehermitian)
resolve(s::OnsiteSelector, lat::AbstractLattice) = OnsiteSelector(s.region, sublats(s, lat), s.forcehermitian)

_checkdims(dns::Missing, lat::Lattice{E,L}) where {E,L} = dns
_checkdims(dns::Tuple{Vararg{SVector{L,Int}}}, lat::Lattice{E,L}) where {E,L} = dns
_checkdims(dns, lat::Lattice{E,L}) where {E,L} =
    throw(DimensionMismatch("Specified cell distance `dn` does not match lattice dimension $L"))

# are sites at (i,j) and (dni, dnj) or (dn, 0) selected?
(s::OnsiteSelector)(lat::AbstractLattice, (i, j)::Tuple, (dni, dnj)::Tuple{SVector, SVector}) =
    isonsite((i, j), (dni, dnj)) && isinregion(i, dni, s.region, lat) && isinsublats(sublat(lat, i), s.sublats)

(s::HoppingSelector)(lat::AbstractLattice, inds, dns) =
    !isonsite(inds, dns) && isinregion(inds, dns, s.region, lat) && isindns(dns, s.dns) &&
    isinrange(inds, s.range, lat) && isinsublats(sublat.(Ref(lat), inds), s.sublats)

isonsite((i, j), (dni, dnj)) = i == j && dni == dnj

isinregion(i::Int, dn, ::Missing, lat) = true
isinregion(i::Int, dn, region::Function, lat) = region(sites(lat)[i] + bravais(lat) * dn)

isinregion(is::Tuple{Int,Int}, dns, ::Missing, lat) = true
function isinregion((row, col)::Tuple{Int,Int}, (dnrow, dncol), region::Function, lat)
    br = bravais(lat)
    r, dr = _rdr(sites(lat)[col] + br * dncol, sites(lat)[row] + br * dnrow)
    return region(r, dr)
end

isinsublats(s::Int, ::Missing) = true
isinsublats(s::Int, sublats::Vector{Int}) = s in sublats
isinsublats(ss::Tuple{Int,Int}, ::Missing) = true
isinsublats(ss::Tuple{Int,Int}, sublats::Vector{Tuple{Int,Int}}) = ss in sublats
isinsublats(s, sublats) =
    throw(ArgumentError("Sublattices $sublats in selector are not resolved."))

isindns((dnrow, dncol)::Tuple{SVector,SVector}, dns) = isindns(dnrow - dncol, dns)
isindns(dn::SVector{L,Int}, dns::Tuple{Vararg{SVector{L,Int}}}) where {L} = dn in dns
isindns(dn::SVector, dns::Missing) = true
isindns(dn, dns) =
    throw(ArgumentError("Cell distance dn in selector is incompatible with Lattice."))

isinrange(inds, ::Missing, lat) = true
isinrange((row, col)::Tuple{Int,Int}, range::Number, lat) =
    norm(sites(lat)[col] - sites(lat)[row]) <= range

# injects non-missing fields of s´ into s
updateselector!(s::OnsiteSelector, s´::OnsiteSelector) =
    OnsiteSelector(updateselector!.(
        (s.region,  s.sublats,  s.forcehermitian),
        (s´.region, s´.sublats, s´.forcehermitian))...)
updateselector!(s::HoppingSelector, s´::HoppingSelector) =
    HoppingSelector(updateselector!.(
        (s.region,  s.sublats,  s.dns,  s.range,  s.forcehermitian),
        (s´.region, s´.sublats, s´.dns, s´.range, s´.forcehermitian))...)
updateselector!(o, o´::Missing) = o
updateselector!(o, o´) = o´

#######################################################################
# Tightbinding types
#######################################################################
abstract type TightbindingModelTerm end
abstract type AbstractOnsiteTerm <: TightbindingModelTerm end
abstract type AbstractHoppingTerm <: TightbindingModelTerm end

struct TightbindingModel{N,T<:Tuple{Vararg{TightbindingModelTerm,N}}}
    terms::T
end

struct OnsiteTerm{F,S<:OnsiteSelector,C} <: AbstractOnsiteTerm
    o::F
    selector::S
    coefficient::C
end

struct HoppingTerm{F,S<:HoppingSelector,C} <: AbstractHoppingTerm
    t::F
    selector::S
    coefficient::C
end

#######################################################################
# TightbindingModel API
#######################################################################
terms(t::TightbindingModel) = t.terms

TightbindingModel(ts::TightbindingModelTerm...) = TightbindingModel(ts)

(m::TightbindingModel)(r, dr) = sum(t -> t(r, dr), m.terms)

# External API #

Base.:*(x, m::TightbindingModel) = TightbindingModel(x .* m.terms)
Base.:*(m::TightbindingModel, x) = x * m
Base.:-(m::TightbindingModel) = TightbindingModel((-1) .* m.terms)

Base.:+(m::TightbindingModel, t::TightbindingModel) = TightbindingModel((m.terms..., t.terms...))
Base.:-(m::TightbindingModel, t::TightbindingModel) = m + (-t)

function Base.show(io::IO, m::TightbindingModel{N}) where {N}
    ioindent = IOContext(io, :indent => "  ")
    print(io, "TightbindingModel{$N}: model with $N terms", "\n")
    foreach(t -> print(ioindent, t, "\n"), m.terms)
end

LinearAlgebra.ishermitian(m::TightbindingModel) = all(t -> ishermitian(t), m.terms)

#######################################################################
# TightbindingModelTerm API
#######################################################################
OnsiteTerm(t::OnsiteTerm, os::OnsiteSelector) =
    OnsiteTerm(t.o, os, t.coefficient)

(o::OnsiteTerm{<:Function})(r,dr) = o.coefficient * o.o(r)
(o::OnsiteTerm)(r,dr) = o.coefficient * o.o

HoppingTerm(t::HoppingTerm, os::HoppingSelector) =
    HoppingTerm(t.t, os, t.coefficient)

(h::HoppingTerm{<:Function})(r, dr) = h.coefficient * h.t(r, dr)
(h::HoppingTerm)(r, dr) = h.coefficient * h.t

sublats(t::TightbindingModelTerm, lat) = sublats(t.selector, lat)

displayparameter(::Type{<:Function}) = "Function"
displayparameter(::Type{T}) where {T} = "$T"

function Base.show(io::IO, o::OnsiteTerm{F}) where {F}
    i = get(io, :indent, "")
    print(io,
"$(i)OnsiteTerm{$(displayparameter(F))}:
$(i)  Sublattices      : $(o.selector.sublats === missing ? "any" : o.selector.sublats)
$(i)  Force hermitian  : $(o.selector.forcehermitian)
$(i)  Coefficient      : $(o.coefficient)")
end

function Base.show(io::IO, h::HoppingTerm{F}) where {F}
    i = get(io, :indent, "")
    print(io,
"$(i)HoppingTerm{$(displayparameter(F))}:
$(i)  Sublattice pairs : $(h.selector.sublats === missing ? "any" : (t -> Pair(reverse(t)...)).(h.selector.sublats))
$(i)  dn cell distance : $(h.selector.dns === missing ? "any" : h.selector.dns)
$(i)  Hopping range    : $(round(h.selector.range, digits = 6))
$(i)  Force hermitian  : $(h.selector.forcehermitian)
$(i)  Coefficient      : $(h.coefficient)")
end

# External API #
"""
    onsite(o; kw...)
    onsite(o, onsiteselector(; kw...))

Create an `TightbindingModelTerm` that applies an onsite energy `o` to a `Lattice` when
creating a `Hamiltonian` with `hamiltonian`. A subset of sites can be specified with the
`kw...`, see `onsiteselector` for details.

The onsite energy `o` can be a number, a matrix (preferably `SMatrix`), a `UniformScaling`
(e.g. `3*I`) or a function of the form `r -> ...` for a position-dependent onsite energy.

The dimension of `o::AbstractMatrix` must match the orbital dimension of applicable
sublattices (see also `orbitals` option for `hamiltonian`). If `o::UniformScaling` it will
be converted to an identity matrix of the appropriate size when applied to
multiorbital sublattices. Similarly, if `o::SMatrix` it will be truncated or padded to the
appropriate size.

`TightbindingModelTerm`s created with `onsite` or `hopping` can be added or substracted
together to build more complicated `TightbindingModel`s.

    onsite(model::TightbindingModel; kw...)

Return a `TightbindingModel` with only the onsite terms of `model`. Any non-missing `kw` is
applied to all such terms.

# Examples
```
julia> model = onsite(1, sublats = (:A,:B)) - hopping(2, sublats = :A=>:A)
TightbindingModel{2}: model with 2 terms
  OnsiteTerm{Int64}:
    Sublattices      : (:A, :B)
    Force hermitian  : true
    Coefficient      : 1
  HoppingTerm{Int64}:
    Sublattice pairs : (:A => :A,)
    dn cell distance : any
    Hopping range    : 1.0
    Force hermitian  : true
    Coefficient      : -1

julia> newmodel = onsite(model; sublats = :A) + hopping(model)
TightbindingModel{2}: model with 2 terms
  OnsiteTerm{Int64}:
    Sublattices      : (:A,)
    Force hermitian  : true
    Coefficient      : 1
  HoppingTerm{Int64}:
    Sublattice pairs : (:A => :A,)
    dn cell distance : any
    Hopping range    : 1.0
    Force hermitian  : true
    Coefficient      : -1

julia> LatticePresets.honeycomb() |> hamiltonian(onsite(r->@SMatrix[1 2; 3 4]), orbitals = Val(2))
Hamiltonian{<:Lattice} : Hamiltonian on a 2D Lattice in 2D space
  Bloch harmonics  : 1 (SparseMatrixCSC, sparse)
  Harmonic size    : 2 × 2
  Orbitals         : ((:a, :a), (:a, :a))
  Element type     : 2 × 2 blocks (Complex{Float64})
  Onsites          : 2
  Hoppings         : 0
  Coordination     : 0.0

```

# See also:
    `hopping`, `onsiteselector`, `hoppingselector`
"""
onsite(o; kw...) = onsite(o, onsiteselector(; kw...))

onsite(o, selector::Selector) =
    TightbindingModel(OnsiteTerm(o, selector, 1))

onsite(m::TightbindingModel, selector::Selector) =
    TightbindingModel(_onlyonsites(selector, m.terms...))

_onlyonsites(s, t::OnsiteTerm, args...) =
    (OnsiteTerm(t, updateselector!(t.selector, s)), _onlyonsites(s, args...)...)
_onlyonsites(s, t::HoppingTerm, args...) = (_onlyonsites(s, args...)...,)
_onlyonsites(s) = ()

"""
    hopping(t; range = 1, kw...)
    hopping(t, hoppingselector(; range = 1, kw...))

Create an `TightbindingModelTerm` that applies a hopping `t` to a `Lattice` when
creating a `Hamiltonian` with `hamiltonian`. A subset of hoppings can be specified with the
`kw...`, see `hoppingselector` for details. Note that a default `range = 1` is assumed.

The hopping amplitude `t` can be a number, a matrix (preferably `SMatrix`), a
`UniformScaling` (e.g. `3*I`) or a function of the form `(r, dr) -> ...` for a
position-dependent hopping (`r` is the bond center, and `dr` the bond vector). If `sublats`
is specified as a sublattice name pair, or tuple thereof, `hopping` is only applied between
sublattices with said names.

The dimension of `t::AbstractMatrix` must match the orbital dimension of applicable
sublattices (see also `orbitals` option for `hamiltonian`). If `t::UniformScaling` it will
be converted to a (possibly rectangular) identity matrix of the appropriate size when
applied to multiorbital sublattices. Similarly, if `t::SMatrix` it will be truncated or
padded to the appropriate size.

`TightbindingModelTerm`s created with `onsite` or `hopping` can be added or substracted
together to build more complicated `TightbindingModel`s.

    hopping(model::TightbindingModel; kw...)

Return a `TightbindingModel` with only the hopping terms of `model`. Any non-missing `kw` is
applied to all such terms.

# Examples
```
julia> model = onsite(1) - hopping(2, dn = ((1,2), (0,0)), sublats = :A=>:B)
TightbindingModel{2}: model with 2 terms
  OnsiteTerm{Int64}:
    Sublattices      : any
    Force hermitian  : true
    Coefficient      : 1
  HoppingTerm{Int64}:
    Sublattice pairs : (:A => :B,)
    dn cell distance : ([1, 2], [0, 0])
    Hopping range    : 1.0
    Force hermitian  : true
    Coefficient      : -1

julia> newmodel = onsite(model) + hopping(model, range = 2)
TightbindingModel{2}: model with 2 terms
  OnsiteTerm{Int64}:
    Sublattices      : any
    Force hermitian  : true
    Coefficient      : 1
  HoppingTerm{Int64}:
    Sublattice pairs : (:A => :B,)
    dn cell distance : ([1, 2], [0, 0])
    Hopping range    : 2.0
    Force hermitian  : true
    Coefficient      : -1

julia> LatticePresets.honeycomb() |> hamiltonian(hopping((r,dr) -> cos(r[1]), sublats = ((:A,:A), (:B,:B))))
Hamiltonian{<:Lattice} : Hamiltonian on a 2D Lattice in 2D space
  Bloch harmonics  : 7 (SparseMatrixCSC, sparse)
  Harmonic size    : 2 × 2
  Orbitals         : ((:a,), (:a,))
  Element type     : scalar (Complex{Float64})
  Onsites          : 0
  Hoppings         : 12
  Coordination     : 6.0
```

# See also:
    `onsite`, `onsiteselector`, `hoppingselector`
"""
hopping(t; range = 1, kw...) =
    hopping(t, hoppingselector(; range = range, kw...))
hopping(t, selector) = TightbindingModel(HoppingTerm(t, selector, 1))

hopping(m::TightbindingModel, selector::Selector) =
    TightbindingModel(_onlyhoppings(selector, m.terms...))

_onlyhoppings(s, t::OnsiteTerm, args...) = (_onlyhoppings(s, args...)...,)
_onlyhoppings(s, t::HoppingTerm, args...) =
    (HoppingTerm(t, updateselector!(t.selector, s)), _onlyhoppings(s, args...)...)
_onlyhoppings(s) = ()

Base.:*(x, o::OnsiteTerm) =
    OnsiteTerm(o.o, o.selector, x * o.coefficient)
Base.:*(x, t::HoppingTerm) = HoppingTerm(t.t, t.selector, x * t.coefficient)
Base.:*(t::TightbindingModelTerm, x) = x * t
Base.:-(t::TightbindingModelTerm) = (-1) * t

LinearAlgebra.ishermitian(t::OnsiteTerm) = t.selector.forcehermitian
LinearAlgebra.ishermitian(t::HoppingTerm) = t.selector.forcehermitian

#######################################################################
# offdiagonal
#######################################################################
"""
    offdiagonal(model, lat, nsublats::NTuple{N,Int})

Build a restricted version of `model` that applies only to off-diagonal blocks formed by
sublattice groups of size `nsublats`.
"""
offdiagonal(m::TightbindingModel, lat, nsublats) =
    TightbindingModel(offdiagonal.(m.terms, Ref(lat), Ref(nsublats)))

offdiagonal(o::OnsiteTerm, lat, nsublats) =
    throw(ArgumentError("No onsite terms allowed in off-diagonal coupling"))

function offdiagonal(t::HoppingTerm, lat, nsublats)
    selector´ = resolve(t.selector, lat)
    s = selector´.sublats
    sr = sublatranges(nsublats...)
    filter!(spair ->  findblock(first(spair), sr) != findblock(last(spair), sr), s)
    return HoppingTerm(t.t, selector´, t.coefficient)
end

sublatranges(i::Int, is::Int...) = _sublatranges((1:i,), is...)
_sublatranges(rs::Tuple, i::Int, is...) = _sublatranges((rs..., last(last(rs)) + 1: last(last(rs)) + i), is...)
_sublatranges(rs::Tuple) = rs

findblock(s, sr) = findfirst(r -> s in r, sr)

#######################################################################
# onsite! and hopping!
#######################################################################
abstract type ElementModifier{V,F,S} end

struct Onsite!{V<:Val,F<:Function,S<:Selector} <: ElementModifier{V,F,S}
    f::F
    needspositions::V    # Val{false} for f(o; kw...), Val{true} for f(o, r; kw...) or other
    selector::S
    addconjugate::Bool   # determines whether to return f(o) or (f(o) + f(o')')/2
                         # (equatl to selector.forcehermitian)
end

Onsite!(f, selector) =
    Onsite!(f, Val(!applicable(f, 0.0)), selector, false)

struct Hopping!{V<:Val,F<:Function,S<:Selector} <: ElementModifier{V,F,S}
    f::F
    needspositions::V    # Val{false} for f(h; kw...), Val{true} for f(h, r, dr; kw...) or other
    selector::S
    addconjugate::Bool   # determines whether to return f(t) or (f(t) + f(t')')/2 
                         # (equal to *unresolved* selector.sublats and selector.forcehermitian)
end

Hopping!(f, selector) =
    Hopping!(f, Val(!applicable(f, 0.0)), selector, false)

# API #

"""
    onsite!(f; kw...)
    onsite!(f, onsiteselector(; kw...))

Create an `ElementModifier`, to be used with `parametric`, that applies `f` to onsite
energies specified by `onsiteselector(; kw...)`. The form of `f` may be `f = (o; kw...) ->
...` or `f = (o, r; kw...) -> ...` if the modification is position (`r`) dependent. The
former is naturally more efficient, as there is no need to compute the positions of each
onsite energy.

# See also:
    `hopping!`, `parametric`
"""
onsite!(f; kw...) =
    onsite!(f, onsiteselector(; kw...))
onsite!(f, selector) = Onsite!(f, selector)

"""
    hopping!(f; kw...)
    hopping!(f, hoppingselector(; kw...))

Create an `ElementModifier`, to be used with `parametric`, that applies `f` to hoppings
specified by `hoppingselector(; kw...)`. The form of `f` may be `f = (t; kw...) -> ...` or
`f = (t, r, dr; kw...) -> ...` if the modification is position (`r, dr`) dependent. The
former is naturally more efficient, as there is no need to compute the positions of the two
sites involved in each hopping.

# See also:
    `onsite!`, `parametric`
"""
hopping!(f; kw...) = hopping!(f, hoppingselector(; kw...))
hopping!(f, selector) = Hopping!(f, selector)

function resolve(o::Onsite!, lat)
    addconjugate = o.selector.forcehermitian
    Onsite!(o.f, o.needspositions, resolve(o.selector, lat), addconjugate)
end

function resolve(h::Hopping!, lat)
    addconjugate = h.selector.sublats === missing && h.selector.forcehermitian
    Hopping!(h.f, h.needspositions, resolve(h.selector, lat), addconjugate)
end

# Intended for resolved ElementModifiers only
@inline (o!::Onsite!{Val{false}})(o, r; kw...) = o!(o; kw...)
@inline (o!::Onsite!{Val{false}})(o, r, dr; kw...) = o!(o; kw...)
@inline (o!::Onsite!{Val{false}})(o; kw...) =
    o!.addconjugate ? 0.5 * (o!.f(o; kw...) + o!.f(o'; kw...)') : o!.f(o; kw...)
@inline (o!::Onsite!{Val{true}})(o, r, dr; kw...) = o!(o, r; kw...)
@inline (o!::Onsite!{Val{true}})(o, r; kw...) =
    o!.addconjugate ? 0.5 * (o!.f(o, r; kw...) + o!.f(o', r; kw...)') : o!.f(o, r; kw...)

@inline (h!::Hopping!{Val{false}})(t, r, dr; kw...) = h!(t; kw...)
@inline (h!::Hopping!{Val{false}})(t; kw...) =
    h!.addconjugate ? 0.5 * (h!.f(t; kw...) + h!.f(t'; kw...)') : h!.f(t; kw...)
@inline (h!::Hopping!{Val{true}})(t, r, dr; kw...) =
    h!.addconjugate ? 0.5 * (h!.f(t, r, dr; kw...) + h!.f(t', r, -dr; kw...)') : h!.f(t, r, dr; kw...)