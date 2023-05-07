struct PosColor
  pos::Vec2
  color::Vec3
end

struct Gradient <: ShaderComponent
  color::Resource
end

function gradient_vert(frag_color, position, index, data_address::DeviceAddressBlock)
  data = @load data_address::InvocationData
  (; pos, color) = @load data.vertex_data[index]::PosColor
  position[] = Vec4(pos.x, pos.y, 0F, 1F)
  frag_color.rgb = color
  frag_color.a = 1F
end

function gradient_frag(color, frag_color)
  color[] = frag_color
end

function Program(::Gradient, device)
  vert = @vertex device gradient_vert(::Vec4::Output, ::Vec4::Output{Position}, ::UInt32::Input{VertexIndex}, ::DeviceAddressBlock::PushConstant)
  frag = @fragment device gradient_frag(::Vec4::Output, ::Vec4::Input)
  Program(vert, frag)
end

interface(::Gradient) = Tuple{PosColor,Nothing,Nothing,Nothing}
