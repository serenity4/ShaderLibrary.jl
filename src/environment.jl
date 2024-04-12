abstract type EnvironmentMap{T} end

struct CubeMap{T} <: EnvironmentMap{T}
  xp::Matrix{T}
  xn::Matrix{T}
  yp::Matrix{T}
  yn::Matrix{T}
  zp::Matrix{T}
  zn::Matrix{T}
end

Base.eltype(::Type{CubeMap{T}}) where {T} = T

Base.show(io::IO, cubemap::CubeMap) = print(io, CubeMap, " with 6x$(join(size(cubemap.xp), 'x')) ", eltype(typeof(cubemap)), " texels")

check_number_of_images(images) = length(images) == 6 || throw(ArgumentError("Expected 6 face images for CubeMap, got $(length(images)) instead"))

function CubeMap(images::AbstractVector{Matrix{T}}) where {T}
  check_number_of_images(images)
  allequal(size(image) for image in images) || throw(ArgumentError("Expected all face images to have the same size, obtained multiple sizes $(unique(size.(images)))"))
  CubeMap(images...)
end

function CubeMap(images::AbstractVector{T}) where {T<:Matrix}
  check_number_of_images(images)
  xp, xn, yp, yn, zp, zn = promote(ntuple(i -> images[i], 6)...)
  CubeMap(@SVector [xp, xn, yp, yn, zp, zn])
end

function Lava.Resource(device::Device, cubemap::CubeMap)
  (; xp, xn, yp, yn, zp, zn) = cubemap
  data = [xp, xn, yp, yn, zp, zn]
  image_resource(device, data; name = :environment_cubemap, array_layers = 6)
end

struct EquirectangularMap{T} <: EnvironmentMap{T}
  data::Matrix{T}
end

function Lava.Resource(device::Device, image::EquirectangularMap)
  image_resource(device, image.data; name = :environment_equirectangular_image)
end

struct Environment{E<:EnvironmentMap} <: GraphicsShaderComponent
  texture::Texture
end

Environment(device::Device, cubemap::CubeMap) = Environment{typeof(cubemap)}(Resource(device, cubemap))
Environment(device::Device, equirectangular::EquirectangularMap) = Environment{typeof(equirectangular)}(Resource(device, equirectangular))

function Environment{C}(resource::Resource) where {C<:EnvironmentMap}
  # Make sure we don't have any seams.
  texture = default_texture(resource; address_modes = CLAMP_TO_EDGE)
  Environment{C}(texture)
end

interface(env::Environment) = Tuple{Vector{Point3f},Nothing,Nothing}
user_data(env::Environment, ctx) = DescriptorIndex(texture_descriptor(env.texture), ctx)
resource_dependencies(env::Environment) = @resource_dependencies begin
  @read env.texture.image::Texture
end

function environment_vert(position, direction, index, (; data)::PhysicalRef{InvocationData})
  position.xyz = world_to_screen_coordinates(data.vertex_locations[index + 1U], data)
  # Give it a maximum depth value to make sure the environment stays in the background.
  position.z = 1
  # Rely on the built-in interpolation to generate suitable directions for all fragments.
  # Per-fragment linear interpolation remains correct because during cubemap sampling
  # the "direction" vector is normalized, thus reprojected on the unit sphere.
  direction[] = @load data.vertex_data[index + 1U]::Vec3
end

function environment_frag(::Type{C}, color, direction, (; data)::PhysicalRef{InvocationData}, textures) where {C<:EnvironmentMap}
  texture_index = @load data.user_data::DescriptorIndex
  texture = textures[texture_index]
  color.rgb = sample_along_direction(C, texture, direction)
  color.a = 1F
end

function sample_along_direction(::Type{<:CubeMap}, texture, direction)
  # Convert from Vulkan's right-handed to the cubemap sampler's left-handed coordinate system.
  # To do this, perform an improper rotation, e.g. a mirroring along the Z-axis.
  direction = Vec3(direction.x, direction.y, -direction.z)
  texture(vec4(direction))
end

function sample_along_direction(::Type{<:EquirectangularMap}, texture, direction)
  (x, y, z) = direction
  # Remap equirectangular map coordinates into our coordinate system.
  (x, y, z) = (-z, -x, y)
  uv = spherical_uv_mapping(Vec3(x, y, z))
  # Make sure we are using fine derivatives,
  # given that there is a discontinuity along the `u` coordinate.
  # This should already be the case for most hardware,
  # but some may keep using coarse derivatives by default.
  dx, dy = DPdxFine(uv), DPdyFine(uv)
  texture(uv, dx, dy)
end

function spherical_uv_mapping(direction)
  (x, y, z) = normalize(direction)
  # Angle in the XY plane, with respect to X.
  ϕ = atan(y, x)
  # Angle in the Zr plane, with respect to Z.
  θ = acos(z)

  # Normalize angles.
  ϕ′ = ϕ/(2(π)F) # [-π, π] -> [-0.5, 0.5]
  θ′ = θ/((π)F)  # [0, π]  -> [0, 1]

  u = 0.5F - ϕ′
  v = θ′
  Vec2(u, v)
end

function Program(::Type{Environment{C}}, device) where {C<:EnvironmentMap}
  vert = @vertex device environment_vert(::Vec4::Output{Position}, ::Vec3::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device environment_frag(
    ::Type{C},
    ::Vec4::Output,
    ::Vec3::Input,
    ::PhysicalRef{InvocationData}::PushConstant,
    ::Arr{2048,SPIRV.SampledImage{SPIRV.image_type(C)}}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_COMBINED_IMAGE_SAMPLER)})
  Program(vert, frag)
end

SPIRV.image_type(::Type{CubeMap{T}}) where {T} = SPIRV.image_type(eltype_to_image_format(T), SPIRV.DimCube, 0, true, false, 1)
SPIRV.image_type(::Type{CubeMap}) = SPIRV.image_type(CubeMap{RGBA{Float16}})
SPIRV.image_type(::Type{EquirectangularMap{T}}) where {T} = SPIRV.image_type(eltype_to_image_format(T), SPIRV.Dim2D, 0, false, false, 1)
SPIRV.image_type(::Type{EquirectangularMap}) = SPIRV.image_type(EquirectangularMap{RGBA{Float16}})

CubeMap(equirectangular::EquirectangularMap{TE}, device::Device) where {TE} = CubeMap{TE}(equirectangular, device)
function CubeMap{TC}(equirectangular::EquirectangularMap{TE}, device::Device) where {TC,TE}
  (nx, ny) = size(equirectangular.data)
  @assert nx == 2ny
  n = ny
  T = promote_type(TC, TE)
  # Improvement: Make a single arrayed image (if color attachments with several layers are widely supported).
  # Even if they are, a cubemap usage would probably not be supported, so would need still a transfer at the end.
  face_attachments = [attachment_resource(device, zeros(T, n, n); usage_flags = Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT) for _ in 1:6]
  faces = Matrix{T}[]
  shader = Environment(device, equirectangular)
  screen = screen_box(face_attachments[1])
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

function face_directions(::Type{<:CubeMap})
  @SVector [
    Point3f[(1, -1, -1), (1, -1, 1), (1, 1, -1), (1, 1, 1)],
    Point3f[(-1, -1, 1), (-1, -1, -1), (-1, 1, 1), (-1, 1, -1)],
    Point3f[(-1, 1, -1), (1, 1, -1), (-1, 1, 1), (1, 1, 1)],
    Point3f[(-1, -1, 1), (1, -1, 1), (-1, -1, -1), (1, -1, -1)],
    Point3f[(-1, -1, -1), (1, -1, -1), (-1, 1, -1), (1, 1, -1)],
    Point3f[(1, -1, 1), (-1, -1, 1), (1, 1, 1), (-1, 1, 1)],
  ]
end

Environment{C}(device::Device, image::EquirectangularMap) where {C<:CubeMap} = Environment(device, C(device, image))

struct IrradianceConvolution{C<:CubeMap} <: GraphicsShaderComponent
  texture::Texture
end

IrradianceConvolution{C}(resource::Resource) where {C<:CubeMap} = IrradianceConvolution{C}(default_texture(resource; address_modes = CLAMP_TO_EDGE))
IrradianceConvolution(environment::CubeMap, device) = IrradianceConvolution{typeof(environment)}(Resource(device, environment))

interface(shader::IrradianceConvolution) = Tuple{Vector{Point3f},Nothing,Nothing}
user_data(shader::IrradianceConvolution, ctx) = DescriptorIndex(texture_descriptor(shader.texture), ctx)
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

function irradiance_convolution_vert(position, center, index, (; data)::PhysicalRef{InvocationData})
  position.xyz = world_to_screen_coordinates(data.vertex_locations[index + 1], data)
  position.z = 1
  center[] = @load data.vertex_data[index + 1]::Vec3
end

function irradiance_convolution_frag(::Type{<:CubeMap}, irradiance, center, (; data)::PhysicalRef{InvocationData}, textures)
  texture_index = @load data.user_data::DescriptorIndex
  texture = textures[texture_index]
  dθ = 0.025F
  dϕ = 0.025F
  value = convolve_hemisphere(Vec3, center, dθ, dϕ) do direction, θ, ϕ
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

compute_irradiance(environment::CubeMap{T}, device::Device) where {T} = compute_irradiance(CubeMap{T}, Resource(device, environment), device)

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
