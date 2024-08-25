struct Text <: GraphicsShaderComponent
  data::OpenType.Text
  font::OpenTypeFont
  options::FontOptions
end

function renderables(cache::ProgramCache, text::Text, parameters::ShaderParameters, location)
  location = vec3(convert(Vec, location))
  line = only(lines(text.data, [text.font => text.options]))
  commands = Command[]
  px = pixel_size(parameters)F
  no_clear = fill(nothing, length(parameters.color))
  for segment in line.segments
    isnothing(boundingelement(line, segment)) && continue
    (; r, g, b) = something(segment.style.color, RGB(1f0, 1f0, 1f0))
    color = Vec3(r, g, b)
    (; position, quads, curves) = glyph_quads(line, segment, location, color, px)
    qbf = QuadraticBezierFill(curves)
    command = Command(cache, qbf, parameters, quads)
    isempty(commands) && (parameters = @set parameters.color_clear = no_clear)
    push!(commands, command)
    !segment.style.underline && !segment.style.strikethrough && continue
    segment.style.underline && push!(commands, Command(cache, Gradient(), parameters, underline_decoration(line, segment, location, color, px)))
    segment.style.strikethrough && push!(commands, Command(cache, Gradient(), parameters, strikethrough_decoration(line, segment, location, color, px)))
  end
  commands
end

function glyph_quads(line::Line, segment::LineSegment, origin::Vec3, color::Vec3, px)
  quads = Primitive{QuadraticBezierPrimitiveData,Vector{Vec2},Nothing,Vector{Vec2}}[]
  curves = Arr{3,Vec2}[]
  processed_glyphs = Dict{Int64,UnitRange{Int64}}() # to glyph range
  n = length(segment.indices)
  (; font, options) = segment
  (; size) = segment.style
  for i in segment.indices
    glyph = line.glyphs[i]
    iszero(glyph) && continue
    position = line.positions[i] .* px
    outlines = line.outlines[glyph] .* size
    box = boundingelement(outlines)

    range = get!(processed_glyphs, glyph) do
      start = 1 + lastindex(curves)
      append!(curves, Arr{3,Vec2}.(broadcast.(Vec2, outlines)))
      stop = lastindex(curves)
      start:stop
    end

    vertex_data = @SVector [box.bottom_left, box.bottom_right, box.top_left, box.top_right]
    geometry = Box(box.min .* px, box.max .* px)
    primitive_data = QuadraticBezierPrimitiveData(range, size * font.units_per_em, color)
    rect = Rectangle(geometry, vertex_data, primitive_data)
    push!(quads, Primitive(rect, vec3(position) .+ origin))
  end
  (; position, quads, curves)
end

function underline_decoration(line::Line, segment::LineSegment, origin::Point{3}, color::Vec3, px)
  decoration = line_decoration(line, segment, origin, color, px)
  offset = 200segment.style.size * px
  baseline = @set origin.y -= offset
  Primitive(decoration, baseline)
end

function strikethrough_decoration(line::Line, segment::LineSegment, origin::Point{3}, color::Vec3, px)
  decoration = line_decoration(line, segment, origin, color, px)
  (; ascender, descender) = segment.font.hhea
  offset = (ascender + descender) * segment.style.size * px / 2
  baseline = @set origin.y += offset
  Primitive(decoration, baseline)
end

function line_decoration(line::Line, segment::LineSegment, origin::Point{3}, color::Vec3, px)
  height = 75segment.style.size * px
  margin = 75segment.style.size * px
  box = boundingelement(line, segment)
  geometry = Box(Point2f(box.min[1] * px - margin/2, -height/2), Point2f(box.max[1] * px + margin/2, height/2))
  vertex_data = fill(color, 4)
  Rectangle(geometry, vertex_data, nothing)
end

"Return the bounding box in which `text` resides, in pixels."
GeometryExperiments.boundingelement(text::Text) = boundingelement(text.data, [text.font => text.options])
"Return the bounding box in which `text` resides, in normalized coordinates."
function GeometryExperiments.boundingelement(text::Text, resolution)
  box = boundingelement(text.data, [text.font => text.options])
  scale = pixel_size(resolution)
  Box(box.min .* scale, box.max .* scale)
end
