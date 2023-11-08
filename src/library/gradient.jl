struct Gradient <: Material end

function gradient_vert(frag_color, position, index, (; data)::PhysicalRef{InvocationData})
  position.xyz = world_to_screen_coordinates(data.vertex_locations[index], data)
  frag_color.rgb = @load data.vertex_data[index]::Vec3
end

function gradient_frag(color, frag_color)
  color[] = frag_color
end

function Program(::Type{Gradient}, device)
  vert = @vertex device gradient_vert(::Vec4::Output, ::Vec4::Output{Position}, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device gradient_frag(::Vec4::Output, ::Vec4::Input)
  Program(vert, frag)
end

interface(::Gradient) = Tuple{Vec3,Nothing,Nothing}
