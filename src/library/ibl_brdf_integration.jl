struct BRDFIntegration <: GraphicsShaderComponent end

interface(shader::BRDFIntegration) = Tuple{Vector{Vec2},Nothing,Nothing}

function brdf_integration_vert(position, uv, index, (; data)::PhysicalRef{InvocationData})
  @swizzle position.xyz = world_to_screen_coordinates(data.vertex_locations[index + 1], data)
  @swizzle position.z = 1
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
  color[] = Vec4(scale, bias, 0F, 1F)
end

function Program(::Type{BRDFIntegration}, device)
  vert = @vertex device brdf_integration_vert(::Mutable{Vec4}::Output{Position}, ::Mutable{Vec2}::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device brdf_integration_frag(
    ::Mutable{Vec4}::Output,
    ::Vec2::Input,
    ::PhysicalRef{InvocationData}::PushConstant
  )
  Program(vert, frag)
end
