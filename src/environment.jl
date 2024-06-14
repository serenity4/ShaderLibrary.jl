check_number_of_images(images) = length(images) == 6 || throw(ArgumentError("Expected 6 face images for CubeMap, got $(length(images)) instead"))

function create_cubemap(device::Device, images::AbstractVector{Matrix{T}}) where {T}
  check_number_of_images(images)
  allequal(size(image) for image in images) || throw(ArgumentError("Expected all face images to have the same size, obtained multiple sizes $(unique(size.(images)))"))
  image_resource(device, images; format = T, name = :cubemap, layers = 6)
end

function create_cubemap(device::Device, images::AbstractVector{T}) where {T<:Matrix}
  check_number_of_images(images)
  xp, xn, yp, yn, zp, zn = promote(ntuple(i -> images[i], 6)...)
  create_cubemap(@SVector [xp, xn, yp, yn, zp, zn])
end

struct CubeMapFaces{T}
  xp::Matrix{T}
  xn::Matrix{T}
  yp::Matrix{T}
  yn::Matrix{T}
  zp::Matrix{T}
  zn::Matrix{T}
end

Base.eltype(::Type{CubeMapFaces{T}}) where {T} = T
Base.show(io::IO, faces::CubeMapFaces) = print(io, typeof(faces), " with 6x$(join(size(faces.xp), 'x')) ", eltype(typeof(faces)), " texels")

function assert_is_cubemap(resource::Resource)
  @assertion
  assert_type(resource, RESOURCE_TYPE_IMAGE)
  allequal(dimensions(resource.image)) || error("Cubemaps require width and height to be the same")
  resource.image.layers == 6 || error("Expected 6 image layers, found ", resource.image.layers, "instead")
end

function collect_cubemap_faces(cubemap::Resource, device::Device)
  assert_is_cubemap(cubemap)
  T = eltype(cubemap.image)
  faces = Matrix{T}[]
  for layer in 1:6
    push!(faces, collect(T, cubemap.image, device; layer))
  end
  CubeMapFaces{T}(ntuple(i -> faces[i], 6)...)
end

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

interface(env::Environment) = Tuple{Vector{Point3f},Nothing,Nothing}
user_data(env::Environment, ctx) = instantiate(env.texture, ctx)
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

function environment_frag(::Type{V}, color, direction, (; data)::PhysicalRef{InvocationData}, textures) where {V<:Val}
  texture_index = @load data.user_data::DescriptorIndex
  texture = textures[texture_index]
  color.rgb = sample_along_direction(V(), texture, direction)
  color.a = 1F
end

sample_along_direction(::Val{:cubemap}, texture, direction) = sample_from_cubemap(texture, direction)
sample_along_direction(::Val{:equirectangular}, texture, direction) = sample_from_equirectangular(texture, direction)

function sample_from_cubemap(texture, direction)
  # Convert from Vulkan's right-handed to the cubemap sampler's left-handed coordinate system.
  # To do this, perform an improper rotation, e.g. a mirroring along the Z-axis.
  direction = Vec3(direction.x, direction.y, -direction.z)
  texture(vec4(direction))
end

function sample_from_equirectangular(texture, direction)
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
  ϕ′ = ϕ/2πF # [-π, π] -> [-0.5, 0.5]
  θ′ = θ/πF  # [0, π]  -> [0, 1]

  u = 0.5F - ϕ′
  v = θ′
  Vec2(u, v)
end

function Program(::Type{Environment{T,E}}, device) where {T,E}
  vert = @vertex device environment_vert(::Vec4::Output{Position}, ::Vec3::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device environment_frag(
    ::Type{Val{E}},
    ::Vec4::Output,
    ::Vec3::Input,
    ::PhysicalRef{InvocationData}::PushConstant,
    ::Arr{2048,SPIRV.SampledImage{spirv_image_type(T, Val(E))}}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_COMBINED_IMAGE_SAMPLER)})
  Program(vert, frag)
end

spirv_image_type(format::Vk.Format) = spirv_image_type(format, Val(:texture))
spirv_image_type(format::Vk.Format, ::Val{:cubemap}) = SPIRV.image_type(SPIRV.ImageFormat(format), SPIRV.DimCube, 0, true, false, 1)
spirv_image_type(format::Vk.Format, ::Val{:texture}) = SPIRV.image_type(SPIRV.ImageFormat(format), SPIRV.Dim2D, 0, false, false, 1)
spirv_image_type(format::Vk.Format, ::Val{:equirectangular}) = spirv_image_type(format)

function create_cubemap_from_equirectangular(device::Device, equirectangular::Resource)
  assert_type(equirectangular, RESOURCE_TYPE_IMAGE)
  (; image) = equirectangular
  (nx, ny) = dimensions(image)
  nx == 2ny || error("Expected an image in equirectangular format where `width = 2 * height`, found `width = $nx`, `height = $ny`")
  n = ny
  # Improvement: Make a single arrayed image (if color attachments with several layers are widely supported).
  # Even if they are, a cubemap usage would probably not be supported, so would need still a transfer at the end.
  usage_flags = Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_SAMPLED_BIT
  cubemap = image_resource(device, nothing; image.format, dims = [n, n], layers = 6, usage_flags)
  shader = environment_from_equirectangular(equirectangular)
  screen = screen_box(1.0)
  for layer in 1:6
    directions = CUBEMAP_FACE_DIRECTIONS[layer]
    geometry = Primitive(Rectangle(screen, directions, nothing))
    attachment = attachment_resource(ImageView(cubemap.image; layer_range = layer:layer), WRITE; name = Symbol(:cubemap_layer_, layer))
    parameters = ShaderParameters(attachment)
    # Improvement: Parallelize face rendering with `render!` and a manually constructed render graph.
    # There is no need to synchronize sequentially with blocking functions as done here.
    render(device, shader, parameters, geometry)
  end
  cubemap
end

const CUBEMAP_FACE_DIRECTIONS = @SVector [
  Point3f[(1, -1, -1), (1, -1, 1), (1, 1, -1), (1, 1, 1)],     # +X
  Point3f[(-1, -1, 1), (-1, -1, -1), (-1, 1, 1), (-1, 1, -1)], # -X
  Point3f[(-1, 1, -1), (1, 1, -1), (-1, 1, 1), (1, 1, 1)],     # +Y
  Point3f[(-1, -1, 1), (1, -1, 1), (-1, -1, -1), (1, -1, -1)], # -Y
  Point3f[(-1, -1, -1), (1, -1, -1), (-1, 1, -1), (1, 1, -1)], # +Z
  Point3f[(1, -1, 1), (-1, -1, 1), (1, 1, 1), (-1, 1, 1)],     # -Z
]
