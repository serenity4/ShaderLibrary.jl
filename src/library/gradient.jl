struct Gradient <: Material end

function gradient_vert(position, color, index, (; data)::PhysicalRef{InvocationData})
  position.xyz = world_to_screen_coordinates(data.vertex_locations[index], data)
  color.rgb = @load data.vertex_data[index]::Vec3
end

function gradient_frag(color_output, color_input)
  color_output[] = color_input
end

function Program(::Type{Gradient}, device)
  vert = @vertex device gradient_vert(::Vec4::Output{Position}, ::Vec4::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device gradient_frag(::Vec4::Output, ::Vec4::Input)
  Program(vert, frag)
end

interface(::Gradient) = Tuple{Vec3,Nothing,Nothing}
