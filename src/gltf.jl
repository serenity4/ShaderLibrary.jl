import_mesh(gltf::GLTF.Object, node::GLTF.Node) = y_up_to_z_up!(VertexMesh(gltf, node))
import_mesh(gltf::GLTF.Object) = y_up_to_z_up!(VertexMesh(gltf))

"""
Read a `Transform` from the given GLTF node.

`apply_rotation` specifies whether the +Y up to +Z up convention transform should be applied
to the transform as a rotation, or if components must simply be remapped.

If a mesh is to be read, or any other object that contains spatial data such that conventions may be applied on that data,
then `apply_rotation` must be set to `false`. Other objects, such as cameras and point lights, require `apply_rotation` to be true.
"""
import_transform(node::GLTF.Node; apply_rotation = true) = y_up_to_z_up(Transform(node); apply_rotation)

"Convert from a convention of +Y up to +Z up, assuming both are right-handed."
function y_up_to_z_up end

y_up_to_z_up(p::Point{3}) = Point(p[1], -p[3], p[2])

function y_up_to_z_up!(mesh::VertexMesh)
  mesh.vertex_locations .= y_up_to_z_up.(mesh.vertex_locations)
  mesh.vertex_normals .= y_up_to_z_up.(mesh.vertex_normals)
  mesh
end

y_up_to_z_up(tr::Translation) = Translation(y_up_to_z_up(tr.vec))
function y_up_to_z_up(sc::Scaling)
  (sx, sy, sz) = sc.vec
  Scaling(sx, sz, sy)
end
function apply_y_up_to_z_up_rotation(q::Quaternion)
  # Define rotation along X axis.
  qᵣₓ = Quaternion(RotationPlane(1F, 0F, 0F), πF/2)
  # Apply the rotation using matrices.
  q′ = Quaternion(SMatrix{3,3}(qᵣₓ) * SMatrix{3,3}(q))
  # Negate w component. Not sure why it's needed, but it's needed.
  Quaternion(-q′.w, q′.x, q′.y, q′.z)
end
function remap_y_up_to_z_up(q::Quaternion)
  cosθ, Δsinθ = q.w, (q.x, q.y, q.z)
  Quaternion(cosθ, y_up_to_z_up(Point(Δsinθ))...)
end

y_up_to_z_up(tr::Transform; apply_rotation = true) = Transform(y_up_to_z_up(tr.translation), apply_rotation ? apply_y_up_to_z_up_rotation(tr.rotation) : remap_y_up_to_z_up(tr.rotation), y_up_to_z_up(tr.scaling))

function import_camera(gltf::GLTF.Object, node::GLTF.Node)
  transform = import_transform(node)
  camera = gltf.cameras[node.camera]
  (; orthographic, perspective) = camera
  if !isnothing(perspective)
    # Assume that the sensor size is standard,
    # since there is no sensor size information in there.
    sensor_size = CAMERA_SENSOR_SIZE_FULL_FRAME
    f = focal_length(perspective.yfov; aspect_ratio = perspective.aspectRatio, sensor_size = sensor_size[1])
    Camera(; focal_length = f, sensor_size, near_clipping_plane = perspective.znear, far_clipping_plane = perspective.zfar, transform)
  elseif !isnothing(orthographic)
    extent = (orthographic.xmag, orthographic.ymag)
    Camera(; extent, near_clipping_plane = orthographic.znear, far_clipping_plane = orthographic.zfar, transform)
  end
end

function import_camera(gltf::GLTF.Object)
  cameras = findall(x -> !isnothing(x.camera), collect(gltf.nodes))
  isempty(cameras) && error("No camera found in GLTF scene")
  length(cameras) > 1 && error("Multiple cameras found in GLTF scene")
  import_camera(gltf, gltf.nodes[only(cameras) - 1])
end

function Light{Float32}(gltf::GLTF.Object, node::GLTF.Node)
  tr = import_transform(node)
  position = apply_transform(zero(Vec3), tr)
  i = node.extensions["KHR_lights_punctual"]["light"]
  light = gltf.extensions["KHR_lights_punctual"]["lights"][i + 1]
  type = light_type(light["type"])
  color = Vec3(light["color"])
  intensity = light["intensity"]
  Light{Float32}(type, position, color, intensity)
end

function light_type(type::AbstractString)
  type == "point" && return LIGHT_TYPE_POINT
  type == "spot" && return LIGHT_TYPE_SPOT
  type == "direction" && return LIGHT_TYPE_DIRECTION
  error("Unknown light type `$type`")
end

function import_lights(gltf::GLTF.Object)
  lights = Light{Float32}[]
  !haskey(gltf.extensions, "KHR_lights_punctual")
  for node in gltf.nodes
    isnothing(node.extensions) && continue
    haskey(node.extensions, "KHR_lights_punctual") || continue
    push!(lights, Light{Float32}(gltf, node))
  end
  lights
end
