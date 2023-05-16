struct Primitive{PT,VT,M<:TriangleMesh{<:Any,VT}}
  mesh::M
  orientation::FaceOrientation
  "World-space transform."
  transform::Transform
  data::PT
end

Primitive(encoding::IndexEncoding, vertices, orientation, transform = Transform(), data = nothing) = Primitive(TriangleMesh(encoding, vertices), orientation, transform, data)

struct Instance{IT,PT,VT,P<:Primitive{PT,VT},V<:AbstractVector{P}}
  primitives::V
  "World-space transform."
  transform::Transform
  data::IT
end

Instance(primitive::Primitive, data = nothing, transform = Transform()) = Instance(SA[primitive], transform, data)
Instance(primitives::AbstractVector{<:Primitive}, transform = Transform()) = Instance(primitives, transform, nothing)

Vk.FrontFace(primitive::Primitive) = primitive.orientation == FACE_ORIENTATION_COUNTERCLOCKWISE ? Vk.FRONT_FACE_COUNTER_CLOCKWISE : Vk.FRONT_FACE_CLOCKWISE

function Vk.PrimitiveTopology(primitive::Primitive)
  E = typeof(primitive.mesh.indices)
  E <: LineStrip && return Vk.PRIMITIVE_TOPOLOGY_LINE_STRIP
  E <: LineList && return Vk.PRIMITIVE_TOPOLOGY_LINE_LIST
  E <: TriangleStrip && return Vk.PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP
  E <: TriangleList && return Vk.PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
  E <: TriangleFan && return Vk.PRIMITIVE_TOPOLOGY_TRIANGLE_FAN
  error("Unknown primitive topology for index encoding type $E")
end

Vk.FrontFace(primitives::AbstractVector{<:Primitive}) = Vk.FrontFace(primitives[begin])
Vk.FrontFace(instance::Instance) = Vk.FrontFace(instance.primitives)
Vk.FrontFace(instances::AbstractVector{<:Instance}) = Vk.FrontFace(instances[begin])

Vk.PrimitiveTopology(primitives::AbstractVector{<:Primitive}) = Vk.PrimitiveTopology(primitives[begin])
Vk.PrimitiveTopology(instance::Instance) = Vk.PrimitiveTopology(instance.primitives)
Vk.PrimitiveTopology(instances::AbstractVector{<:Instance}) = Vk.PrimitiveTopology(instances[begin])

vertex_indices(primitive::Primitive) = foldl(append!, primitive.mesh.indices.indices; init = UInt32[])
function vertex_indices(primitives::AbstractVector{<:Primitive})
  indices = UInt32[]
  offset = 0U
  for primitive in primitives
    primitive_indices = vertex_indices(primitive)
    for index in primitive_indices
      push!(indices, index + offset)
    end
    offset += maximum(primitive_indices)
  end
  indices
end
DrawIndexed(primitive::Primitive) = DrawIndexed(vertex_indices(primitive))
DrawIndexed(primitives::AbstractVector{<:Primitive}) = DrawIndexed(vertex_indices(primitives))
