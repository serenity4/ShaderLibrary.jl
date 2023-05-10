struct GaussianBlur <: ShaderComponent
  color::Resource
  texture::Texture
  σ::Float32
end
GaussianBlur(color, image::Resource, σ = 0.01) = GaussianBlur(color, default_texture(image), σ)

function gaussian_1d(t, σ)
  exp(-t^2 / 2σ^2) / sqrt(2 * (π)F * σ^2)
end
gaussian_2d((x, y), σ) = gaussian_1d(x, σ) * gaussian_1d(y, σ)

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
  σ, texture_index = @load data.user_data::Tuple{Float32, DescriptorIndex}
  reference = textures[texture_index]
  out_color.rgb = gaussian_blur(σ, reference, uv)
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

user_data(blur::GaussianBlur, ctx) = (blur.σ, DescriptorIndex(texture_descriptor(blur.texture), ctx))
resource_dependencies(blur::GaussianBlur) = @resource_dependencies begin
  @read blur.texture.image::Texture
  @write (blur.color => CLEAR_VALUE)::Color
end
interface(::GaussianBlur) = Tuple{Vec2,Nothing,Nothing}
