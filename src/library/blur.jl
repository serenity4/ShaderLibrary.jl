const BLUR_HORIZONTAL = 0
const BLUR_VERTICAL = 1

struct GaussianBlurDirectional <: ShaderComponent
  color::Resource
  texture::Texture
  direction::UInt32
  size::Float32
end
GaussianBlurDirectional(color, image::Resource, direction, size = 0.01) = GaussianBlurDirectional(color, default_texture(image), direction, size)

gaussian_1d(t, size) = exp(-t^2 / 2size^2) / sqrt(2 * (π)F * size^2)

function gaussian_blur_directional(reference, uv, direction, size)
  res = zero(Vec3)
  imsize = Base.size(SPIRV.Image(reference), 0U)
  pixel_size = 1F ./ imsize # size of one pixel in UV coordinates.
  rx, ry = Int32.(min.(ceil.(3size .* imsize), imsize))
  if direction == BLUR_HORIZONTAL
    for i in -rx:rx
      uv_offset = Vec2(i * pixel_size[1], 0)
      weight = gaussian_1d(uv_offset.x, size) * pixel_size[1]
      sampled = reference(uv + uv_offset)
      color = sampled.rgb
      res .+= color * weight
    end
  else
    for j in -ry:ry
      uv_offset = Vec2(0, j * pixel_size[2])
      weight = gaussian_1d(uv_offset.y, size) * pixel_size[2]
      sampled = reference(uv + uv_offset)
      color = sampled.rgb
      res .+= color * weight
    end
  end
  res
end

function gaussian_blur_directional_frag(out_color, uv, data_address, textures)
  data = @load data_address::InvocationData
  direction, size, texture_index = @load data.user_data::Tuple{UInt32, Float32, DescriptorIndex}
  reference = textures[texture_index]
  out_color.rgb = gaussian_blur_directional(reference, uv, direction, size)
  out_color.a = 1F + 0F
end

function Program(blur::GaussianBlurDirectional, device)
  vert = @vertex device sprite_vert(::Vec2::Output, ::Vec4::Output{Position}, ::UInt32::Input{VertexIndex}, ::DeviceAddressBlock::PushConstant)
  frag = @fragment device gaussian_blur_directional_frag(
    ::Vec4::Output,
    ::Vec2::Input,
    ::DeviceAddressBlock::PushConstant,
    ::Arr{2048,SPIRV.SampledImage{image_type(SPIRV.ImageFormatRgba16f, SPIRV.Dim2D, 0, false, false, 1)}}::UniformConstant{@DescriptorSet(0), @Binding(3)})
  Program(vert, frag)
end

user_data(blur::GaussianBlurDirectional, ctx) = (blur.direction, blur.size, DescriptorIndex(texture_descriptor(blur.texture), ctx))
resource_dependencies(blur::GaussianBlurDirectional) = @resource_dependencies begin
  @read blur.texture.image::Texture
  @write (blur.color => CLEAR_VALUE)::Color
end
interface(::GaussianBlurDirectional) = Tuple{Vec2,Nothing,Nothing}

struct GaussianBlur <: ShaderComponent
  color::Resource
  texture::Texture
  size::Float32
end
GaussianBlur(color, image::Resource, size = 0.01) = GaussianBlur(color, default_texture(image), size)

gaussian_2d((x, y), size) = gaussian_1d(x, size) * gaussian_1d(y, size)

"""
Naive but slow implementation, with quadratic complexity in the size of the image.

A natural improvement would make use of the fact that `gaussian_2d((x, y), size) = gaussian_1d(x, size) * gaussian_1d(y, size)`
only needs N + M gaussian kernel evaluations instead of N*M evaluations as done currently.
"""
function gaussian_blur(σ, reference, uv)
  res = zero(Vec3)
  imsize = size(SPIRV.Image(reference), 0U)
  pixel_size = 1F ./ imsize # size of one pixel in UV coordinates.
  rx, ry = Int32.(min.(ceil.(3σ .* imsize), imsize))
  for i in -rx:rx
    for j in -ry:ry
      uv_offset = Vec2(i, j) .* pixel_size
      weight = gaussian_2d(uv_offset, σ) * 0.5(pixel_size[1]^2 + pixel_size[2]^2)
      sampled = reference(uv + uv_offset)
      color = sampled.rgb
      res .+= color * weight
    end
  end
  res
end

function blur_frag(out_color, uv, data_address, textures)
  data = @load data_address::InvocationData
  size, texture_index = @load data.user_data::Tuple{Float32, DescriptorIndex}
  reference = textures[texture_index]
  out_color.rgb = gaussian_blur(size, reference, uv)
  out_color.a = 1F
end

function Program(blur::GaussianBlur, device)
  vert = @vertex device sprite_vert(::Vec2::Output, ::Vec4::Output{Position}, ::UInt32::Input{VertexIndex}, ::DeviceAddressBlock::PushConstant)
  frag = @fragment device blur_frag(
    ::Vec4::Output,
    ::Vec2::Input,
    ::DeviceAddressBlock::PushConstant,
    ::Arr{2048,SPIRV.SampledImage{image_type(SPIRV.ImageFormatRgba16f, SPIRV.Dim2D, 0, false, false, 1)}}::UniformConstant{@DescriptorSet(0), @Binding(3)})
  Program(vert, frag)
end

user_data(blur::GaussianBlur, ctx) = (blur.size, DescriptorIndex(texture_descriptor(blur.texture), ctx))
resource_dependencies(blur::GaussianBlur) = @resource_dependencies begin
  @read blur.texture.image::Texture
  @write (blur.color => CLEAR_VALUE)::Color
end
interface(::GaussianBlur) = Tuple{Vec2,Nothing,Nothing}
