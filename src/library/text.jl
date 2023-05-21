struct Text <: GraphicsShaderComponent
  color::Resource
  data::OpenType.Text
end

function renderables(cache::ProgramCache, text::Text, font, options, location)
  line = only(lines(text.data, [font => options]))
  segment = only(line.segments)
  (; quads, curves) = glyph_quads(line, segment, location)
  qbf = QuadraticBezierFill(text.color, curves)
  renderables(cache, qbf, quads)
end

function glyph_quads(line::Line, segment::LineSegment, pen_position)
  quads = Rectangle{Vec2,QuadraticBezierPrimitiveData,Vector{Vec2}}[]
  glyph_curves = Arr{3,Vec2}[]
  processed_glyphs = Dict{GlyphID,UnitRange{UInt32}}() # to glyph range
  n = length(segment.indices)
  (; font, options) = segment
  scale = options.font_size / font.units_per_em
  (; r, g, b) = segment.style.color
  color = (r, g, b)
  vertex_data = Vec2[(0, 0), (1, 0), (0, 1), (1, 1)]
  for i in segment.indices
    position = line.positions[i]
    origin = pen_position .+ position.origin .* scale
    pen_position = pen_position .+ position.advance .* scale
    glyph_id = line.glyphs[i]
    glyph = font[glyph_id]
    # Assume that the absence of a glyph means there is no glyph to draw.
    isnothing(glyph) && continue
    (; header) = glyph
    min = scale .* Point(header.xmin, header.ymin)
    max = scale .* Point(header.xmax, header.ymax)
    center = origin .+ (min .+ max) ./ 2
    semidiag = (max .- min) ./ 2

    range = get!(processed_glyphs, glyph_id) do
      start = lastindex(glyph_curves)
      append!(glyph_curves, Arr{3,Vec2}.(broadcast.(Vec2, curves_normalized(glyph))))
      stop = lastindex(glyph_curves) - 1
      start:stop
    end

    quad_data = QuadraticBezierPrimitiveData(range, 20options.font_size, color)
    push!(quads, Rectangle(semidiag, center, vertex_data, quad_data))
  end
  (; quads = Primitive.(quads), curves = glyph_curves)
end
