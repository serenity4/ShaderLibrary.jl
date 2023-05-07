struct Primitive{PT,VT,E<:IndexEncoding,V<:AbstractVector{VT}}
  encoding::E
  orientation::FaceOrientation
  data::PT
  vertex_data::V
end

Primitive(encoding::IndexEncoding, orientation::FaceOrientation, vertex_data::AbstractVector) = Primitive(encoding, orientation, nothing, vertex_data)

struct Instance{IT,PT,VT,P<:Primitive{PT,VT},V<:AbstractVector{P}}
  data::IT
  primitives::V
end

Instance(primitive::Primitive, data = nothing) = Instance(data, SA[primitive])
Instance(primitives::AbstractVector{<:Primitive}) = Instance(nothing, primitives)

Vk.FrontFace(primitive::Primitive) = primitive.orientation == FACE_ORIENTATION_COUNTERCLOCKWISE ? Vk.FRONT_FACE_COUNTER_CLOCKWISE : Vk.FRONT_FACE_CLOCKWISE

function Vk.PrimitiveTopology(primitive::Primitive{T,VT,E}) where {T,VT,E}
  E <: LineStrip && return Vk.PRIMITIVE_TOPOLOGY_LINE_STRIP
  E <: LineList && return Vk.PRIMITIVE_TOPOLOGY_LINE_LIST
  E <: TriangleStrip && return Vk.PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP
  E <: TriangleList && return Vk.PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
  E <: TriangleFan && return Vk.PRIMITIVE_TOPOLOGY_TRIANGLE_FAN
  error("Unknown primitive topology for index encoding type $E")
end

Vk.FrontFace(primitives::AbstractVector{Primitive}) = Vk.FrontFace(primitives[begin])
Vk.FrontFace(instance::Instance) = Vk.FrontFace(instance.primitives)
Vk.FrontFace(instances::AbstractVector{Instance}) = Vk.FrontFace(instances[begin])

Vk.PrimitiveTopology(primitives::AbstractVector{Primitive}) = Vk.PrimitiveTopology(primitives[begin])
Vk.PrimitiveTopology(instance::Instance) = Vk.PrimitiveTopology(instance.primitives)
Vk.PrimitiveTopology(instances::AbstractVector{Instance}) = Vk.PrimitiveTopology(instances[begin])

DrawIndexed(primitive::Primitive) = DrawIndexed(primitive.encoding.indices)
