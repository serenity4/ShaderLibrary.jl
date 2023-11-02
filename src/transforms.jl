@struct_hash_equal_isapprox struct Plane
  u::Vec3
  v::Vec3
  Plane(u, v) = new(normalize(convert(Vec3, u)), normalize(convert(Vec3, v)))
end

Plane(coords::Real...) = Plane(coords)
Plane(normal) = Plane(convert(Vec3, normal))
function Plane(normal::Vec3)
  iszero(normal) && return Plane((1, 0, 0), (0, 1, 0))
  u = @ga 3 Vec3 normal::Vector × 1f0::e1
  iszero(u) && (u = @ga 3 Vec3 dual(normal::Vector × 1f0::e2))
  v = @ga 3 Vec3 dual(normal::Vector × u::Vector)
  Plane(u, v)
end

@struct_hash_equal_isapprox struct Rotation
  quaternion::Vec4
end

function Rotation(plane::Plane, angle::Real)
  # Define rotation bivector which encodes a rotation in the given plane by the specified angle.
  ϕ = @ga 3 Vec3 angle::0 ⟑ (plane.u::1 ∧ plane.v::1)
  # Define rotation generator to be applied to perform the operation.
  Ω = @ga 3 Vec4 exp((ϕ::2) / 2f0::0)::(0 + 2)
  Rotation(Ω)
end

Rotation(axis::Vec3) = Rotation(Plane(normalize(axis)), norm(axis))
Rotation() = Rotation(Plane(Vec3(0, 0, 1)), 0)

Base.inv(rot::Rotation) = Rotation(@ga 3 Vec4 inverse(rot.quaternion::(0 + 2))::(0 + 2))
Base.iszero(rot::Rotation) = isone(rot.quaternion[1])

function apply_rotation(p::Vec3, rotation::Rotation)
  Ω = rotation.quaternion
  @ga 3 Vec3 begin
    Ω::(0 + 2)
    inverse(Ω) ⟑ p::1 ⟑ Ω
  end
end

struct Degree end
Base.:(*)(x, ::Degree) = deg2rad(x)
const ° = Degree()

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
  far_clipping_plane::Float32 = 100
  transform::Transform = Transform()
end

function project(p::Vec3, camera::Camera)
  # 3D world space -> camera local space.
  p = apply_transform(p, inv(camera.transform))

  # Camera local space -> 2D screen space.
  f = camera.focal_length
  x, y = p.x/f, p.y/f

  # Even though we lose a dimension, we keep a Z coordinate to encode something else: the depth,
  # or abstract distance at which the object is from the camera.
  # The camera is looking down, meaning that the depth value of an object will be along the -Z axis of the camera, so we negate the Z coordinate.
  z = -p.z

  # We want to encode the depth between 0 and 1, such that device coordinates may use it for depth clipping.
  # For this, we remap from [near_clipping_plane; far_clipping_plane] to [0; 1].
  z = remap(z, camera.near_clipping_plane, camera.far_clipping_plane, 0F, 1F)

  Vec3(x, y, z)
end
