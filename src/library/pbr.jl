# https://google.github.io/filament/Filament.html#table_symbols
# v   | View unit vector
# l   | Incident light unit vector
# n   | Surface normal unit vector
# h   | Half unit vector between l and v
# f   | BRDF
# fd  | Diffuse component of a BRDF
# fᵣ  | Specular component of a BRDF
# α   | Roughness, remapped from perceptual roughness
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
  0.5F / (ggx_v + ggx_l)
end

# https://google.github.io/filament/Filament.html#listing_approximatedspecularv
function specular_visibility_smith_ggx_correlated_fast(α, n, v, l)
  ggx_v = (n ⋅ l) * sqrt((n ⋅ v) * (1 - α) + α)
  ggx_l = (n ⋅ v) * sqrt((n ⋅ l) * (1 - α) + α)
  0.5 / (ggx_v + ggx_l)
end

pow5(x) = x * (x * x)^2
# https://google.github.io/filament/Filament.html#listing_specularf
fresnel_schlick(cosθ, f₀, f₉₀) = f₀ + (f₉₀ .- f₀) * pow5(1 - cosθ)

brdf_specular(α, n, h, v, l, cosθ, f₀, f₉₀) = specular_normal_distribution_ggx_fp32(α, n, h) * specular_visibility_smith_ggx_correlated(α, n, v, l) * fresnel_schlick(cosθ, f₀, f₉₀)

# https://google.github.io/filament/Filament.html#listing_diffusebrdf
# Note: this is not energy-conserving.
function brdf_diffuse_disney(α, n, v, l, h, f₀)
  f₉₀ = 0.5F + 2α * (l ⋅ h)^2
  light_scatter = fresnel_schlick(n ⋅ l, f₀, f₉₀)
  view_scatter = fresnel_schlick(n ⋅ v, f₀, f₉₀)
  light_scatter .* view_scatter ./ (π)F
end

brdf_diffuse_lambertian(albedo) = albedo / (π)F

# Parametrization as described in Section 4.8 of https://google.github.io/filament/Filament.html
struct BSDF{T<:Real}
  # For metallic materials, use values with a luminosity of 67% to 100% (170-255 sRGB).
  # For non-metallic materials, values should be an sRGB value in the range 50-240 (strict range) or 30-240 (tolerant range).
  # Should be devoid of lighting information.
  base_color::SVector{3,T}
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

function scattering(bsdf::BSDF{T}, position, light::Light, normal, view) where {T}
  light_direction = normalize(light.position - position)
  diffuse_color = (1 .- bsdf.metallic) .* bsdf.base_color
  roughness = max(bsdf.roughness, T(0.089))^2
  f₀ = T(0.16) * bsdf.reflectance^2 * (one(T) - bsdf.metallic) .+ bsdf.base_color .* bsdf.metallic
  f₉₀ = one(T)
  h = normalize(view + light_direction)
  cosθ = view ⋅ h
  cosθ < zero(T) && return zero(Point{3,T})
  specular = brdf_specular(roughness, normal, h, view, light_direction, cosθ, f₀, f₉₀)
  diffuse = brdf_diffuse_lambertian(bsdf.base_color)
  # diffuse = brdf_diffuse_disney(roughness, normal, view, light_direction, h, f₀)
  brdf = specular .* diffuse
  btdf = one(T) # XXX
  brdf .* btdf
end

function scatter_light_source(bsdf::BSDF, position, normal, light::Light, view)
  factor = scattering(bsdf, position, light, normal, view)
  light_direction = normalize(light.position - position)
  sₗ = shape_factor(normal, light_direction)
  factor .* radiance(light, position) .* sₗ
end

function scatter_light_sources(bsdf::BSDF{T}, position, normal, lights, camera::Camera) where {T}
  res = zero(Point{3,T})
  view = normalize(camera.transform.translation.vec - position)
  for light in lights
    res += scatter_light_source(bsdf, position, normal, light, view)
  end
  res
end

struct PBR{T} <: Material
  bsdf::BSDF{T}
  lights::PhysicalBuffer{Light{T}}
end

function pbr_vert(position, frag_position, frag_normal, index, (; data)::PhysicalRef{InvocationData})
  frag_position[] = data.vertex_locations[index + 1U]
  frag_normal[] = data.vertex_normals[index + 1U]
  position.xyz = world_to_screen_coordinates(frag_position, data)
end

function pbr_frag(::Type{T}, color, position, normal, (; data)::PhysicalRef{InvocationData}) where {T}
  (; camera) = data
  pbr = @load data.user_data::PBR{T}
  # scattered = scatter_light_sources(pbr.bsdf, position, normal, pbr.lights, camera)
  scattered = compute_lighting(pbr.bsdf, position, normal, pbr.lights, camera)
  color.rgb = clamp.(Vec3(scattered), 0F, 1F)
  color.a = 1F
end
user_data(pbr::PBR, ctx) = pbr
interface(::PBR) = Tuple{Nothing, Nothing, Nothing}

function Program(::Type{PBR{T}}, device) where {T}
  vert = @vertex device pbr_vert(::Vec4::Output{Position}, ::Vec3::Output, ::Vec3::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device pbr_frag(
    ::Type{T},
    ::Vec4::Output,
    ::Point3f::Input,
    ::SVector{3,Float32}::Input,
    ::PhysicalRef{InvocationData}::PushConstant,
  )
  Program(vert, frag)
end




# ----------------------------------
# https://learnopengl.com/PBR/Theory

"""
Approximates the amount the surface's microfacets are aligned to the halfway vector, influenced by the roughness of the surface.

- `α`: roughness of the surface
- `sₕ`: shape factor between the halfway direction and the surface normal.
"""
microfacet_scattering(α, sₕ) = microfacet_scattering_trowbridge_reitz_ggx(α, sₕ)

function microfacet_scattering_trowbridge_reitz_ggx(α, sₕ)
  α² = α^2
  α² / ((π)F * (sₕ^2 * (α² - 1) + 1)^2)
end

"""
Describes the self-shadowing property of the microfacets. When a surface is relatively rough, the surface's microfacets can overshadow other microfacets reducing the light the surface reflects.

- `k`: remapped roughness, depending on whether direct or image-based lighting is used.
- `s`: shape factor between a direction of interest and the surface normal.
"""
microfacet_occlusion_factor(k, s) = microfacet_occlusion_factor_schlick_ggx(k, s)
microfacet_occlusion_factor_schlick_ggx(k, s) = s / lerp(one(k), s, k)
function microfacet_occlusion_factor(k, sᵥ, sₗ)
  fᵥ = microfacet_occlusion_factor(k, sᵥ)
  fₗ = microfacet_occlusion_factor(k, sₗ)
  fᵥ * fₗ
end

remap_roughness_direct_lighting(α) = (α + 1)^2/8
remap_roughness_image_based_lighting(α) = α^2/2

"""
Describes the ratio of surface reflection at different surface angles.

Uses the Fresnel equation, which interpolates between an incident factor f₀ and a tangent factor f₉₀ (often taken to be zero - no light reflected for a tangential ray).
"""
surface_reflection(s, f₀) = surface_reflection_fresnel(s, f₀)
surface_reflection_fresnel(s, f₀) = lerp(one(s), pow5(clamp(one(s) - s, zero(s), one(s))), f₀)

"""
- `α`: roughness factor.
- `sᵥ`: shape factor between surface normal and view direction.
- `sₗ`: shape factor between surface normal and light direction.
- `sₕ`: half-way shape factor between view direction and light direction.
- `f₀`: reflectivity at incidence, based on indices of refraction (1 = reflects all light, 0 = absorbs all light).
"""
function cook_torrance_specular_brdf(α, sᵥ, sₗ, sₕ)
  # Use `α^2` as roughness value to give more realistic results.
  d = microfacet_scattering(α^2, sₕ)
  k = remap_roughness_direct_lighting(α) # change for image-based lighting
  f = microfacet_occlusion_factor(k, sᵥ, sₗ)
  d * f / (4 * sᵥ * sₗ + convert(typeof(α), 0.0001))
end

shape_factor(x::AbstractVector{T}, y::AbstractVector{T}) where {T} = max(x ⋅ y, zero(T))

function compute_lighting(bsdf::BSDF{T}, position, normal, light::Light, view) where {T}
  sᵥ = shape_factor(normal, view)
  light_direction = normalize(light.position - position)
  sₗ = shape_factor(normal, light_direction)
  halfway_direction = normalize(light_direction + view)
  sₕ = shape_factor(normal, halfway_direction)
  # f₀ = T(0.16) * bsdf.reflectance^2 * (one(T) - bsdf.metallic) .+ bsdf.base_color .* bsdf.metallic
  f₀ = lerp(@SVector(ones(T, 3)), bsdf.base_color, bsdf.metallic)
  α = bsdf.roughness
  specular = cook_torrance_specular_brdf(bsdf.roughness, sᵥ, sₗ, sₕ)
  kₛ = surface_reflection(max(halfway_direction ⋅ view, zero(T)), f₀)
  diffuse = kₛ .* brdf_diffuse_lambertian(bsdf.base_color)
  kd = (@SVector(ones(T, 3)) .- kₛ) .* (one(T) - bsdf.metallic)
  brdf = kₛ .* specular .+ kd .* diffuse
  btdf = one(T)
  scattering = brdf .* btdf
  radiance(light, position) .* sₗ .* scattering
end

function compute_lighting(bsdf::BSDF{T}, position, normal, lights, camera::Camera) where {T}
  res = zero(Point{3,T})
  view = normalize(camera.transform.translation.vec - position)
  for light in lights
    res += compute_lighting(bsdf, position, normal, light, view)
  end
  res
end

# ----------------------------------
