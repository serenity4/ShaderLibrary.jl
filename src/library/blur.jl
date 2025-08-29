const BLUR_HORIZONTAL = 0U
const BLUR_VERTICAL = 1U

struct GaussianBlurDirectional <: GraphicsShaderComponent
  texture::Texture
  direction::UInt32
  size::Float32
end
GaussianBlurDirectional(image::Resource, direction, size = 0.01) = GaussianBlurDirectional(default_texture(image), direction, size)

gaussian_1d(t, size) = exp(-t^2 / 2size^2) / sqrt(2 * πF * size^2)

function gaussian_blur_directional(reference, uv, direction, size)
  color = zero(Vec3)
  imsize = Base.size(SPIRV.Image(reference), 0U)
  pixel_size = 1F ./ imsize # size of one pixel in UV coordinates.
  rx, ry = Int32.(min.(ceil.(3size .* imsize), imsize))
  if direction == BLUR_HORIZONTAL
    @for i in -rx:rx begin
      uv_offset = Vec2(i * pixel_size[1], 0)
      weight = gaussian_1d(uv_offset.x, size) * pixel_size[1]
      sampled = vec3(reference(uv + uv_offset))
      color += sampled * weight
    end
  else
    @for j in -ry:ry begin
      uv_offset = Vec2(0, j * pixel_size[2])
      weight = gaussian_1d(uv_offset.y, size) * pixel_size[2]
      sampled = vec3(reference(uv + uv_offset))
      color += sampled * weight
    end
  end
  color
end

function gaussian_blur_directional_frag(color, uv, (; data)::PhysicalRef{InvocationData}, textures)
  direction, size, texture_index = @load data.user_data::Tuple{UInt32, Float32, DescriptorIndex}
  reference = textures[texture_index]
  @swizzle color.rgb = gaussian_blur_directional(reference, uv, direction, size)
  @swizzle color.a = 1F
end

function Program(::Type{GaussianBlurDirectional}, device)
  vert = @vertex device sprite_vert(::Mutable{Vec4}::Output{Position}, ::Mutable{Vec2}::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device gaussian_blur_directional_frag(
    ::Mutable{Vec4}::Output,
    ::Vec2::Input,
    ::PhysicalRef{InvocationData}::PushConstant,
    ::Arr{2048,SPIRV.SampledImage{image_type(SPIRV.ImageFormatRgba16f, SPIRV.Dim2D, 0, false, false, 1)}}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_COMBINED_IMAGE_SAMPLER)})
  Program(vert, frag)
end

user_data(blur::GaussianBlurDirectional, ctx) = (blur.direction, blur.size, instantiate(blur.texture, ctx))
resource_dependencies(blur::GaussianBlurDirectional) = @resource_dependencies begin
  @read blur.texture.resource::Texture
end
interface(::GaussianBlurDirectional) = Tuple{Vector{Vec2},Nothing,Nothing}

struct GaussianBlur <: GraphicsShaderComponent
  texture::Texture
  size::Float32
end
GaussianBlur(image::Resource, size = 0.01) = GaussianBlur(default_texture(image), size)

function renderables(cache::ProgramCache, blur::GaussianBlur, parameters::ShaderParameters, geometry)
  color = parameters.color[1]
  transient_color = similar(color; dims = dimensions(blur.texture.resource), usage_flags = Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT, name = :transient_color)

  # First, blur the whole texture once, then blur only the relevant portion.
  # XXX: We could deduce a conservative bounding box from the radius
  # and blur this region only, instead of the whole texture.
  blur_x = GaussianBlurDirectional(blur.texture, BLUR_HORIZONTAL, blur.size)
  uvs = Vec2.([0.5 * (1 .+ p) for p in PointSet(HyperCube{2}, Vec2)])
  rect = Rectangle((-1, -1), (1, 1), uvs, nothing)

  transient_image = Resource(similar(transient_color.attachment.view.image; usage_flags = Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_SAMPLED_BIT); name = :transient_image)
  transiant_parameters = @set parameters.color[1] = transient_color
  transfer = transfer_command(transient_color, transient_image)

  blur_y = GaussianBlurDirectional(transient_image, BLUR_VERTICAL, blur.size)

  [
    RenderNode(Command(cache, blur_x, transiant_parameters, Primitive(rect)), :directional_blur_x),
    RenderNode(transfer, :transfer),
    RenderNode(Command(cache, blur_y, parameters, geometry), :directional_blur_y),
  ]
end
