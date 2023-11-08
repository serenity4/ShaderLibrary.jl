struct Vertex{T}
  location::Vec3
  data::T
end
Vertex(location, data = nothing) = Vertex(vec3(location), data)

GeometryExperiments.location(vertex::Vertex) = vertex.location

struct Primitive{PT,VT}
  mesh::VertexMesh{UInt32,Vertex{VT},Vector{Vertex{VT}}}
  orientation::FaceOrientation
  "World-space transform."
  transform::Transform
  data::PT
  function Primitive{PT,VT}(mesh, orientation, transform, data) where {PT,VT}
    mesh = convert(VertexMesh{UInt32,Vertex{VT},Vector{Vertex{VT}}}, mesh)
    orientation = convert(FaceOrientation, orientation)
    transform = convert(Transform, transform)
    data = convert(PT, data)
    new{PT,VT}(mesh, orientation, transform, data)
  end
end

Primitive(mesh::VertexMesh{<:Any,Vertex{T}}, orientation::FaceOrientation; transform::Transform = Transform(), data = nothing) where {T} = Primitive{typeof(data),T}(mesh, orientation, transform, data)
function Primitive(encoding::MeshEncoding, vertices::AbstractVector{Vertex{VT}}, orientation, transform = Transform(), data::PT = nothing) where {VT,PT}
  encoding = convert(MeshEncoding{UInt32}, encoding)
  Primitive{PT,VT}(VertexMesh(encoding, vertices), orientation, transform, data)
end

struct Instance{IT,PT,VT,V<:AbstractVector{Primitive{PT,VT}}}
  primitives::V
  "World-space transform."
  transform::Transform
  data::IT
end

Instance(primitive::Primitive, data = nothing, transform = Transform()) = Instance(SA[primitive], transform, data)
Instance(primitives::AbstractVector{<:Primitive}, transform = Transform()) = Instance(primitives, transform, nothing)

Vk.FrontFace(primitive::Primitive) = primitive.orientation == FACE_ORIENTATION_COUNTERCLOCKWISE ? Vk.FRONT_FACE_COUNTER_CLOCKWISE : Vk.FRONT_FACE_CLOCKWISE

GeometryExperiments.MeshTopology(primitives::AbstractVector{<:Primitive}) = length(primitives) == 1 ? MeshTopology(primitives[1]) : MESH_TOPOLOGY_TRIANGLE_LIST
GeometryExperiments.MeshTopology(primitive::Primitive) = primitive.mesh.encoding.topology

Vk.PrimitiveTopology(primitive::Primitive) = vk_primitive_topology(primitive.mesh.encoding.topology)
function vk_primitive_topology(topology::MeshTopology)
  topology === MESH_TOPOLOGY_TRIANGLE_LIST && return Vk.PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
  topology === MESH_TOPOLOGY_TRIANGLE_STRIP && return Vk.PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP
  topology === MESH_TOPOLOGY_TRIANGLE_FAN && return Vk.PRIMITIVE_TOPOLOGY_TRIANGLE_FAN
  error("Unknown mesh topology `$topology`")
end

Vk.FrontFace(primitives::AbstractVector{<:Primitive}) = Vk.FrontFace(primitives[begin])
Vk.FrontFace(instance::Instance) = Vk.FrontFace(instance.primitives)
Vk.FrontFace(instances::AbstractVector{<:Instance}) = Vk.FrontFace(instances[begin])

Vk.PrimitiveTopology(primitives::AbstractVector{<:Primitive}) = length(primitives) == 1 ? vk_primitive_topology(primitives[begin]) : Vk.PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
Vk.PrimitiveTopology(instance::Instance) = Vk.PrimitiveTopology(instance.primitives)
Vk.PrimitiveTopology(instances::AbstractVector{<:Instance}) = Vk.PrimitiveTopology(instances[begin])

vertex_indices(primitive::Primitive) = primitive.mesh.encoding.indices
function vertex_indices(primitives::AbstractVector{<:Primitive})
  indices = UInt32[]
  offset = 0U
  topology = MeshTopology(primitives)
  for primitive in primitives
    encoding = reencode(primitive.mesh.encoding, topology)
    # Renumber all indices such that they are contiguous with the previous ones.
    for index in encoding.indices
      push!(indices, index + offset)
    end
    offset += maximum(encoding.indices)
  end
  indices
end
function DrawIndexed(primitive::Union{Primitive,AbstractVector{<:Primitive}})
  indices = vertex_indices(primitive)
  DrawIndexed(indices; vertex_offset = -Int32(minimum(indices)))
end
