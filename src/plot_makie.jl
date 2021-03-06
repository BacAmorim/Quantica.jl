using .Makie
using GeometryTypes: Cylinder
import .Makie.AbstractPlotting: plot!, plot, to_value

#######################################################################
# Tools
#######################################################################

function matrixidx(h::AbstractSparseMatrix, row, col)
    for ptr in nzrange(h, col)
        rowvals(h)[ptr] == row && return ptr
    end
    return 0
end

matrixidx(h::DenseMatrix, row, col) = LinearIndices(h)[row, col]

transparent(rgba::RGBAf0, v = 0.5) = RGBAf0(rgba.r, rgba.g, rgba.b, rgba.alpha * v)

function darken(rgba::RGBAf0, v = 0.66)
    r = max(0, min(rgba.r * (1 - v), 1))
    g = max(0, min(rgba.g * (1 - v), 1))
    b = max(0, min(rgba.b * (1 - v), 1))
    RGBAf0(r,g,b,rgba.alpha)
end
function lighten(rgba, v = 0.66)
    darken(rgba, -v)
end

#######################################################################
# plot(::Hamiltonian)
#######################################################################

function plot(h::Hamiltonian{<:Lattice}; resolution = (1000, 1000), kw...)
    scene = hamiltonianplot(h; resolution = resolution, scale_plot = false, kw...)
    plot = scene[end]
    plot[:tooltips][] && addtooltips!(scene, h)
    scale!(scene)
    return scene
end

@recipe(HamiltonianPlot, hamiltonian) do scene
    Theme(
        allintra = false, allcells = true, showsites = true, showlinks = true,
        shadedsites = false, shadedlinks = false, dimming = 0.75,
        siteradius = 0.2, siteborder = 3, siteborderdarken = 1.0, linkdarken = 0.0,
        linkthickness = 6, linkoffset = missing, linkradius = 0.1,
        tooltips = true, digits = 3,
        _tooltips_rowcolhar = Vector{Tuple{Int,Int,Int}}[],
        colors = map(t -> RGBAf0(t...),
            ((0.960,0.600,.327), (0.410,0.067,0.031),(0.940,0.780,0.000),
            (0.640,0.760,0.900),(0.310,0.370,0.650),(0.600,0.550,0.810),
            (0.150,0.051,0.100),(0.870,0.530,0.640),(0.720,0.130,0.250))),
        light = Vec3f0[[0, 0, 10], [0, 10, 0], [10, 0, 0], [10, 10, 10], [-10, -10, -10]]
    )
end

function plot!(plot::HamiltonianPlot)
    h = to_value(plot[1])
    lat = h.lattice
    colors = Iterators.cycle(plot[:colors][])
    sublats = Quantica.sublats(lat)

    mdist = Quantica.meandist(h)
    mdist > 0 || (mdist = 1)
    plot[:siteradius][] *= mdist/2
    plot[:linkradius][] *= mdist/2

    lo = plot[:linkoffset][]
    plot[:linkoffset][] =
        lo === missing ? √max(1-(plot[:linkradius][]/plot[:siteradius][])^2, 0) : lo * mdist

    # plot sites
    plot[:showsites][] &&
        for (n, har) in enumerate(h.harmonics), (ssrc, csrc) in zip(sublats, colors)
            iszero(har.dn) || plot[:allcells][] || break
            csrc´ = iszero(har.dn) ? csrc : transparent(csrc, 1 - plot[:dimming][])
            itr = siterange(lat, ssrc)
            plotsites!(plot, lat, itr, har.dn, n, csrc´)
        end

    # plot links
    plot[:showlinks][] &&
        for (n, har) in enumerate(h.harmonics)
            iszero(har.dn) || plot[:allcells][] || break
            for (ssrc, csrc) in zip(sublats, colors)
                csrc´ = iszero(har.dn) ? csrc : transparent(csrc, 1 - plot[:dimming][])
                csrc´ = darken(csrc´, plot[:linkdarken][])
                for (sdst, cdst) in zip(sublats, colors)
                    itr = Quantica.nonzero_indices(har, siterange(lat, sdst), siterange(lat, ssrc))
                    plotlinks!(plot, lat, itr, har.dn, n, csrc´)
                end
            end
        end

    return plot
end

function plotsites!(plot, lat, srange, dn, n, color)
    allsites = Quantica.sites(lat)
    br = lat.bravais.matrix
    sites = [padright(allsites[i] + br * dn, Val(3)) for i in srange]
    plot[:tooltips][] && (tt = [(site, 0, n) for site in srange])
    if !isempty(sites)
        plot[:shadedsites][] ? plotsites_hi!(plot, sites, color) : plotsites_lo!(plot, sites, color)
        plot[:tooltips][] && push!(plot[:_tooltips_rowcolhar][], tt)
    end
    return plot
end

function plotsites_lo!(plot, sites, color)
    scatter!(plot, sites;
        color = color,
        markersize = 2 * plot[:siteradius][],
        strokewidth = plot[:siteborder][],
        strokecolor = darken(color, plot[:siteborderdarken][]))
    return nothing
end

function plotsites_hi!(plot, sites, color)
    meshscatter!(plot, sites;
        color = color,
        markersize = plot[:siteradius][], light = plot[:light][])
    return nothing
end

function plotlinks!(plot, lat, itr, dn, n, color)
    links = Pair{SVector{3,Float32},SVector{3,Float32}}[]
    plot[:tooltips][] && (tt = Tuple{Int,Int,Int}[])
    sites = Quantica.sites(lat)
    br = lat.bravais.matrix
    for (row, col) in itr
        iszero(dn) && row == col && continue
        rdst = padright(sites[row] + br * dn, Val(3))
        rsrc = padright(sites[col], Val(3))
        rdst = iszero(dn) ? (rdst + rsrc) / 2 : rdst
        rsrc = rsrc + plot[:siteradius][] * plot[:linkoffset][] * normalize(rdst - rsrc)
        push!(links, rsrc => rdst)
        plot[:tooltips][] && push!(tt, (row, col, n))
    end
    if !isempty(links)
        plot[:shadedlinks][] ? plotlinks_hi!(plot, links, color) : plotlinks_lo!(plot, links, color)
        plot[:tooltips][] && push!(plot[:_tooltips_rowcolhar][], tt)
    end
    return plot
end

function plotlinks_lo!(plot, links, color)
    # linesegments!(plot, links; color = darken(color, plot[:siteborderdarken][]), linewidth = 2+plot[:linkthickness][])
    linesegments!(plot, links; color = color, linewidth = plot[:linkthickness][])
    return nothing
end

function plotlinks_hi!(plot, links, color)
    positions = [(r1 + r2) / 2 for (r1, r2) in links]
    rotvectors = [r2 - r1 for (r1, r2) in links]
    radius = plot[:linkradius][]
    scales = [Vec3f0(radius, radius, norm(r2 - r1)/2) for (r1, r2) in links]
    cylinder = Cylinder(Point3f0(0., 0., -1.0), Point3f0(0., 0, 1.0), Float32(1))
    meshscatter!(plot, positions;
        color = color, marker = cylinder, markersize = scales, rotations = rotvectors,
        light = plot[:light][])
    return nothing
end

function addtooltips!(scene, h)
    sceneplot = scene[end]
    visible = Node(false)
    N = Quantica.blockdim(h)
    poprect = lift(scene.events.mouseposition) do mp
        FRect((mp .+ 5), 1,1)
    end
    textpos = lift(scene.events.mouseposition) do mp
        Vec3f0((mp .+ 5 .+ (0, -50))..., 0)
    end
    popup = poly!(campixel(scene), poprect, raw = true, color = RGBAf0(1,1,1,0), visible = visible)
    rect = popup[end]
    translate!(popup, Vec3f0(0, 0, 10000))
    text!(popup, " ", textsize = 30, position = textpos, align = (:center, :center),
        color = :black, strokewidth = 4, strokecolor = :white, raw = true, visible = visible)
    text_field = popup[end]
    on(scene.events.mouseposition) do event
        subplot, idx = mouse_selection(scene)
        layer = findfirst(isequal(subplot), sceneplot.plots)
        if layer !== nothing && idx > 0
            idx´ = fix_linesegments_bug(idx, subplot)
            txt = popuptext(sceneplot, layer, idx´, h)
            text_field[1] = txt
            visible[] = true
        else
            visible[] = false
        end
        return
    end
    return scene
end

# idx returned by mouse_selection seems wrong by a factor 2 in LineSegments subplot
fix_linesegments_bug(idx, subplot::LineSegments) = Int(idx/2) # catches odd idx
fix_linesegments_bug(idx, subplot) = idx

function popuptext(sceneplot, layer, idx, h)
    cache = sceneplot[:_tooltips_rowcolhar][]
    checkbounds(Bool, cache, layer) || return string("Bug in layer: ", layer, " of ", length(cache))
    checkbounds(Bool, cache[layer], idx) || return string("Bug in idx: ", idx, " of ", length(cache[layer]))
    (row, col_or_zero, haridx) = cache[layer][idx]
    if col_or_zero == 0
        col = iszero(col_or_zero) ? row : col_or_zero
        har = h.harmonics[1]
    else
        col = col_or_zero
        har = h.harmonics[haridx]
    end
    element = round.(har.h[row, col], digits = sceneplot[:digits][])
    txt = iszero(col_or_zero) ? matrixstring(col, element) : matrixstring(row, col, element)
    return txt
end

#######################################################################
# plot(::Bandstructure)
#######################################################################

function plot(bs::Bandstructure{1}; kw...)
    scene = bandplot2d(bs; kw...)
    axis = scene[Axis]
    axis[:names, :axisnames] = ("φ", "ε")
    return scene
end

function plot(bs::Bandstructure{2}; kw...)
    scene = bandplot3d(bs; kw...)
    axis = scene[Axis]
    to_value(scene[:show_axis]) && (axis[:names, :axisnames] = ("φ₁", "φ₂", "ε"))
    return scene
end

@recipe(BandPlot2D, bandstructure) do scene
    Theme(
    linewidth = 3,
    wireframe = true,
    colors = map(t -> RGBAf0((0.8 .* t)...),
        ((0.973, 0.565, 0.576), (0.682, 0.838, 0.922), (0.742, 0.91, 0.734),
         (0.879, 0.744, 0.894), (1.0, 0.84, 0.0), (1.0, 1.0, 0.669),
         (0.898, 0.762, 0.629), (0.992, 0.843, 0.93), (0.88, 0.88, 0.88)))
    )
end

function plot!(plot::BandPlot2D)
    bs = to_value(plot[1])
    bands = haskey(plot, :bands) ? to_value(plot[:bands]) : eachindex(bs.bands)
    colors = Iterators.cycle(plot[:colors][])
    for (nb, color) in zip(bands, colors)
        band = bs.bands[nb]
        vertices = band.mesh.vertices
        simplices = band.simplices
        linesegments!(plot, (t -> vertices[first(t)] => vertices[last(t)]).(simplices),
                      linewidth = plot[:linewidth], color = color)
    end
    return plot
 end

@recipe(BandPlot3D, bandstructure) do scene
    Theme(
    linewidth = 1,
    wireframe = false,
    colors = map(t -> RGBAf0(t...),
        ((0.973, 0.565, 0.576), (0.682, 0.838, 0.922), (0.742, 0.91, 0.734),
         (0.879, 0.744, 0.894), (1.0, 0.84, 0.0), (1.0, 1.0, 0.669),
         (0.898, 0.762, 0.629), (0.992, 0.843, 0.93), (0.88, 0.88, 0.88)))
    )
end

function plot!(plot::BandPlot3D)
    bs = to_value(plot[1])
    bands = haskey(plot, :bands) ? to_value(plot[:bands]) : eachindex(bs.bands)
    colors = Iterators.cycle(plot[:colors][])
    for (nb, color) in zip(bands, colors)
        band = bs.bands[nb]
        vertices = band.mesh.vertices
        connectivity = [s[j] for s in band.simplices, j in 1:3]
        if isempty(connectivity)
            scatter!(plot, vertices, color = color)
        else
            mesh!(plot, vertices, connectivity, color = color, transparency = false)
            if plot[:wireframe][]
                edgevertices = collect(Quantica.edgevertices(band.mesh))
                linesegments!(plot, edgevertices, linewidth = plot[:linewidth])
            end
        end
    end
    return plot
 end

function allpairs(simplex::NTuple{D,Int}, vertices) where D
    ntuple(i -> (i))
end