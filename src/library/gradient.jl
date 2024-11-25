struct Gradient{T} <: Material end

Gradient() = Gradient{Vec3}()

function gradient_vert(position, color, index, (; data)::PhysicalRef{InvocationData}, ::Type{T}) where {T}
  @swizzle position.xyz = world_to_screen_coordinates(data.vertex_locations[index + 1U], data)
  color[] = vec4(@load data.vertex_data[index + 1U]::T)
end

function gradient_frag(color_output, color_input)
  color_output[] = color_input
end

function Program(::Type{Gradient{T}}, device) where {T}
  vert = @vertex device gradient_vert(::Mutable{Vec4}::Output{Position}, ::Mutable{Vec4}::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant, ::Type{T})
  frag = @fragment device gradient_frag(::Mutable{Vec4}::Output, ::Vec4::Input)
  Program(vert, frag)
end

interface(::Gradient{T}) where {T} = Tuple{Vector{T},Nothing,Nothing}
