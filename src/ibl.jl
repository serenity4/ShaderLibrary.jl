# Setup `GraphicsShaderComponent`s to compute the required data for image-based lighting to be used.
# The main things to compute are:
# - The irradiance map, used for diffuse lighting (a single low-resolution cubemap).
# - The prefiltered envrionment map, used for specular lighting (a high-resolution cubemap where increasing mip levels are correlated to decreasing roughness).

struct IrradianceConvolution{C<:CubeMap} <: GraphicsShaderComponent
  texture::Texture
end

IrradianceConvolution{C}(resource::Resource) where {C<:CubeMap} = IrradianceConvolution{C}(default_texture(resource; address_modes = CLAMP_TO_EDGE))
IrradianceConvolution(environment::CubeMap, device) = IrradianceConvolution{typeof(environment)}(Resource(environment, device))

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

function irradiance_convolution_frag(::Type{<:CubeMap}, irradiance, location, (; data)::PhysicalRef{InvocationData}, textures)
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

function Program(::Type{IrradianceConvolution{C}}, device) where {C}
  vert = @vertex device irradiance_convolution_vert(::Vec4::Output{Position}, ::Vec3::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device irradiance_convolution_frag(
    ::Type{C},
    ::Vec4::Output,
    ::Vec3::Input,
    ::PhysicalRef{InvocationData}::PushConstant,
    ::Arr{2048,SPIRV.SampledImage{SPIRV.image_type(C)}}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_COMBINED_IMAGE_SAMPLER)})
  Program(vert, frag)
end

compute_irradiance(environment::CubeMap{T}, device::Device) where {T} = compute_irradiance(CubeMap{T}, Resource(environment, device), device)

function compute_irradiance(::Type{CubeMap{T}}, environment::Resource, device::Device) where {T}
  # Use small attachments, as irradiance cubemaps don't have high-frequency details.
  n = 32
  face_attachments = [attachment_resource(device, zeros(T, n, n); usage_flags = Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT) for _ in 1:6]
  shader = IrradianceConvolution{CubeMap{T}}(environment)
  screen = screen_box(face_attachments[1])
  faces = Matrix{T}[]
  for (face_attachment, directions) in zip(face_attachments, face_directions(CubeMap))
    geometry = Primitive(Rectangle(screen, directions, nothing))
    parameters = ShaderParameters(face_attachment)
    # Improvement: Parallelize face rendering with `render!` and a manually constructed render graph.
    # There is no need to synchronize sequentially with blocking functions as done here.
    render(device, shader, parameters, geometry)
    face = collect(face_attachment, device)
    push!(faces, face)
  end
  CubeMap(faces)
end

struct PrefilteredEnvironmentConvolution{C<:CubeMap} <: GraphicsShaderComponent
  texture::Texture
  roughness::Float32
end

PrefilteredEnvironmentConvolution{C}(resource::Resource, roughness) where {C<:CubeMap} = PrefilteredEnvironmentConvolution{C}(default_texture(resource; address_modes = CLAMP_TO_EDGE), roughness)
PrefilteredEnvironmentConvolution(environment::CubeMap, device, roughness) = PrefilteredEnvironmentConvolution{typeof(environment)}(Resource(environment, device), roughness)

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
hammersley(i::UInt32, n) = Vec2(float(i)/float(n), radical_inverse_vdc(i))

"""
    importance_sampling_ggx((a, b), α)
    importance_sampling_ggx((a, b), α, Ω::Rotation)
    importance_sampling_ggx((a, b), α, normal)

Generate a microfacet normal using importance sampling, such that light reflected on it contributes to the lighting.

`a` and `b` are two random numbers between 0 and 1, used to generate a normal vector disturbed on the tangent/bitangent directions.
`α` is the roughness of the surface, used to predict a sampling shape that is more widely spread for larger roughness values.

If a rotation or normal is provided as a third argument, the result will be converted from tangent space to world space.
"""
function importance_sampling_ggx end

function importance_sampling_ggx((a, b), α)
  # Generate spherical angles from the two random nubmers `a` and `b`.
  α² = α^2
  ϕ = 2πF * a
  sinϕ, cosϕ = sincos(ϕ)
  cosθ = sqrt((one(b) - b) / (one(b) + (α²^2 - one(b)) * b))
  sinθ = sqrt(one(cosθ) - cosθ^2)

  # Generate a cartesian vector from spherical angles.
  Point(sinθ * cosϕ, sinθ * sinϕ, cosθ)
end

importance_sampling_ggx((a, b), α, Ω::Rotation) = apply_rotation(importance_sampling_ggx((a, b), α), Ω)
importance_sampling_ggx((a, b), α, microfacet_normal) = importance_sampling_ggx((a, b), α, Rotation(Point3f(0, 0, 1), point3(microfacet_normal)))

# -------------------------------------------------

function prefiltered_environment_convolution_frag(::Type{C}, prefiltered_color, location, (; data)::PhysicalRef{InvocationData}, textures) where {C<:CubeMap}
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
      value += sample_along_direction(C, environment_map, light_direction).rgb * sₗ
      total_weight += sₗ
    end
  end
  prefiltered_color.rgb = value ./ total_weight
  prefiltered_color.a = 1F
end

reflect(vec, axis) = normalize(vec - 2F * (vec ⋅ axis) * axis)

function Program(::Type{PrefilteredEnvironmentConvolution{C}}, device) where {C}
  vert = @vertex device irradiance_convolution_vert(::Vec4::Output{Position}, ::Vec3::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device prefiltered_environment_convolution_frag(
    ::Type{C},
    ::Vec4::Output,
    ::Vec3::Input,
    ::PhysicalRef{InvocationData}::PushConstant,
    ::Arr{2048,SPIRV.SampledImage{SPIRV.image_type(C)}}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_COMBINED_IMAGE_SAMPLER)})
  Program(vert, frag)
end

function compute_prefiltered_environment!(image::Image, mip_level::Integer, device::Device, shader::PrefilteredEnvironmentConvolution)
  screen = screen_box(1.0)
  for (i, directions) in enumerate(face_directions(CubeMap))
    geometry = Primitive(Rectangle(screen, directions, nothing))
    attachment = attachment_resource(ImageView(image; layer_range = i:i, mip_range = mip_level:mip_level), WRITE; name = Symbol(:prefiltered_environment_mip_, mip_level, :_layer_, fieldnames(CubeMap)[i]))
    parameters = ShaderParameters(attachment)
    # Improvement: Parallelize face rendering with `render!` and a manually constructed render graph.
    # There is no need to synchronize sequentially with blocking functions as done here.
    render(device, shader, parameters, geometry)
  end
end

function compute_prefiltered_environment!(result::Resource, environment::Resource, device::Device)
  for mip_level in mip_range(result.image)
    roughness = (mip_level - 1) / (max(1, length(mip_range(result.image)) - 1))
    shader = PrefilteredEnvironmentConvolution{CubeMap{Lava.format_type(environment.image.format)}}(environment, roughness)
    compute_prefiltered_environment!(result.image, mip_level, device, shader)
  end
  result
end

function compute_prefiltered_environment(environment::Resource, device::Device; base_resolution = 256, mip_levels = Int(log2(base_resolution)) - 2, usage_flags = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_SAMPLED_BIT)
  result = image_resource(device, nothing; dims = [base_resolution, base_resolution], format = environment.image.format, layers = 6, mip_levels, usage_flags = Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT | usage_flags, name = :prefiltered_environment)
  compute_prefiltered_environment!(result, environment, device)
end
