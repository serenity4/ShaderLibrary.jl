struct Text <: GraphicsShaderComponent
  data::OpenType.Text
  font::OpenTypeFont
  options::FontOptions
end

function renderables(cache::ProgramCache, text::Text, parameters::ShaderParameters, location)
  location = point3(convert(Point, location))
  line = only(lines(text.data, [text.font => text.options]))
  segment = only(line.segments)
  (; quads, curves) = glyph_quads(line, segment, location)
  qbf = QuadraticBezierFill(curves)
  renderables(cache, qbf, parameters, quads)
end

function glyph_quads(line::Line, segment::LineSegment, origin::Point{3})
  quads = Primitive{QuadraticBezierPrimitiveData,Vector{Vec2},Nothing,Vector{Vec2}}[]
  curves = Arr{3,Vec2}[]
  processed_glyphs = Dict{Int64,UnitRange{Int64}}() # to glyph range
  n = length(segment.indices)
  (; font, options) = segment
  (; r, g, b) = something(segment.style.color, RGB(1f0, 1f0, 1f0))
  color = (r, g, b)
  vertex_data = Vec2[(0, 0), (1, 0), (0, 1), (1, 1)]
  for i in segment.indices
    glyph = line.glyphs[i]
    iszero(glyph) && continue
    position = point3(line.positions[i])
    outlines = line.outlines[glyph]
    box = boundingelement(outlines)

    range = get!(processed_glyphs, glyph) do
      start = 1 + lastindex(curves)
      # TODO: Try to make `QuadraticBezierFill` work without such remapping.
      transf = BoxTransform(box, Box(Point2(0, 0), Point2(1, 1)))
      append!(curves, Arr{3,Vec2}.(broadcast.(Vec2 ∘ transf, outlines)))
      stop = lastindex(curves)
      start:stop
    end

    quad_data = QuadraticBezierPrimitiveData(range, 20options.font_size.value, color)
    rect = Rectangle(box, vertex_data, quad_data)
    push!(quads, Primitive(rect, position + origin))
  end
  (; quads, curves)
end

GeometryExperiments.boundingelement(text::Text) = boundingelement(text.data, [text.font => text.options])
