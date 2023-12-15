function import_mesh(gltf::GLTF.Object, node::GLTF.Node)
  mesh = VertexMesh(gltf, node)
  y_up_to_z_up!(mesh)
end

function import_mesh(gltf::GLTF.Object)
  scene = gltf.scenes[gltf.scene]
  mesh_indices = findall(x -> !isnothing(x.mesh), collect(gltf.nodes))
  isempty(mesh_indices) && error("No mesh found.")
  length(mesh_indices) > 1 && error("More than one mesh found.")
  i = only(mesh_indices)
  node = gltf.nodes[scene.nodes[i]]
  import_mesh(gltf, node)
end

import_transform(node::GLTF.Node) = y_up_to_z_up(Transform(node))

"Convert from a convention of +Y up to +Z up, assuming both are right-handed."
function y_up_to_z_up end

y_up_to_z_up(p::Point{3}) = Point(p[1], -p[3], p[2])

function y_up_to_z_up!(mesh::VertexMesh)
  mesh.vertex_locations .= y_up_to_z_up.(mesh.vertex_locations)
  mesh
end

y_up_to_z_up(tr::Translation) = Translation(y_up_to_z_up(tr.vec))
function y_up_to_z_up(sc::Scaling)
  (sx, sy, sz) = sc.vec
  Scaling(sx, sz, sy)
end
function y_up_to_z_up(q::Quaternion)
  cosθ, Δsinθ = q.w, (q.x, q.y, q.z)
  Quaternion(cosθ, y_up_to_z_up(Point(Δsinθ))...)
end

y_up_to_z_up(tr::Transform) = Transform(y_up_to_z_up(tr.translation), y_up_to_z_up(tr.rotation), y_up_to_z_up(tr.scaling))

function Camera(gltf::GLTF.Object, node::GLTF.Node)
  transform = Transform(node)
  camera = gltf.cameras[node.camera]
  (; orthographic, perspective) = camera
  if !isnothing(perspective)
    Camera(near_clipping_plane = perspective.znear, far_clipping_plane = perspective.zfar; transform)
  elseif !isnothing(orthographic)
    Camera(near_clipping_plane = orthographic.znear, far_clipping_plane = orthographic.zfar; transform)
  end
end

function import_camera(gltf::GLTF.Object)
  cameras = findall(x -> !isnothing(x.camera), collect(gltf.nodes))
  isempty(cameras) && error("No camera found in GLTF scene")
  length(cameras) > 1 && error("Multiple cameras found in GLTF scene")
  Camera(gltf, gltf.nodes[only(cameras) - 1])
end

function Light{Float32}(gltf::GLTF.Object, node::GLTF.Node)
  tr = import_transform(node)
  position = apply_transform(zero(Point3f), tr)
  i = node.extensions["KHR_lights_punctual"]["light"]
  light = gltf.extensions["KHR_lights_punctual"]["lights"][i + 1]
  type = light_type(light["type"])
  color = Point3f(light["color"])
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
