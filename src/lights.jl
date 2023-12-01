@enum LightType::UInt32 begin
  LIGHT_TYPE_POINT = 1
  LIGHT_TYPE_SPOT = 2
  LIGHT_TYPE_DIRECTION = 3
end

struct Light
  type::LightType
  position::Point3f
  color::SVector{3,Float32}
  intensity::Float32
  attenuation::Float32
end

function intensity(light, position, normal)
  if light.type == LIGHT_TYPE_POINT
    d² = distance2(position, light.position)
    light.intensity .* light.attenuation/d² .* (normal ⋅ normalize(light.position - position))
  else
    0F
  end
end
