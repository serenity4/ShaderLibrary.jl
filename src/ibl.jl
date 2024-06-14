# Setup `GraphicsShaderComponent`s to compute the required data for image-based lighting to be used.
# The main things to compute are:
# - The irradiance map, used for diffuse lighting (a single low-resolution cubemap).
# - The prefiltered envrionment map, used for specular lighting (a high-resolution cubemap where increasing mip levels are correlated to decreasing roughness).

struct IrradianceConvolution{F} <: GraphicsShaderComponent
  texture::Texture
end

IrradianceConvolution{F}(resource::Resource) where {F} = IrradianceConvolution{F}(environment_texture_cubemap(resource))
IrradianceConvolution(resource::Resource) = IrradianceConvolution{resource.image.format}(resource)

interface(shader::IrradianceConvolution) = Tuple{Vector{Point3f},Nothing,Nothing}
user_data(shader::IrradianceConvolution, ctx) = instantiate(shader.texture, ctx)
resource_dependencies(shader::IrradianceConvolution) = @resource_dependencies begin
  @read shader.texture.image::Texture
end

function convolve_hemisphere(f, ::Type{T}, center, dθ, dϕ) where {T}
  value = zero(T)
  nθ = 1U + (fld(πF, 2dϕ))U
  nϕ = 1U + (fld(2πF, dθ))U
  n = nθ * nϕ
  q = Rotation(Point3f(0, 0, 1), point3(center))
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
      value = value .+ f(vec4(direction), θ, ϕ) .* sinθ
    end
  end
  value ./ n
end

function irradiance_convolution_vert(position, location, index, (; data)::PhysicalRef{InvocationData})
  position.xyz = world_to_screen_coordinates(data.vertex_locations[index + 1], data)
  position.z = 1
  location[] = @load data.vertex_data[index + 1]::Vec3
end

function irradiance_convolution_frag(irradiance, location, (; data)::PhysicalRef{InvocationData}, textures)
  texture_index = @load data.user_data::DescriptorIndex
  texture = textures[texture_index]
  dθ = 0.025F
  dϕ = 0.025F
  value = convolve_hemisphere(Vec3, location, dθ, dϕ) do direction, θ, ϕ
    texture(direction).rgb .* cos(θ)
  end
  irradiance.rgb = value .* πF
  irradiance.a = 1F
end

function Program(::Type{IrradianceConvolution{F}}, device) where {F}
  vert = @vertex device irradiance_convolution_vert(::Vec4::Output{Position}, ::Vec3::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device irradiance_convolution_frag(
    ::Vec4::Output,
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

struct PrefilteredEnvironmentConvolution{F} <: GraphicsShaderComponent
  texture::Texture
  roughness::Float32
end

PrefilteredEnvironmentConvolution{F}(resource::Resource, roughness) where {F} = PrefilteredEnvironmentConvolution{F}(environment_texture_cubemap(resource), roughness)
PrefilteredEnvironmentConvolution(resource::Resource, roughness) = PrefilteredEnvironmentConvolution{resource.image.format}(resource, roughness)

interface(shader::PrefilteredEnvironmentConvolution) = Tuple{Vector{Point3f},Nothing,Nothing}
user_data(shader::PrefilteredEnvironmentConvolution, ctx) = (instantiate(shader.texture, ctx), shader.roughness)
resource_dependencies(shader::PrefilteredEnvironmentConvolution) = @resource_dependencies begin
  @read shader.texture.image::Texture
end

# -------------------------------------------------
# From https://learnopengl.com/PBR/IBL/Specular-IBL

function radical_inverse_vdc(bits::UInt32)
  bits = (bits << 16U) | (bits >> 16U)
  bits = ((bits & 0x55555555) << 1U) | ((bits & 0xAAAAAAAA) >> 1U)
  bits = ((bits & 0x33333333) << 2U) | ((bits & 0xCCCCCCCC) >> 2U)
  bits = ((bits & 0x0F0F0F0F) << 4U) | ((bits & 0xF0F0F0F0) >> 4U)
  bits = ((bits & 0x00FF00FF) << 8U) | ((bits & 0xFF00FF00) >> 8U)
  float(bits) * 2.3283064365386963f-10 # 0x100000000
end
"Generate a low discrepancy sequence using the [Hammersley set](https://en.wikipedia.org/wiki/Low-discrepancy_sequence#Hammersley_set)."
hammersley(i::UInt32, n) = Vec2((i)F/n, radical_inverse_vdc(i))

"""
    importance_sampling_ggx((a, b), α)
    importance_sampling_ggx((a, b), α, normal)

Generate a microfacet normal using importance sampling, such that light reflected on it contributes to the lighting.

`a` and `b` are two random numbers between 0 and 1, used to generate a normal vector disturbed on the tangent/bitangent directions.
`α` is the roughness of the surface, used to predict a sampling shape that is more widely spread for larger roughness values.

If a normal is provided as a third argument, it will be used to convert the result from tangent space to world space.
"""
function importance_sampling_ggx end

function importance_sampling_ggx((a, b), roughness)
  # Generate spherical angles from the two random nubmers `a` and `b`.
  α² = roughness^2
  ϕ = 2πF * a
  sinϕ, cosϕ = sincos(ϕ)
  cosθ = sqrt((one(b) - b) / (one(b) + (α²^2 - one(b)) * b))
  sinθ = sqrt(one(cosθ) - cosθ^2)

  # Generate a cartesian vector from spherical angles.
  Point(sinθ * cosϕ, sinθ * sinϕ, cosθ)
end

function importance_sampling_ggx((a, b), roughness, normal::Vec3)
  # Cartesian microfacet vector in tangent space.
  microfacet = importance_sampling_ggx((a, b), roughness)

  # Find a tangent frame expressed in world space.
  up = abs(normal.z) < 0.999 ? Vec3(0.0, 0.0, 1.0) : Vec3(1.0, 0.0, 0.0)
  tangent = normalize(up × normal)
  bitangent = normal × tangent

  # Convert from tangent space to world space using the tangent frame.
  normalize(tangent * microfacet.x + bitangent * microfacet.y + normal * microfacet.z)
end

# -------------------------------------------------

function prefiltered_environment_convolution_frag(prefiltered_color, location, (; data)::PhysicalRef{InvocationData}, textures)
  (texture_index, roughness) = @load data.user_data::Tuple{DescriptorIndex,Float32}
  environment_map = textures[texture_index]
  NUMBER_OF_SAMPLES = 1024U
  value = zero(Vec3)
  total_weight = 0F
  # Take the normalized render sample location as an outward normal meant to receive the lighting from the environment.
  normal = normalize(location)
  # Consider a view completely incident to that surface, and only this one (instead of all possible views).
  # This simplification is necessary to make PBR performant enough for real-time rendering (for this preprocessing shader and later the sampling one).
  view_direction = normal
  for i in 1U:NUMBER_OF_SAMPLES
    # Generate a microfacet direction roughly aligned with the sampled normal.
    # Then, negate that direction because the microfacet is meant to face the normal.
    microfacet_normal = -importance_sampling_ggx(hammersley(i, NUMBER_OF_SAMPLES), roughness, normal)

    # Generate the light direction, taken to be a simple reflection of the view direction along the microfacet normal.
    # The view direction is negated to have the light direction face the correct side (from the microfacet normal to the light source).
    light_direction = reflect(-view_direction, microfacet_normal)

    # Add the contribution to the lighting value.
    # If the microfacet normal was generated with an adequate importance sampling method,
    # the required condition should be satisfied most of the time.

    sₗ = shape_factor(normal, light_direction)
    if !iszero(sₗ)
      value += sample_from_cubemap(environment_map, light_direction).rgb * sₗ
      total_weight += sₗ
    end
  end
  prefiltered_color.rgb = value ./ total_weight
  prefiltered_color.a = 1F
end

reflect(vec, axis) = normalize(vec - 2F * (vec ⋅ axis) * axis)

function Program(::Type{PrefilteredEnvironmentConvolution{F}}, device) where {F}
  vert = @vertex device irradiance_convolution_vert(::Vec4::Output{Position}, ::Vec3::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device prefiltered_environment_convolution_frag(
    ::Vec4::Output,
    ::Vec3::Input,
    ::PhysicalRef{InvocationData}::PushConstant,
    ::Arr{2048,SPIRV.SampledImage{spirv_image_type(F, Val(:cubemap))}}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_COMBINED_IMAGE_SAMPLER)})
  Program(vert, frag)
end

function compute_prefiltered_environment!(image::Image, mip_level::Integer, device::Device, shader::PrefilteredEnvironmentConvolution)
  screen = screen_box(1.0)
  for layer in 1:6
    directions = CUBEMAP_FACE_DIRECTIONS[layer]
    geometry = Primitive(Rectangle(screen, directions, nothing))
    attachment = attachment_resource(ImageView(image; layer_range = layer:layer, mip_range = mip_level:mip_level), WRITE; name = Symbol(:prefiltered_environment_mip_, mip_level, :_layer_, fieldnames(CubeMapFaces)[layer]))
    parameters = ShaderParameters(attachment)
    # Improvement: Parallelize face rendering with `render!` and a manually constructed render graph.
    # There is no need to synchronize sequentially with blocking functions as done here.
    render(device, shader, parameters, geometry)
  end
end

function compute_prefiltered_environment!(result::Resource, environment::Resource, device::Device)
  assert_is_cubemap(result)
  for mip_level in mip_range(result.image)
    roughness = (mip_level - 1) / (max(1, length(mip_range(result.image)) - 1))
    shader = PrefilteredEnvironmentConvolution{environment.image.format}(environment, roughness)
    compute_prefiltered_environment!(result.image, mip_level, device, shader)
  end
  result
end

function compute_prefiltered_environment(environment::Resource, device::Device; base_resolution = 256, mip_levels = Int(log2(base_resolution)) - 2, usage_flags = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_SAMPLED_BIT)
  result = image_resource(device, nothing; dims = [base_resolution, base_resolution], format = environment.image.format, layers = 6, mip_levels, usage_flags = Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT | usage_flags, name = :prefiltered_environment)
  compute_prefiltered_environment!(result, environment, device)
end

struct BRDFIntegration <: GraphicsShaderComponent end

interface(shader::BRDFIntegration) = Tuple{Vector{Vec2},Nothing,Nothing}

function brdf_integration_vert(position, uv, index, (; data)::PhysicalRef{InvocationData})
  position.xyz = world_to_screen_coordinates(data.vertex_locations[index + 1], data)
  position.z = 1
  uv[] = @load data.vertex_data[index + 1]::Vec2
end

function brdf_integration_frag(color, uv, (; data)::PhysicalRef{InvocationData})
  (sᵥ, roughness) = uv
  NUMBER_OF_SAMPLES = 4096U
  scale, bias = 0F, 0F
  view = Vec3(sqrt(1F - sᵥ^2), 0F, sᵥ)
  normal = Vec3(0, 0, 1)
  for i in 1U:NUMBER_OF_SAMPLES
    # Generate a microfacet direction roughly aligned with the normal.
    # Then, negate that direction because the microfacet is meant to face the normal.
    microfacet = importance_sampling_ggx(hammersley(i, NUMBER_OF_SAMPLES), roughness, normal)

    # Generate the light direction, taken to be a simple reflection of the view direction along the microfacet normal.
    # The view direction is negated to have the light direction face the correct side (from the microfacet normal to the light source).
    light = reflect(-view, microfacet)

    # Add the contribution to the lighting value.
    # If the microfacet normal was generated with an adequate importance sampling method,
    # the required condition should be satisfied most of the time.

    sₗ = max(light.z, 0F) # = shape_factor(const normal, light)
    if !iszero(sₗ)
      sₕ = max(microfacet.z, 0F) # = # shape_factor(const normal, microfacet)
      occlusion = microfacet_occlusion_factor(remap_roughness_image_based_lighting(roughness), sᵥ, sₗ)
      sᵥₕ = shape_factor(view, microfacet)
      visibility = occlusion * sᵥₕ / (sₕ * sᵥ)
      α = pow5(1F - sᵥₕ)
      scale += (1F - α) * visibility
      bias += α * visibility
    end
  end
  scale /= NUMBER_OF_SAMPLES
  bias /= NUMBER_OF_SAMPLES
  color.r = scale
  color.g = bias
  color.a = 1F
end

function Program(::Type{BRDFIntegration}, device)
  vert = @vertex device brdf_integration_vert(::Vec4::Output{Position}, ::Vec2::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device brdf_integration_frag(
    ::Vec4::Output,
    ::Vec2::Input,
    ::PhysicalRef{InvocationData}::PushConstant
  )
  Program(vert, frag)
end
