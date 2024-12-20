# Setup `GraphicsShaderComponent`s to compute the required data for image-based lighting to be used.
# The main things to compute are:
# - The irradiance map, used for diffuse lighting (a single low-resolution cubemap).
# - The prefiltered envrionment map, used for specular lighting (a high-resolution cubemap where increasing mip levels are correlated to decreasing roughness).

struct IrradianceConvolution{F} <: GraphicsShaderComponent
  texture::Texture
end

IrradianceConvolution{F}(resource::Resource) where {F} = IrradianceConvolution{F}(environment_texture_cubemap(resource))
IrradianceConvolution(resource::Resource) = IrradianceConvolution{resource.image.format}(resource)

interface(shader::IrradianceConvolution) = Tuple{Vector{Vec3},Nothing,Nothing}
user_data(shader::IrradianceConvolution, ctx) = instantiate(shader.texture, ctx)
resource_dependencies(shader::IrradianceConvolution) = @resource_dependencies begin
  @read shader.texture.resource::Texture
end

function convolve_hemisphere(f, ::Type{T}, center, dθ, dϕ) where {T}
  value = zero(T)
  nθ = 1U + (fld(πF, 2dϕ))U
  nϕ = 1U + (fld(2πF, dθ))U
  n = nθ * nϕ
  q = Rotation(Vec3(0, 0, 1), center)
  θ = 0F
  for i in 1U:nθ
    θ += dθ
    ϕ = 0F
    for j in 1U:nϕ
      ϕ += dϕ
      sinθ, cosθ = sincos(θ)
      sinϕ, cosϕ = sincos(ϕ)
      direction = Point(sinθ * cosϕ, sinθ * sinϕ, cosθ)
      direction = apply_rotation(direction, q)
      # Sum the new value, weighted by sinθ to balance out the skewed distribution toward the pole.
      value = value .+ f(direction, θ, ϕ) .* sinθ
    end
  end
  value ./ n
end

function irradiance_convolution_vert(position, location, index, (; data)::PhysicalRef{InvocationData})
  @swizzle position.xyz = world_to_screen_coordinates(data.vertex_locations[index + 1], data)
  @swizzle position.z = 1
  location[] = @load data.vertex_data[index + 1]::Vec3
end

function irradiance_convolution_frag(irradiance, location, (; data)::PhysicalRef{InvocationData}, textures)
  texture_index = @load data.user_data::DescriptorIndex
  texture = textures[texture_index]
  dθ = 0.025F
  dϕ = 0.025F
  value = convolve_hemisphere(Vec3, location, dθ, dϕ) do direction, θ, ϕ
    @inline
    vec3(sample_from_cubemap(texture, direction)) .* cos(θ)
  end
  @swizzle irradiance.rgb = value .* πF
  @swizzle irradiance.a = 1F
end

function Program(::Type{IrradianceConvolution{F}}, device) where {F}
  vert = @vertex device irradiance_convolution_vert(::Mutable{Vec4}::Output{Position}, ::Mutable{Vec3}::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device irradiance_convolution_frag(
    ::Mutable{Vec4}::Output,
    ::Vec3::Input,
    ::PhysicalRef{InvocationData}::PushConstant,
    ::Arr{2048,SPIRV.SampledImage{spirv_image_type(F, Val(:cubemap))}}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_COMBINED_IMAGE_SAMPLER)})
  Program(vert, frag)
end

function compute_irradiance(environment::Resource, device::Device)
  # Use small attachments, as irradiance cubemaps don't have high-frequency details.
  n = 32
  usage_flags = Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_SAMPLED_BIT
  irradiance = image_resource(device, nothing; environment.image.format, dims = [n, n], layers = 6, usage_flags)
  shader = IrradianceConvolution{environment.image.format}(environment)
  screen = screen_box(1.0)
  for layer in 1:6
    directions = CUBEMAP_FACE_DIRECTIONS[layer]
    geometry = Primitive(Rectangle(screen, directions, nothing))
    attachment = attachment_resource(ImageView(irradiance.image; layer_range = layer:layer), WRITE; name = Symbol(:irradiance_layer_, layer))
    parameters = ShaderParameters(attachment)
    # Improvement: Parallelize face rendering with `render!` and a manually constructed render graph.
    # There is no need to synchronize sequentially with blocking functions as done here.
    render(device, shader, parameters, geometry)
  end
  irradiance
end
