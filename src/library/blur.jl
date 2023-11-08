const BLUR_HORIZONTAL = 0
const BLUR_VERTICAL = 1

struct GaussianBlurDirectional <: GraphicsShaderComponent
  texture::Texture
  direction::UInt32
  size::Float32
end
GaussianBlurDirectional(image::Resource, direction, size = 0.01) = GaussianBlurDirectional(default_texture(image), direction, size)

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

function gaussian_blur_directional_frag(color, uv, (; data)::PhysicalRef{InvocationData}, textures)
  direction, size, texture_index = @load data.user_data::Tuple{UInt32, Float32, DescriptorIndex}
  reference = textures[texture_index]
  color.rgb = gaussian_blur_directional(reference, uv, direction, size)
  color.a = 1F
end

function Program(::Type{GaussianBlurDirectional}, device)
  vert = @vertex device sprite_vert(::Vec4::Output{Position}, ::Vec2::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device gaussian_blur_directional_frag(
    ::Vec4::Output,
    ::Vec2::Input,
    ::PhysicalRef{InvocationData}::PushConstant,
    ::Arr{2048,SPIRV.SampledImage{image_type(SPIRV.ImageFormatRgba16f, SPIRV.Dim2D, 0, false, false, 1)}}::UniformConstant{@DescriptorSet(0), @Binding(3)})
  Program(vert, frag)
end

user_data(blur::GaussianBlurDirectional, ctx) = (blur.direction, blur.size, DescriptorIndex(texture_descriptor(blur.texture), ctx))
resource_dependencies(blur::GaussianBlurDirectional) = @resource_dependencies begin
  @read blur.texture.image::Texture
end
interface(::GaussianBlurDirectional) = Tuple{Vec2,Nothing,Nothing}

struct GaussianBlur <: GraphicsShaderComponent
  texture::Texture
  size::Float32
end
GaussianBlur(image::Resource, size = 0.01) = GaussianBlur(default_texture(image), size)

function renderables(cache::ProgramCache, blur::GaussianBlur, parameters::ShaderParameters, geometry)
  color = parameters.color[1]
  transient_color = similar(color; blur.texture.image.image.dims, usage_flags = Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT, name = :transient_color)

  # First, blur the whole texture once, then blur only the relevant portion.
  blur_x = GaussianBlurDirectional(blur.texture, BLUR_HORIZONTAL, blur.size)
  uvs = Vec2.([0.5 * (1 .+ p) for p in PointSet(HyperCube{2}, Point2f)])
  rect = Rectangle((-1, -1), (1, 1), uvs, nothing)

  transient_image = Resource(similar(transient_color.attachment.view.image; usage_flags = Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_SAMPLED_BIT), :transient_image)
  transiant_parameters = @set parameters.color[1] = transient_color
  transfer = transfer_command(transient_color, transient_image)

  blur_y = GaussianBlurDirectional(transient_image, BLUR_VERTICAL, blur.size)

  (
    RenderNode(Command(cache, blur_x, transiant_parameters, Primitive(rect)), :directional_blur_x),
    RenderNode(transfer, :transfer),
    RenderNode(Command(cache, blur_y, parameters, geometry), :directional_blur_y),
  )
end
