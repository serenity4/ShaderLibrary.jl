struct PrefilteredEnvironmentConvolution{F} <: GraphicsShaderComponent
  texture::Texture
  roughness::Float32
end

PrefilteredEnvironmentConvolution{F}(resource::Resource, roughness) where {F} = PrefilteredEnvironmentConvolution{F}(environment_texture_cubemap(resource), roughness)
PrefilteredEnvironmentConvolution(resource::Resource, roughness) = PrefilteredEnvironmentConvolution{resource.image.format}(resource, roughness)

interface(shader::PrefilteredEnvironmentConvolution) = Tuple{Vector{Vec3},Nothing,Nothing}
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
      value += vec3(sample_from_cubemap(environment_map, light_direction)) * sₗ
      total_weight += sₗ
    end
  end
  @swizzle prefiltered_color.rgb = value ./ total_weight
  @swizzle prefiltered_color.a = 1F
end

# XXX: Define and use the GLSL intrinsic in SPIRV.jl
reflect(vec, axis) = normalize(vec - 2F * (vec ⋅ axis) * axis)

function Program(::Type{PrefilteredEnvironmentConvolution{F}}, device) where {F}
  vert = @vertex device irradiance_convolution_vert(::Mutable{Vec4}::Output{Position}, ::Mutable{Vec3}::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device prefiltered_environment_convolution_frag(
    ::Mutable{Vec4}::Output,
    ::Vec3::Input,
    ::PhysicalRef{InvocationData}::PushConstant,
    ::Arr{2048,SPIRV.SampledImage{spirv_image_type(F, Val(:cubemap))}}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_COMBINED_IMAGE_SAMPLER)})
  Program(vert, frag)
end
