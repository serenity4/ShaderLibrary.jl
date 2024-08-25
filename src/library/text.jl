struct Text <: GraphicsShaderComponent
  data::OpenType.Text
  font::OpenTypeFont
  options::FontOptions
end

function renderables(cache::ProgramCache, text::Text, parameters::ShaderParameters, location)
  location = vec3(convert(Vec, location))
  line = only(lines(text.data, [text.font => text.options]))
  nodes = RenderNode[]
  px = pixel_size(parameters)F
  no_clear = fill(nothing, length(parameters.color))
  for segment in line.segments
    isnothing(boundingelement(line, segment)) && continue
    (; r, g, b) = something(segment.style.color, RGB(1f0, 1f0, 1f0))
    color = Vec3(r, g, b)
    (; quads, curves) = glyph_quads(line, segment, location, color, px)
    qbf = QuadraticBezierFill(curves)
    command = Command(cache, qbf, parameters, quads)
    isempty(nodes) && (parameters = @set parameters.color_clear = no_clear)
    push!(nodes, command)
    !segment.style.underline && !segment.style.strikethrough && continue
    segment.style.underline && push!(nodes, Command(cache, Gradient(), parameters, underline_decoration(line, segment, location, color, px)))
    segment.style.strikethrough && push!(nodes, Command(cache, Gradient(), parameters, strikethrough_decoration(line, segment, location, color, px)))
  end
  nodes
end

function glyph_quads(line::Line, segment::LineSegment, origin::Point{3}, color::Vec3, px)
  quads = Primitive{QuadraticBezierPrimitiveData,Vector{Vec2},Nothing,Vector{Vec2}}[]
  curves = Arr{3,Vec2}[]
  processed_glyphs = Dict{Int64,UnitRange{Int64}}() # to glyph range
  n = length(segment.indices)
  (; font, options) = segment
  for i in segment.indices
    glyph = line.glyphs[i]
    iszero(glyph) && continue
    position = vec3(line.positions[i] .* px)
    outlines = line.outlines[glyph]
    box = boundingelement(outlines)

    range = get!(processed_glyphs, glyph) do
      start = 1 + lastindex(curves)
      append!(curves, Arr{3,Vec2}.(broadcast.(Vec2, outlines)))
      stop = lastindex(curves)
      start:stop
    end

    vertex_data = @SVector [box.bottom_left, box.bottom_right, box.top_left, box.top_right]
    geometry = Box(box.min .* px, box.max .* px)
    primitive_data = QuadraticBezierPrimitiveData(range, options.font_size.value, color)
    rect = Rectangle(geometry, vertex_data, primitive_data)
    push!(quads, Primitive(rect, position .+ origin))
  end
  (; quads, curves)
end

function underline_decoration(line::Line, segment::LineSegment, origin::Point{3}, color::Vec3, px)
  decoration = line_decoration(line, segment, origin, color, px)
  baseline = origin .- (0F, 8px, 0F)
  Primitive(decoration, baseline)
end

function strikethrough_decoration(line::Line, segment::LineSegment, origin::Point{3}, color::Vec3, px)
  decoration = line_decoration(line, segment, origin, color, px)
  (; ascender, descender) = segment.font.hhea
  scale = segment.options.font_size.value / segment.font.units_per_em
  y = (ascender + descender) / 2 * scale * px
  baseline = origin .+ (0F, y, 0F)
  Primitive(decoration, baseline)
end

function line_decoration(line::Line, segment::LineSegment, origin::Point{3}, color::Vec3, px)
  height = 3px
  margin = 3px
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
