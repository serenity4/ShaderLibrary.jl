const CAMERA_SENSOR_SIZE_FULL_FRAME = (0.036, 0.024)

"""
Pinhole camera with a hole that is infinitely small.

By default (no transform applied), the camera looks downward along -Z with +X on the right and +Y up.

Pinhole camera models do not produce blur, which may make them appear somewhat unrealistic; the image is perfectly sharp. This behavior is the same as used in most 3D engines/games.

The image plane is taken to be `z = 0`.
The optical center is placed a `z = -focal_length` for perspective projections.

Projection through the camera yields a z-component which describes how far
from the camera the point was. The resulting value is between 0 and 1,
where 0 corresponds to a point on the near clipping plane, and 1 to one on
the far clipping plane.
"""
@struct_hash_equal_isapprox Base.@kwdef struct Camera
  "Focal length (zero for an orthographic camera)."
  focal_length::Float32 = 0.0
  "Sensor size, in meters. Ignored for orthographic projections."
  sensor_size::NTuple{2, Float32} = CAMERA_SENSOR_SIZE_FULL_FRAME
  """
  Extent of the camera on the X and Y axes for orthographic projections.

  Ignored for perspective projections.
  """
  extent::NTuple{2, Float32} = (2, 2)
  near_clipping_plane::Float32 = 0
  far_clipping_plane::Float32 = 100
  transform::Transform{3,Float32,Quaternion{Float32}} = Transform{3,Float32}()
end

aspect_ratio(camera::Camera) = aspect_ratio(camera.sensor_size)

"Get the focal length of the camera (in no specific unit)."
focal_length(camera::Camera) = camera.focal_length
focal_length(field_of_view; aspect_ratio = 1, sensor_size = CAMERA_SENSOR_SIZE_FULL_FRAME[1]) = 1/max(aspect_ratio, 1) * sensor_size/2tan(field_of_view/2)

horizontal_field_of_view(camera::Camera; aspect_ratio = aspect_ratio(camera)) = horizontal_field_of_view(camera.focal_length; aspect_ratio, sensor_size = camera.sensor_size[1])
horizontal_field_of_view(focal_length; aspect_ratio = 1, sensor_size = CAMERA_SENSOR_SIZE_FULL_FRAME[1]) = 2atan(sensor_size/2focal_length)

vertical_field_of_view(camera::Camera; aspect_ratio = aspect_ratio(camera)) = vertical_field_of_view(camera.focal_length; aspect_ratio, sensor_size = camera.sensor_size[2])
vertical_field_of_view(focal_length; aspect_ratio = 1, sensor_size = CAMERA_SENSOR_SIZE_FULL_FRAME[2]) = 2atan(sensor_size/2focal_length)

field_of_view(camera::Camera; aspect_ratio = aspect_ratio(camera)) = field_of_view(camera.focal_length; aspect_ratio, camera.sensor_size)
function field_of_view(focal_length; sensor_size = CAMERA_SENSOR_SIZE_FULL_FRAME, aspect_ratio = aspect_ratio(sensor_size))
  hfov = horizontal_field_of_view(focal_length; aspect_ratio, sensor_size = sensor_size[1])
  vfov = vertical_field_of_view(focal_length; aspect_ratio, sensor_size = sensor_size[2])
  (hfov, vfov)
end

isorthogonal(camera::Camera) = iszero(camera.focal_length)

"""
Project the point `p` through the given `camera`, computing its depth in the resulting Z coordinate.

The X and Y coordinates describe the location of the projected point in the (infinite) 2D projection plane. The Z coordinate is a type of depth value, computed according to `near_clipping_plane` and `far_clipping_plane`.

The depth value is a normalized distance from the projection plane. The applied normalization depends on the values of `near_clipping_plane` and `far_clipping_plane`. Any distance lesser than `near_clipping_plane` will be lesser than 0, and any distance greater than `far_clipping_plane` will be greater than 1.

The following transformations are performed on the point:
- 3D world space to camera local space: the camera transform (if there is one) will be inversely applied to the point, such that the point is represented as seen from the camera's perspective.
- Camera local space to 2D screen space: now that the camera and the point use the same coordinate system, the X and Y coordinates are projected on the image plane. For orthographic projections, the focal plane is infinite and located at `z = 0`.

A focal length of zero (default) is taken to perform orthographic projections, while a nonzero focal length will be taken to perform perspective projections.
"""
function project(p::Vec3, camera::Camera)
  isorthogonal(camera) && return orthogonal_projection(p, camera)
  perspective_projection(p, camera)
end

"""
Assuming the camera is rotated 180° in the ZY plane, perform the inverse rotation.

This hardcoded transform allows to use an +X right, +Y up right-handed coordinate system,
along with a positive depth value. Without this transform, either +X right/+Y down must be used, or the computed Z value results in an opposite of the depth, which is not as convenient for graphics APIs.
"""
apply_fixed_camera_transform_inverse(p::Vec3) = Vec3(p.x, -p.y, -p.z)

"""
Perform the perspective projection of `p` through the `camera`.
"""
function perspective_projection(p::Vec3, camera::Camera)
  # 3D world space -> camera local space.
  p = apply_transform_inverse(p, camera.transform)
  p = apply_fixed_camera_transform_inverse(p)
  depth = remap(p.z, camera.near_clipping_plane, camera.far_clipping_plane, 0F, 1F)
  sx, sy = perspective_projection_scaling(camera, p)
  p′ = Vec3(p.x * sx, p.y * sy, depth)
  project_onto_sensor(p′, camera)
end

function project_onto_sensor(p, camera::Camera)
  (; sensor_size) = camera
  ar = aspect_ratio(camera)
  limit = ifelse(ar ≥ 1, sensor_size[2], sensor_size[1])
  magnify = remap(-limit/2F, limit/2F, -1F, 1F)
  Vec3(magnify(p.x), magnify(p.y), p.z)
end

function projection_scaling(camera::Camera, p)
  isorthogonal(camera) && return orthogonal_projection_scaling(camera)
  perspective_projection_scaling(camera, p)
end

orthogonal_projection_scaling(camera::Camera) = 2F ./ camera.extent
perspective_projection_scaling(camera::Camera, p) = ntuple(_ -> camera.focal_length/p.z, 2)

"""
Perform the orthogonal projection of `p` through the `camera`.
"""
function orthogonal_projection(p::Vec3, camera::Camera)
  # 3D world space -> camera local space.
  # Only the rotation and scaling are applied, as the orthogonal projection
  # is invariant with respect to camera translation.
  p = apply_rotation(p, inv(camera.transform.rotation))
  p = apply_scaling(p, inv(camera.transform.scaling))
  p = apply_fixed_camera_transform_inverse(p)
  depth = remap(p.z, camera.near_clipping_plane, camera.far_clipping_plane, 0F, 1F)
  sx, sy = orthogonal_projection_scaling(camera)
  p′ = typeof(p)(p.x * sx, p.y * sy, depth)
end

"""
Return a cropping factor in ]0, 1] along X and Y axes corresponding to how much
cropping is needed to fit the target `aspect_ratio` into the camera sensor.
"""
function cropping_factor(camera::Camera, ar)
  effective_ar = ar/aspect_ratio(camera)
  xcrop = min(one(ar), effective_ar)
  ycrop = min(one(ar), one(ar)/effective_ar)
  (xcrop, ycrop)
end

function screen_semidiagonal(aspect_ratio::Number)
  xmax = max(one(aspect_ratio), aspect_ratio)
  ymax = max(one(aspect_ratio), one(aspect_ratio)/aspect_ratio)
  (xmax, ymax)
end
screen_box(aspect_ratio::Number) = Box(Point(screen_semidiagonal(aspect_ratio)...))
screen_box(color::Resource) = screen_box(aspect_ratio(color))
