struct Sprite <: Material
  texture::Texture
end
Sprite(image::Resource) = Sprite(default_texture(image))
function sprite_vert(uv, position, index, (; data)::PhysicalRef{InvocationData})
  position.xyz = world_to_screen_coordinates(data.vertex_locations[index], data)
  uv[] = @load data.vertex_data[index]::Vec2
end

function sprite_frag(out_color, uv, (; data)::PhysicalRef{InvocationData}, textures)
  texture_index = @load data.user_data::DescriptorIndex
  out_color.rgb = textures[texture_index](uv)
  out_color.a = 1F
end

function Program(::Type{Sprite}, device)
  vert = @vertex device sprite_vert(::Vec2::Output, ::Vec4::Output{Position}, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device sprite_frag(
    ::Vec4::Output,
    ::Vec2::Input,
    ::PhysicalRef{InvocationData}::PushConstant,
    ::Arr{2048,SPIRV.SampledImage{SPIRV.image_type(SPIRV.ImageFormatRgba16f, SPIRV.Dim2D, 0, false, false, 1)}}::UniformConstant{@DescriptorSet(0), @Binding(3)})
  Program(vert, frag)
end

interface(::Sprite) = Tuple{Vec2,Nothing,Nothing}
user_data(sprite::Sprite, ctx) = DescriptorIndex(texture_descriptor(sprite.texture), ctx)
resource_dependencies(sprite::Sprite) = @resource_dependencies begin
  @read sprite.texture.image::Texture
end
