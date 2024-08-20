struct Text <: GraphicsShaderComponent
  data::OpenType.Text
  font::OpenTypeFont
  options::FontOptions
end

function renderables(cache::ProgramCache, text::Text, parameters::ShaderParameters, location)
  location = vec3(convert(Vec, location))
  line = only(lines(text.data, [text.font => text.options]))
  segment = only(line.segments)
  (; quads, curves) = glyph_quads(line, segment, location, pixel_size(parameters)F)
  qbf = QuadraticBezierFill(curves)
  renderables(cache, qbf, parameters, quads)
end

function glyph_quads(line::Line, segment::LineSegment, origin::Point{3}, pixel_size)
  quads = Primitive{QuadraticBezierPrimitiveData,Vector{Vec2},Nothing,Vector{Vec2}}[]
  curves = Arr{3,Vec2}[]
  processed_glyphs = Dict{Int64,UnitRange{Int64}}() # to glyph range
  n = length(segment.indices)
  (; font, options) = segment
  (; r, g, b) = something(segment.style.color, RGB(1f0, 1f0, 1f0))
  color = (r, g, b)
  for i in segment.indices
    glyph = line.glyphs[i]
    iszero(glyph) && continue
    position = vec3(line.positions[i] .* pixel_size)
    outlines = line.outlines[glyph]
    box = boundingelement(outlines)

    range = get!(processed_glyphs, glyph) do
      start = 1 + lastindex(curves)
      append!(curves, Arr{3,Vec2}.(broadcast.(Vec2, outlines)))
      stop = lastindex(curves)
      start:stop
    end

    vertex_data = @SVector [box.bottom_left, box.bottom_right, box.top_left, box.top_right]
    geometry = Box(box.min .* pixel_size, box.max .* pixel_size)
    primitive_data = QuadraticBezierPrimitiveData(range, options.font_size.value, color)
    rect = Rectangle(geometry, vertex_data, primitive_data)
    push!(quads, Primitive(rect, position .+ origin))
  end
  (; quads, curves)
end

"Return the bounding box in which `text` resides, in pixels."
GeometryExperiments.boundingelement(text::Text) = boundingelement(text.data, [text.font => text.options])
"Return the bounding box in which `text` resides, in normalized coordinates."
function GeometryExperiments.boundingelement(text::Text, resolution)
  box = boundingelement(text.data, [text.font => text.options])
  scale = pixel_size(resolution)
  Box(box.min .* scale, box.max .* scale)
end
