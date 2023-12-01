@enum LightType::UInt32 begin
  LIGHT_TYPE_POINT = 1
  LIGHT_TYPE_SPOT = 2
  LIGHT_TYPE_DIRECTION = 3
end

struct Light{T}
  type::LightType
  position::Point{3,T}
  color::SVector{3,T}
  intensity::T
end

function radiance(light::Light{T}, at::Point{3}) where {T}
  if light.type == LIGHT_TYPE_POINT
    d² = distance2(at, light.position)
    attenuation = light.intensity / d²
    light.color .* attenuation
  else
    zero(SVector{3,T})
  end
end
