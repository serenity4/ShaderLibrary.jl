# Uses the technique from GPU-Centered Font Rendering Directly from Glyph Outlines, E. Lengyel, 2017.
# Note: this technique is patented in the US until 2038: https://patents.google.com/patent/US10373352B1/en.

function intensity(bezier, pixel_per_em)
  ((x₁, y₁), (x₂, y₂), (x₃, y₃)) = bezier.points
  T = typeof(x₁)
  res = zero(T)

  # Cast a ray in the X direction.
  code = classify_bezier_curve((y₁, y₂, y₃))
  if !iszero(code)
    (t₁, t₂) = compute_roots(y₁ - 2y₂ + y₃, y₁ - y₂, y₁)
    if !isnan(t₁)
      code & 0x0001 == 0x0001 && (res += winding_contribution(pixel_per_em, first(bezier(t₁))))
      code > 0x0001 && (res -= winding_contribution(pixel_per_em, first(bezier(t₂))))
    end
  end

  # Cast a ray in the Y direction.
  code = classify_bezier_curve((x₁, x₂, x₃))
  if !iszero(code)
    (t₁, t₂) = compute_roots(x₁ - 2x₂ + x₃, x₁ - x₂, x₁)
    if !isnan(t₁)
      code & 0x0001 == 0x0001 && (res -= winding_contribution(pixel_per_em, last(bezier(t₁))))
      code > 0x0001 && (res += winding_contribution(pixel_per_em, last(bezier(t₂))))
    end
  end

  res
end

winding_contribution(pixel_per_em, value) = clamp(0.5F + pixel_per_em * value, 0F, 1F)

function classify_bezier_curve(points)
  (x₁, x₂, x₃) = points
  rshift = ifelse(x₁ > 0, 1 << 1, 0) + ifelse(x₂ > 0, 1 << 2, 0) + ifelse(x₃ > 0, 1 << 3, 0)
  (0x2e74 >> rshift) & 0x0003
end

function intensity(position, curves, range, pixel_per_em)
  res = 0F
  for curve in curves
    curve = BezierCurve(curve .- Ref(position))
    res += intensity(curve, pixel_per_em)
  end
  sqrt(abs(res))
end

struct QuadraticBezierFill <: Material
  curves::Vector{Arr{3,Vec2}}
end

struct QuadraticBezierPrimitiveData
  range::UnitRange{UInt32}
  sharpness::Float32
  color::Vec3
end

function quadratic_bezier_fill_vert(position, frag_coordinates, frag_primitive_index::Vec{2,UInt32}, index, (; data)::PhysicalRef{InvocationData})
  position.xyz = world_to_screen_coordinates(data.vertex_locations[index + 1U], data)
  frag_coordinates[] = @load data.vertex_data[index + 1U]::Vec2
  frag_primitive_index.x = @load data.primitive_indices[index + 1U]::UInt32
end

function quadratic_bezier_fill_frag(out_color, coordinates, primitive_index, (; data)::PhysicalRef{InvocationData})
  (; color, range, sharpness) = @load data.primitive_data[primitive_index.x]::QuadraticBezierPrimitiveData
  curves_start = DeviceAddress(UInt64(data.user_data) + 24*(first(range) - 1U))
  curves = PhysicalBuffer{Arr{3,Vec2}}(length(range), curves_start)
  out_color.rgb = color
  out_color.a = clamp(intensity(coordinates, curves, range, 10sharpness), 0F, 1F)
end

function Program(::Type{QuadraticBezierFill}, device)
  vert = @vertex device quadratic_bezier_fill_vert(::Vec4::Output{Position}, ::Vec2::Output, ::Vec{2,UInt32}::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device quadratic_bezier_fill_frag(::Vec4::Output, ::Vec2::Input, ::Vec{2,UInt32}::Input{@Flat}, ::PhysicalRef{InvocationData}::PushConstant)
  Program(vert, frag)
end

interface(::QuadraticBezierFill) = Tuple{Vector{Vec2},QuadraticBezierPrimitiveData,Nothing}
user_data(qbf::QuadraticBezierFill, ctx) = qbf.curves
