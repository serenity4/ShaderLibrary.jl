struct Rectangle{VT,PT,V<:AbstractVector{VT}}
  geometry::Box{2,Float32}
  location::Point2f
  vertex_data::V
  primitive_data::PT
  Rectangle(geometry::Box, location, vertex_data::AbstractVector, primitive_data) = 
    new{eltype(vertex_data),typeof(primitive_data),typeof(vertex_data)}(geometry, location, vertex_data, primitive_data)
  Rectangle(geometry::Box, location, vertex_data::Nothing, primitive_data) = Rectangle(geometry, location, (@SVector fill(nothing, 4)), primitive_data)
  Rectangle(min, max, location, vertex_data::Union{AbstractVector,Nothing}, primitive_data) = Rectangle(Box(min, max), location, vertex_data, primitive_data)
  Rectangle(semidiag::Point, location, vertex_data::Union{AbstractVector,Nothing}, primitive_data) = Rectangle(Box(semidiag), location, vertex_data, primitive_data)
end

function Primitive(rect::Rectangle)
  vertices = Vertex.(Vec2.(PointSet(rect.geometry).points), rect.vertex_data)
  transform = Transform(translation = vec3(rect.location))
  Primitive(TriangleStrip(1:4), vertices, FACE_ORIENTATION_COUNTERCLOCKWISE, transform, rect.primitive_data)
end
