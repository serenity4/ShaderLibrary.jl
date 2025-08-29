struct Text <: GraphicsShaderComponent
  parsed::ParsedText
end

Text(text::OpenType.Text, font::OpenTypeFont, options::OpenType.FontOptions) = Text(text, [font => options])

function Text(text::OpenType.Text, fonts)
  parsed = ParsedText(text, fonts)
  Text(parsed)
end

function renderables(cache::ProgramCache, text::Text, parameters::ShaderParameters, location)
  (; parsed) = text
  location = vec3(convert(Vec, location))
  isempty(parsed.lines) && return Command[]
  background_renders = Command[]
  text_renders = Command[]
  # Disable any clears; we have multiple draws so it's probably best for the user to decide when/what to clear.
  @reset parameters.color_clear = []
  @reset parameters.depth_clear = nothing
  @reset parameters.stencil_clear = nothing
  for (line, spacing) in zip(parsed.lines, parsed.spacings)
    @reset location.y += Float32(-spacing)
    render_glyph_backgrounds!(background_renders, line, location, cache, parameters)
    render_glyphs!(text_renders, line, location, cache, parameters)
  end
  isempty(background_renders) && return text_renders
  [background_renders, text_renders]
end

function render_glyph_backgrounds!(background_renders, line::Line, location, cache::ProgramCache, parameters::ShaderParameters)
  for segment in line.segments
    isnothing(segment.style.background) && continue
    (; r, g, b, alpha) = something(segment.style.background, RGBA(1f0, 1f0, 1f0, 1f0))
    color = Vec4(r, g, b, alpha)
    command = Command(cache, Gradient{Vec4}(), parameters, background_decoration(line, segment, location, color))
    push!(background_renders, command)
  end
end

function render_glyphs!(text_renders, line::Line, location, cache::ProgramCache, parameters::ShaderParameters)
  for segment in line.segments
    has_outlines(line, segment) || continue
    (; r, g, b, alpha) = something(segment.style.color, RGBA(1f0, 1f0, 1f0, 1f0))
    color = Vec4(r, g, b, alpha)
    (; position, quads, curves) = glyph_quads(line, segment, location, color)
    qbf = QuadraticBezierFill(curves)
    command = Command(cache, qbf, parameters, quads)
    push!(text_renders, command)
    segment.style.underline && push!(text_renders, Command(cache, Gradient{Vec4}(), parameters, underline_decoration(line, segment, location, color)))
    segment.style.strikethrough && push!(text_renders, Command(cache, Gradient{Vec4}(), parameters, strikethrough_decoration(line, segment, location, color)))
  end
end

function glyph_quads(line::Line, segment::LineSegment, origin::Vec3, color::Vec4)
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

function underline_decoration(line::Line, segment::LineSegment, origin::Point{3}, color::Vec4)
  decoration = linear_decoration(line, segment, origin, color)
  offset = 200segment.style.size
  baseline = @set origin.y -= offset
  Primitive(decoration, baseline)
end

function strikethrough_decoration(line::Line, segment::LineSegment, origin::Point{3}, color::Vec4)
  decoration = linear_decoration(line, segment, origin, color)
  offset = (ascender(segment) + descender(segment)) / 2
  line_center = @set origin.y += offset
  Primitive(decoration, line_center)
end

function linear_decoration(line::Line, segment::LineSegment, origin::Point{3}, color::Vec4)
  height = 75segment.style.size
  margin = 75segment.style.size
  box = segment_geometry(line, segment)
  geometry = Box(Point2f(box.min[1] - margin/2, -height/2), Point2f(box.max[1] + margin/2, height/2))
  vertex_data = fill(color, 4)
  Rectangle(geometry, vertex_data, nothing)
end

function background_decoration(line::Line, segment::LineSegment, origin::Point{3}, color::Vec4)
  geometry = segment_geometry(line, segment)
  vertex_data = fill(color, 4)
  decoration = Rectangle(geometry, vertex_data, nothing)
  Primitive(decoration, origin)
end
