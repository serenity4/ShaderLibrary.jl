struct Rectangle{VT,PT,V<:AbstractVector{VT}}
  geometry::Box{2,Float32}
  vertex_data::V
  primitive_data::PT
  Rectangle(geometry::Box, vertex_data::AbstractVector, primitive_data) = 
    new{eltype(vertex_data),typeof(primitive_data),typeof(vertex_data)}(geometry, vertex_data, primitive_data)
  Rectangle(geometry::Box, vertex_data::Nothing, primitive_data) = Rectangle(geometry, (@SVector fill(nothing, 4)), primitive_data)
  Rectangle(min, max, vertex_data::Union{AbstractVector,Nothing}, primitive_data) = Rectangle(Box{2,Float32}(min, max), vertex_data, primitive_data)
  Rectangle(semidiag::Point, vertex_data::Union{AbstractVector,Nothing}, primitive_data) = Rectangle(Box{2,Float32}(semidiag), vertex_data, primitive_data)
end

Primitive(rect::Rectangle, location) = Primitive(rect, Transform(translation = vec3(location)))
function Primitive(rect::Rectangle, transform::Transform = Transform())
  vertices = Vertex.(Vec2.(PointSet(rect.geometry).points), rect.vertex_data)
  Primitive(MeshEncoding(1:4), vertices, FACE_ORIENTATION_COUNTERCLOCKWISE, transform, rect.primitive_data)
end
