# Uses the technique from GPU-Centered Font Rendering Directly from Glyph Outlines, E. Lengyel, 2017.
# Note: this technique is patented in the US until 2038: https://patents.google.com/patent/US10373352B1/en.

function intensity(bezier, font_size)
  ((x₁, y₁), (x₂, y₂), (x₃, y₃)) = bezier.points
  T = typeof(x₁)
  res = zero(T)

  # Cast a ray in the X direction.
  code = classify_bezier_curve((y₁, y₂, y₃))
  if !iszero(code)
    (t₁, t₂) = compute_roots(y₁ - 2y₂ + y₃, y₁ - y₂, y₁; atol = 0.0001F * max(abs(y₁), abs(y₃)))
    if !isnan(t₁)
      code & 0x0001 == 0x0001 && (res += winding_contribution(font_size, first(bezier(t₁))))
      code > 0x0001 && (res -= winding_contribution(font_size, first(bezier(t₂))))
    end
  end

  # Cast a ray in the Y direction.
  code = classify_bezier_curve((x₁, x₂, x₃))
  if !iszero(code)
    (t₁, t₂) = compute_roots(x₁ - 2x₂ + x₃, x₁ - x₂, x₁; atol = 0.0001F * max(abs(x₁), abs(x₃)))
    if !isnan(t₁)
      code & 0x0001 == 0x0001 && (res -= winding_contribution(font_size, last(bezier(t₁))))
      code > 0x0001 && (res += winding_contribution(font_size, last(bezier(t₂))))
    end
  end

  res
end

# `font_size` is the number of pixels in one em.
winding_contribution(font_size, value) = clamp(0.5F + font_size * value, 0F, 1F)

function classify_bezier_curve(points)
  (x₁, x₂, x₃) = points
  rshift = ifelse(x₁ > zero(x₁), 1U << 1, 0U) + ifelse(x₂ > zero(x₂), 1U << 2, 0U) + ifelse(x₃ > zero(x₃), 1U << 3, 0U)
  (0x2e74 >> rshift) & 0x0003
end

function intensity(position, curves, font_size)
  coverage = 0F
  for curve in curves
    curve = BezierCurve(curve .- Ref(position))
    coverage += intensity(curve, font_size)
  end
  coverage = abs(coverage)
  coverage *= 0.5F # average ray contributions from both directions.
  clamp(coverage, 0F, 1F)
end

struct QuadraticBezierFill <: Material
  curves::Vector{Arr{3,Vec2}}
end

struct QuadraticBezierPrimitiveData
  range::UnitRange{UInt32}
  font_size::Float32
  color::Vec4
end

function quadratic_bezier_fill_vert(position, grid_position, frag_primitive_index, index, (; data)::PhysicalRef{InvocationData})
  @swizzle position.xyz = world_to_screen_coordinates(data.vertex_locations[index + 1U], data)
  grid_position[] = @load data.vertex_data[index + 1U]::Vec2
  @swizzle frag_primitive_index.x = @load data.primitive_indices[index + 1U]::UInt32
end

function quadratic_bezier_fill_frag(out_color, grid_position, primitive_index, (; data)::PhysicalRef{InvocationData})
  (; color, range, font_size) = @load data.primitive_data[primitive_index.x]::QuadraticBezierPrimitiveData
  curves_start = DeviceAddress(UInt64(data.user_data) + sizeof(Arr{3,Vec2})U*(range[1U] - 1U))
  curves = PhysicalBuffer{Arr{3,Vec2}}(length(range), curves_start)
  @swizzle out_color.rgb = @swizzle color.rgb
  @swizzle out_color.a = intensity(grid_position, curves, font_size) * @swizzle color.a
end

function Program(::Type{QuadraticBezierFill}, device)
  vert = @vertex device quadratic_bezier_fill_vert(::Mutable{Vec4}::Output{Position}, ::Mutable{Vec2}::Output, ::Mutable{Vec2U}::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device quadratic_bezier_fill_frag(::Mutable{Vec4}::Output, ::Vec2::Input, ::Vec2U::Input{@Flat}, ::PhysicalRef{InvocationData}::PushConstant)
  Program(vert, frag)
end

interface(::QuadraticBezierFill) = Tuple{Vector{Vec2},QuadraticBezierPrimitiveData,Nothing}
user_data(qbf::QuadraticBezierFill, ctx) = qbf.curves
