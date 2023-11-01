@struct_hash_equal_isapprox struct Plane
  u::Vec3
  v::Vec3
  Plane(u, v) = new(normalize(convert(Vec3, u)), normalize(convert(Vec3, v)))
end

Plane(normal) = Plane(convert(Vec3, normal))
function Plane(normal::Vec3)
  iszero(normal) && return Plane(Vec3(1, 0, 0), Vec3(0, 1, 0))
  u = @ga 3 Vec3 normal::Vector × 1f0::e1
  iszero(u) && (u = @ga 3 Vec3 dual(normal::Vector × 1f0::e2))
  v = @ga 3 Vec3 dual(normal::Vector × u::Vector)
  Plane(u, v)
end

@struct_hash_equal_isapprox struct Rotation
  plane::Plane
  angle::Float32
end

Rotation(axis::Vec3) = Rotation(Plane(normalize(axis)), norm(axis))
Rotation() = Rotation(Plane(Vec3(0, 0, 1)), 0)

Base.inv(rot::Rotation) = @set rot.angle = -rot.angle
Base.iszero(rot::Rotation) = iszero(rot.angle)

function apply_rotation(p::Vec3, rotation::Rotation)
  # Define rotation bivector which encodes a rotation in the given plane by the specified angle.
  ϕ = @ga 3 Vec3 rotation.angle::Scalar ⟑ (rotation.plane.u::Vector ∧ rotation.plane.v::Vector)
  # Define rotation generator to be applied to perform the operation.
  Ω = @ga 3 Tuple exp((ϕ::Bivector) / 2f0::Scalar)
  @ga 3 Vec3 begin
    Ω::(Scalar, Bivector)
    inverse(Ω) ⟑ p::Vector ⟑ Ω
  end
end

@struct_hash_equal_isapprox Base.@kwdef struct Transform
  translation::Vec3 = (0, 0, 0)
  rotation::Rotation = Rotation()
  scaling::Vec3 = (1, 1, 1)
end

function apply_transform(p::Vec3, (; translation, rotation, scaling)::Transform)
  apply_rotation(p .* scaling, rotation) + translation
end

Base.inv((; translation, rotation, scaling)::Transform) = Transform(-translation, inv(rotation), inv.(scaling))

"""
Pinhole camera with a hole that is infinitely small.

Does not produce blur, which may make it appear somewhat unrealistic; the image is perfectly sharp. This behavior is the same as used in most 3D engines/games.

The image plane is taken to be z = 0.
The optical center is placed a z = focal_length.

Projection through the camera yields a z-component which describes how far
or near the camera the point was. The resulting value is between 0 and 1,
where 0 corresponds to a point on the near clipping plane, and 1 to one on
the far clipping plane.
"""
@struct_hash_equal_isapprox Base.@kwdef struct Camera
  focal_length::Float32 = 1.0
  near_clipping_plane::Float32 = 0
  far_clipping_plane::Float32 = 1
  transform::Transform = Transform()
end

function project(p::Vec3, camera::Camera)
  p = apply_transform(p, inv(camera.transform))
  f = camera.focal_length
  z = remap(p.z, camera.near_clipping_plane, camera.far_clipping_plane, 0F, 1F)
  Vec3(p.x/f, p.y/f, z)
end
