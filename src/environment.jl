struct CubeMap{T}
  xp::Matrix{T}
  xn::Matrix{T}
  yp::Matrix{T}
  yn::Matrix{T}
  zp::Matrix{T}
  zn::Matrix{T}
end

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

struct Environment <: GraphicsShaderComponent
  texture::Texture
end

Environment(device::Device, cubemap::CubeMap) = Environment(Resource(device, cubemap))
Environment(cubemap::Resource) = Environment(default_texture(cubemap))

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

function environment_frag(color, direction, (; data)::PhysicalRef{InvocationData}, textures)
  texture_index = @load data.user_data::DescriptorIndex
  color.rgb = textures[texture_index](vec4(direction))
  color.a = 1F
end

function Program(::Type{Environment}, device)
  vert = @vertex device environment_vert(::Vec4::Output{Position}, ::Vec3::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device environment_frag(
    ::Vec4::Output,
    ::Vec3::Input,
    ::PhysicalRef{InvocationData}::PushConstant,
    ::Arr{2048,SPIRV.SampledImage{SPIRV.image_type(SPIRV.ImageFormatRgba16f, SPIRV.DimCube, 0, true, false, 1)}}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_COMBINED_IMAGE_SAMPLER)})
  Program(vert, frag)
end
