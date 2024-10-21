struct Text <: GraphicsShaderComponent
  data::OpenType.Text
  font::OpenTypeFont
  options::FontOptions
end

function renderables(cache::ProgramCache, text::Text, parameters::ShaderParameters, location)
  location = vec3(convert(Vec, location))
  line = only(lines(text.data, [text.font => text.options]))
  commands = Command[]
  no_clear = fill(nothing, length(parameters.color))

  # Render backgrounds first.
  for segment in line.segments
    isnothing(segment.style.background) && continue
    command = Command(cache, Gradient(), parameters, background_decoration(line, segment, location, segment.style.background))
    isempty(commands) && (parameters = @set parameters.color_clear = no_clear)
    push!(commands, command)
  end

  # Then render glyphs.
  for segment in line.segments
    isnothing(boundingelement(line, segment)) && continue
    (; r, g, b) = something(segment.style.color, RGB(1f0, 1f0, 1f0))
    color = Vec3(r, g, b)
    (; position, quads, curves) = glyph_quads(line, segment, location, color)
    qbf = QuadraticBezierFill(curves)
    command = Command(cache, qbf, parameters, quads)
    isempty(commands) && (parameters = @set parameters.color_clear = no_clear)
    push!(commands, command)
    segment.style.underline && push!(commands, Command(cache, Gradient(), parameters, underline_decoration(line, segment, location, color)))
    segment.style.strikethrough && push!(commands, Command(cache, Gradient(), parameters, strikethrough_decoration(line, segment, location, color)))
  end

  commands
end

function glyph_quads(line::Line, segment::LineSegment, origin::Vec3, color::Vec3)
  quads = Primitive{QuadraticBezierPrimitiveData,Vector{Vec2},Nothing,Vector{Vec2}}[]
  curves = Arr{3,Vec2}[]
  processed_glyphs = Dict{Int64,UnitRange{Int64}}() # to glyph range
  n = length(segment.indices)
  (; font, options) = segment
  (; size) = segment.style
  for i in segment.indices
    glyph = line.glyphs[i]
    iszero(glyph) && continue
    position = line.positions[i]
    outlines = line.outlines[glyph]
    box = boundingelement(outlines)

    range = get!(processed_glyphs, glyph) do
      start = 1 + lastindex(curves)
      append!(curves, Arr{3,Vec2}.(broadcast.(Vec2, outlines)))
      stop = lastindex(curves)
      start:stop
    end

    vertex_data = @SVector [box.bottom_left, box.bottom_right, box.top_left, box.top_right]
    geometry = Box(box.min * size, box.max * size)
    primitive_data = QuadraticBezierPrimitiveData(range, size * font.units_per_em, color)
    rect = Rectangle(geometry, vertex_data, primitive_data)
    push!(quads, Primitive(rect, vec3(position) .+ origin))
  end
  (; position, quads, curves)
end

function underline_decoration(line::Line, segment::LineSegment, origin::Point{3}, color::Vec3)
  decoration = line_decoration(line, segment, origin, color)
  offset = 200segment.style.size
  baseline = @set origin.y -= offset
  Primitive(decoration, baseline)
end

function strikethrough_decoration(line::Line, segment::LineSegment, origin::Point{3}, color::Vec3)
  decoration = line_decoration(line, segment, origin, color)
  (; ascender, descender) = segment.font.hhea
  offset = (ascender + descender) * segment.style.size / 2
  baseline = @set origin.y += offset
  Primitive(decoration, baseline)
end

function line_decoration(line::Line, segment::LineSegment, origin::Point{3}, color::Vec3)
  height = 75segment.style.size
  margin = 75segment.style.size
  box = boundingelement(line, segment)
  geometry = Box(Point2f(box.min[1] - margin/2, -height/2), Point2f(box.max[1] + margin/2, height/2))
  vertex_data = fill(color, 4)
  Rectangle(geometry, vertex_data, nothing)
end

function background_decoration(line::Line, segment::LineSegment, origin::Point{3}, color::RGBA{Float32})
  color = Vec3(color.r, color.g, color.b)
  (; ascender, descender) = segment.font.hhea
  ascender *= segment.style.size
  descender *= segment.style.size
  offset = (ascender + descender) / 2
  position = @set origin.y += offset
  height = ascender - descender
  box = boundingelement(line, segment)
  geometry = Box(Point2f(box.min[1], -height/2), Point2f(box.max[1], height/2))
  vertex_data = fill(color, 4)
  decoration = Rectangle(geometry, vertex_data, nothing)
  Primitive(decoration, position)
end

"Return the bounding box in which the text resides."
GeometryExperiments.boundingelement(text::Text) = boundingelement(text.data, [text.font => text.options])
