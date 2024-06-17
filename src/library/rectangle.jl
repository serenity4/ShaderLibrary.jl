struct Rectangle{VT,PT,V<:Optional{AbstractVector{VT}}}
  geometry::Box{2,Float32}
  vertex_data::V
  primitive_data::PT
  Rectangle(geometry::Box, vertex_data::AbstractVector, primitive_data) =
    new{eltype(vertex_data),typeof(primitive_data),typeof(vertex_data)}(geometry, vertex_data, primitive_data)
  Rectangle(geometry::Box, vertex_data::Nothing, primitive_data) =
    new{Nothing,typeof(primitive_data),typeof(vertex_data)}(geometry, vertex_data, primitive_data)
  Rectangle(min, max, vertex_data::Union{AbstractVector,Nothing}, primitive_data) = Rectangle(Box{2,Float32}(min, max), vertex_data, primitive_data)
  Rectangle(semidiag::Point, vertex_data::Union{AbstractVector,Nothing}, primitive_data) = Rectangle(Box{2,Float32}(semidiag), vertex_data, primitive_data)
end

Primitive(rect::Rectangle, location) = Primitive(rect, Transform(translation = Translation(point3(location))))
function Primitive(rect::Rectangle, transform::Transform = Transform())
  mesh = VertexMesh(1:4, PointSet(rect.geometry); rect.vertex_data)
  Primitive(mesh, FACE_ORIENTATION_COUNTERCLOCKWISE; transform, data = rect.primitive_data)
end

function Rectangle(color::Resource; primitive_data = nothing)
  screen = screen_box(color)
  set = PointSet(screen)
  directions = [Point3f(p..., -1F) for p in set]
  Rectangle(screen, directions, primitive_data)
end

function Rectangle(color::Resource, camera::Camera; primitive_data = nothing)
  (; sensor_size) = camera
  crop = cropping_factor(camera, aspect_ratio(color))
  screen = screen_box(color)
  set = PointSet(screen)
  directions = [begin
    # Define p′ as one of the corners of the image plane,
    # located at z = -focal_length and whose extent in the
    # XY plane is that of the sensor.
    xy = sign.(p) .* sensor_size ./ 2 .* crop
    p′ = Point3f(xy..., -camera.focal_length)
    apply_rotation(p′, camera.transform.rotation)
  end for p in set]
  Rectangle(screen, directions, primitive_data)
end
