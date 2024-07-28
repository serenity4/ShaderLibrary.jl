struct Environment{F,E} <: GraphicsShaderComponent
  texture::Texture
end

environment_from_cubemap(resource::Resource) = environment_from_cubemap(resource.image.format, resource)
environment_from_equirectangular(resource::Resource) = environment_from_equirectangular(resource.image.format, resource)

environment_from_cubemap(format::Vk.Format, cubemap::Resource) = Environment{format,:cubemap}(cubemap)
environment_from_equirectangular(format::Vk.Format, resource::Resource) = Environment{format,:equirectangular}(resource)

Environment{F,:equirectangular}(resource::Resource) where {F} = Environment{F,:equirectangular}(environment_texture_equirectangular(resource))
Environment{F,:cubemap}(resource::Resource) where {F} = Environment{F,:cubemap}(environment_texture_cubemap(resource))

  # Make sure we don't have any seams.
function environment_texture_equirectangular(resource::Resource)
  assert_type(resource, RESOURCE_TYPE_IMAGE)
  default_texture(resource; address_modes = CLAMP_TO_EDGE)
end
function environment_texture_cubemap(resource::Resource)
  assert_is_cubemap(resource)
  default_texture(resource; address_modes = CLAMP_TO_EDGE)
end

Accessors.constructorof(::Type{Environment{T,E}}) where {T,E} = Environment{T,E}

interface(env::Environment) = Tuple{Vector{Vec3},Nothing,Nothing}
user_data(env::Environment, ctx) = instantiate(env.texture, ctx)
resource_dependencies(env::Environment) = @resource_dependencies begin
  @read env.texture.image::Texture
end

function environment_vert(position, direction, index, (; data)::PhysicalRef{InvocationData})
  @swizzle position.xyz = world_to_screen_coordinates(data.vertex_locations[index + 1U], data)
  # Give it a maximum depth value to make sure the environment stays in the background.
  position.z = 1
  # Rely on the built-in interpolation to generate suitable directions for all fragments.
  # Per-fragment linear interpolation remains correct because during cubemap sampling
  # the "direction" vector is normalized, thus reprojected on the unit sphere.
  direction[] = @load data.vertex_data[index + 1U]::Vec3
end

function environment_frag(::Type{V}, color, direction, (; data)::PhysicalRef{InvocationData}, textures) where {V<:Val}
  texture_index = @load data.user_data::DescriptorIndex
  texture = textures[texture_index]
  @swizzle color.rgb = sample_along_direction(V(), texture, direction)
  @swizzle color.a = 1F
end

sample_along_direction(::Val{:cubemap}, texture, direction) = sample_from_cubemap(texture, direction)
sample_along_direction(::Val{:equirectangular}, texture, direction) = sample_from_equirectangular(texture, direction)

"""
Convert from the world coordinate system (right-handed, +Z up)
to the cubemap sampler's coordinate system (left-handed, +Y up).
"""
world_to_cubemap(direction) = typeof(direction)(-direction.y, direction.z, direction.x)

"""
Perform the inverse conversion from cubemap coordinates into world coordinates.
"""
cubemap_to_world(direction) = typeof(direction)(-direction.z, -direction.x, direction.y)

function sample_from_cubemap(texture, direction, sampling_parameters...)
  direction = world_to_cubemap(direction)
  texture(vec4(direction), sampling_parameters...)
end

function sample_from_equirectangular(texture, direction)
  uv = spherical_uv_mapping(vec3(direction))
  # Make sure we are using fine derivatives,
  # given that there is a discontinuity along the `u` coordinate.
  # This should already be the case for most hardware,
  # but some may keep using coarse derivatives by default.
  dx, dy = SPIRV.DPdxFine(uv), SPIRV.DPdyFine(uv)
  texture(uv, dx, dy)
end

function spherical_uv_mapping(direction)
  (x, y, z) = normalize(direction)
  # Angle in the XY plane, with respect to X.
  ϕ = atan(y, x)
  # Angle in the Zr plane, with respect to Z.
  θ = acos(z)

  # Normalize angles.
  ϕ′ = ϕ/2πF # [-π, π] -> [-0.5, 0.5]
  θ′ = θ/πF  # [0, π]  -> [0, 1]

  u = 0.5F - ϕ′
  v = θ′
  Vec2(u, v)
end

function Program(::Type{Environment{T,E}}, device) where {T,E}
  vert = @vertex device environment_vert(::Mutable{Vec4}::Output{Position}, ::Mutable{Vec3}::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device environment_frag(
    ::Type{Val{E}},
    ::Mutable{Vec4}::Output,
    ::Vec3::Input,
    ::PhysicalRef{InvocationData}::PushConstant,
    ::Arr{2048,SPIRV.SampledImage{spirv_image_type(T, Val(E))}}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_COMBINED_IMAGE_SAMPLER)})
  Program(vert, frag)
end

spirv_image_type(format::Vk.Format) = spirv_image_type(format, Val(:texture))
spirv_image_type(format::Vk.Format, ::Val{:cubemap}) = SPIRV.image_type(SPIRV.ImageFormat(format), SPIRV.DimCube, 0, true, false, 1)
spirv_image_type(format::Vk.Format, ::Val{:texture}) = SPIRV.image_type(SPIRV.ImageFormat(format), SPIRV.Dim2D, 0, false, false, 1)
spirv_image_type(format::Vk.Format, ::Val{:equirectangular}) = spirv_image_type(format)
