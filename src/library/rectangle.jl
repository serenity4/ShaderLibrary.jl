struct Rectangle
  color::Vec3
  geometry::Box
  location::Point2f
  Rectangle(color, geometry::Box, location) = new(color, geometry, location)
  Rectangle(min, max, location, color) = Rectangle(color, box(min, max), location)
  Rectangle(semidiag, location, color) = Rectangle(color, Box(Scaling(semidiag...)), location)
end

function Primitive(rect::Rectangle)
  vertices = PosColor.(Vec2.(PointSet(rect.geometry, Point2f).points .+ Ref(rect.location)), Ref(rect.color))
  Primitive(TriangleStrip(1:4), FACE_ORIENTATION_COUNTERCLOCKWISE, vertices)
end
