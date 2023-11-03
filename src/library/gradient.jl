struct Gradient <: Material end

function gradient_vert(frag_color, position, index, data_address::DeviceAddressBlock)
  data = @load data_address::InvocationData
  pos = @load data.vertex_locations[index]::Vec3
  pos = project(pos, data.camera)
  pos.xy = device_coordinates(pos.xy, data.aspect_ratio)
  color = @load data.vertex_data[index]::Vec3
  position[] = Vec4(pos.x, pos.y, pos.z, 1F)
  frag_color.rgb = color
  frag_color.a = 1F
end

function gradient_frag(color, frag_color)
  color[] = frag_color
end

function Program(::Type{Gradient}, device)
  vert = @vertex device gradient_vert(::Vec4::Output, ::Vec4::Output{Position}, ::UInt32::Input{VertexIndex}, ::DeviceAddressBlock::PushConstant)
  frag = @fragment device gradient_frag(::Vec4::Output, ::Vec4::Input)
  Program(vert, frag)
end

interface(::Gradient) = Tuple{Vec3,Nothing,Nothing}
