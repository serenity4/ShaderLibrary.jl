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

"""
Set of directions covering all cubemap faces, in world coordinates.

The order and orientation of the faces follow cubemap conventions;
when converted to cubemap coordinates, they come in the order
+X, -X, +Y, -Y, +Z, -Z. In world coordinates, these faces may
be rotated and do not follow the same order because the frame of
reference differs.
"""
const CUBEMAP_FACE_DIRECTIONS = (x -> cubemap_to_world.(x)).(@SVector [
  Point3f[(1, -1, -1), (1, -1, 1), (1, 1, -1), (1, 1, 1)],     # +X
  Point3f[(-1, -1, 1), (-1, -1, -1), (-1, 1, 1), (-1, 1, -1)], # -X
  Point3f[(-1, 1, -1), (1, 1, -1), (-1, 1, 1), (1, 1, 1)],     # +Y
  Point3f[(-1, -1, 1), (1, -1, 1), (-1, -1, -1), (1, -1, -1)], # -Y
  Point3f[(-1, -1, -1), (1, -1, -1), (-1, 1, -1), (1, 1, -1)], # +Z
  Point3f[(1, -1, 1), (-1, -1, 1), (1, 1, 1), (-1, 1, 1)],     # -Z
])
