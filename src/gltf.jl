function Transform(node::GLTF.Node)
  rotation = Rotation(Vec4(node.rotation))
  translation = Vec3(node.translation)
  scaling = Vec3(node.scale)
  Transform(; translation, rotation, scaling)
end

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

function read_camera(gltf::GLTF.Object)
  cameras = findall(x -> !isnothing(x.camera), collect(gltf.nodes))
  isempty(cameras) && error("No camera found in GLTF scene")
  length(cameras) > 1 && error("Multiple cameras found in GLTF scene")
  Camera(gltf, gltf.nodes[only(cameras) - 1])
end

function Light(gltf::GLTF.Object, node::GLTF.Node)
  tr = Transform(node)
  position = apply_transform(zero(Vec3), tr)
  i = node.extensions["KHR_lights_punctual"]["light"]
  light = gltf.extensions["KHR_lights_punctual"]["lights"][i + 1]
  type = light_type(light["type"])
  color = Vec3(light["color"])
  intensity = light["intensity"]
  # XXX: What value to put here?
  attenuation = 1.0
  Light(type, position, color, intensity, attenuation)
end

function light_type(type::AbstractString)
  type == "point" && return LIGHT_TYPE_POINT
  type == "spot" && return LIGHT_TYPE_SPOT
  type == "direction" && return LIGHT_TYPE_DIRECTION
  error("Unknown light type `$type`")
end

function read_lights(gltf::GLTF.Object)
  lights = Light[]
  !haskey(gltf.extensions, "KHR_lights_punctual")
  for node in gltf.nodes
    isnothing(node.extensions) && continue
    haskey(node.extensions, "KHR_lights_punctual") || continue
    push!(lights, Light(gltf, node))
  end
  lights
end
