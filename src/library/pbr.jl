# https://google.github.io/filament/Filament.html#table_symbols
# v   | View unit vector
# l   | Incident light unit vector
# n   | Surface normal unit vector
# h   | Half unit vector between l and v
# f   | BRDF
# fd  | Diffuse component of a BRDF
# fᵣ  | Specular component of a BRDF
# α   | Roughness, remapped from using input perceptualRoughness
# σ   | Diffuse reflectance
# Ω   | Spherical domain
# f₀  | Reflectance at normal incidence
# f₉₀ | Reflectance at grazing angle

# https://google.github.io/filament/Filament.html#listing_speculard
specular_normal_distribution_ggx_fp32(α, n, h) = α^2/((π)F * ((n ⋅ h)^2 * (α^2 - 1) + 1)^2)

# https://google.github.io/filament/Filament.html#listing_speculardfp16
specular_normal_distribution_ggx_fp16(α, n, h) = min((α / (((n × h) ⋅ (n × h)) + ((n ⋅ h) * α)^2))^2 / Float16(π), floatmax(Float16))

# https://google.github.io/filament/Filament.html#listing_specularv
function specular_visibility_smith_ggx_correlated(α, n, v, l)
  α² = α^2
  ggx_v = (n ⋅ l) * sqrt((n ⋅ v)^2 * (1 - α²) + α²)
  ggx_l = (n ⋅ v) * sqrt((n ⋅ l)^2 * (1 - α²) + α²)
  0.5 / (ggx_v + ggx_l)
end

# https://google.github.io/filament/Filament.html#listing_approximatedspecularv
function specular_visibility_smith_ggx_correlated_fast(α, n, v, l)
  ggx_v = (n ⋅ l) * sqrt((n ⋅ v) * (1 - α) + α)
  ggx_l = (n ⋅ v) * sqrt((n ⋅ l) * (1 - α) + α)
  0.5 / (ggx_v + ggx_l)
end

pow5(x) = x * (x * x)^2
# https://google.github.io/filament/Filament.html#listing_specularf
fresnel_schlick(u, f₀, f₉₀) = f₀ + (f₉₀ .- f₀) * pow5(1 - u)

brdf_specular(α, n, h, v, l, u, f₀, f₉₀) = specular_normal_distribution_ggx_fp32(α, n, h) * specular_visibility_smith_ggx_correlated(α, n, v, l) * fresnel_schlick(u, f₀, f₉₀)

# https://google.github.io/filament/Filament.html#listing_diffusebrdf
# Note: this is not energy-conserving.
function brdf_diffuse_disney(α, n, v, l, h, f₀)
  f₉₀ = 0.5F + 2α * (l ⋅ h)^2
  light_scatter = fresnel_schlick(n ⋅ l, f₀, f₉₀)
  view_scatter = fresnel_schlick(n ⋅ v, f₀, f₉₀)
  light_scatter .* view_scatter ./ (π)F
end

# Parametrization as described in Section 4.8 of https://google.github.io/filament/Filament.html
struct BSDF{T<:Real}
  # For metallic materials, use values with a luminosity of 67% to 100% (170-255 sRGB).
  # For non-metallic materials, values should be an sRGB value in the range 50-240 (strict range) or 30-240 (tolerant range).
  # Should be devoid of lighting information.
  base_color::Vec{3,T}
  # 0 = dielectric, 1 = metallic. Values in-between should remain close to 0 or to 1.
  metallic::T
  roughness::T # perceptual roughness
  # Should be set to 127 sRGB (0.5 linear, 4% reflectance) if you cannot find a proper value. Do not use values under 90 sRGB (0.35 linear, 2% reflectance).
  # For metals, reflectance is ignored.
  reflectance::T
end

# https://google.github.io/filament/Filament.html#table_fnormalmetals
const METAL_COLORS = Dict{Symbol,Vec3}(
  :silver => (0.97, 0.96, 0.91),
  :aluminum => (0.91, 0.92, 0.92),
  :titanium => (0.76, 0.73, 0.69),
  :iron => (0.77, 0.78, 0.78),
  :platinum => (0.83, 0.81, 0.78),
  :gold => (1.00, 0.85, 0.57),
  :brass => (0.98, 0.90, 0.59),
  :copper => (0.97, 0.74, 0.62),
)

function scatter(bsdf::BSDF{T}, position, light_direction, normal, view) where {T}
  diffuse_color = (1 .- bsdf.metallic) .* bsdf.base_color
  roughness = max(bsdf.roughness, T(0.089))^2
  f₀ = T(0.16) * bsdf.reflectance^2 * (one(T) - bsdf.metallic) .+ bsdf.base_color .* bsdf.metallic
  f₉₀ = one(T)
  h = normalize(view - light_direction) / T(2)
  u = view ⋅ h
  specular = brdf_specular(roughness, normal, h, view, light_direction, u, f₀, f₉₀)
  diffuse = brdf_diffuse_disney(roughness, normal, view, light_direction, h, f₀)
  brdf = specular .* diffuse
  btdf = zero(T) # XXX
  brdf .* btdf
end

struct PointLight
  position::Vec3
  color::Vec3
  intensity::Float32
  attenuation::Float32
end

struct PBR{T} <: Material
  bsdf::BSDF{T}
  lights::PhysicalBuffer{PointLight} 
end

function pbr_vert(position, frag_position, frag_normal, index, (; data)::PhysicalRef{InvocationData})
  frag_position[] = data.vertex_locations[index]
  frag_normal[] = data.vertex_normals[index]
  position.xyz = world_to_screen_coordinates(frag_position, data)
end

function pbr_frag(::Type{T}, color, position, normal, (; data)::PhysicalRef{InvocationData}) where {T}
  (; camera) = data
  pbr = @load data.user_data::PBR{T}
  for light in pbr.lights
    light_direction = position - light.position
    view = normalize(position - camera.transform.translation)
    d² = distance2(position, light.position)
    color.rgb += scatter(pbr.bsdf, position, light_direction, normal, view) .* light.intensity .* light.attenuation/d² .* (normal ⋅ light_direction) .* light.color
  end
  color.rgb = clamp.(color.rgb, 0F, 1F)
  color.a = 1F
end
user_data(pbr::PBR, ctx) = pbr
interface(::PBR) = Tuple{Nothing, Nothing, Nothing}

function Program(::Type{PBR{T}}, device) where {T}
  vert = @vertex device pbr_vert(::Vec4::Output{Position}, ::Vec3::Output, ::Vec3::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device pbr_frag(
    ::Type{T},
    ::Vec4::Output,
    ::Vec3::Input,
    ::Vec3::Input,
    ::PhysicalRef{InvocationData}::PushConstant,
  )
  Program(vert, frag)
end
