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
  transform::Transform{3,Float32,Quaternion{Float32}} = Transform{3,Float32}()
end

function project(p::Vec3, camera::Camera)
  # 3D world space -> camera local space.
  p = apply_transform_inverse(p, camera.transform)

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
