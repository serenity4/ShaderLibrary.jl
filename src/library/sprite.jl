struct Sprite <: Material
  texture::Texture
end
Sprite(image::Resource) = Sprite(default_texture(image))
function sprite_vert(position, uv, index, (; data)::PhysicalRef{InvocationData})
  @swizzle position.xyz = world_to_screen_coordinates(data.vertex_locations[index + 1U], data)
  uv[] = @load data.vertex_data[index + 1U]::Vec2
end

function sprite_frag(color, uv, (; data)::PhysicalRef{InvocationData}, textures)
  texture_index = @load data.user_data::DescriptorIndex
  @swizzle color.rgba = textures[texture_index](uv)
end

function Program(::Type{Sprite}, device)
  vert = @vertex device sprite_vert(::Mutable{Vec4}::Output{Position}, ::Mutable{Vec2}::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device sprite_frag(
    ::Mutable{Vec4}::Output,
    ::Vec2::Input,
    ::PhysicalRef{InvocationData}::PushConstant,
    ::Arr{2048,SPIRV.SampledImage{SPIRV.image_type(SPIRV.ImageFormatRgba16f, SPIRV.Dim2D, 0, false, false, 1)}}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_COMBINED_IMAGE_SAMPLER)})
  Program(vert, frag)
end

interface(::Sprite) = Tuple{Vector{Vec2},Nothing,Nothing}
user_data(sprite::Sprite, ctx) = instantiate(sprite.texture, ctx)
resource_dependencies(sprite::Sprite) = @resource_dependencies begin
  @read sprite.texture.resource::Texture
end
