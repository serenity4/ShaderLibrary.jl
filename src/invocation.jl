struct PhysicalRef{T}
  address::DeviceAddress
end
Base.getindex(ref::PhysicalRef{T}) where {T} = @load ref.address::T
Base.getproperty(ref::PhysicalRef, name::Symbol) = name === :data ? ref[] : getfield(ref, name)

struct PhysicalBuffer{T}
  size::UInt32
  address::DeviceAddress
end

Base.getindex(buffer::PhysicalBuffer{T}, i) where {T} = @load buffer.address[i]::T
Base.iterate(buffer::PhysicalBuffer) = iterate(buffer, 1U)
function Base.iterate(buffer::PhysicalBuffer{T}, i) where {T}
  i > buffer.size && return nothing
  (buffer[i], i + one(i))
end
Base.IteratorEltype(::Type{PhysicalBuffer{T}}) where {T} = Base.HasEltype()
Base.eltype(::Type{PhysicalBuffer{T}}) where {T} = T
Base.length(buffer::PhysicalBuffer) = buffer.size

PhysicalBuffer{T}(size::Integer, buffer::Buffer) where {T} = PhysicalBuffer{T}(size, DeviceAddress(buffer))
PhysicalBuffer{T}() where {T} = PhysicalBuffer{T}(0, DeviceAddress(0))

@struct_hash_equal struct InvocationData
  vertex_locations::PhysicalBuffer{Vec3} # indexed by `VertexIndex + 1`
  "Vertex normals in object space."
  vertex_normals::PhysicalBuffer{Vec3} # indexed by `VertexIndex + 1`
  vertex_data::DeviceAddress # optional vector indexed by `VertexIndex + 1`
  primitive_data::DeviceAddress # optional vector indexed by primitive index
  primitive_indices::DeviceAddress # primitive index by `VertexIndex + 1`
  instance_data::DeviceAddress # optional vector indexed by `InstanceIndex + 1`
  user_data::DeviceAddress # user-defined data
  camera::Camera # provided as a shader parameter
  aspect_ratio::Float32 # computed from a "reference" attachment (i.e. the color attachment in most cases)
end

"""
    interface(::GraphicsShaderComponent)

Return a tuple type `Tuple{VT,PT,IT,UT}` representing expected types for primitive, vertex, instance and user data.
A type of `Nothing` indicates the absence of value.
"""
function interface end

data_container(::Type{Nothing}) = nothing
data_container(::Type{T}) where {T} = T[]
data_container(::Type{Vector{T}}) where {T} = T[]

ProgramInvocationData(shader::GraphicsShaderComponent, parameters, prog, instance::Instance) = ProgramInvocationData(shader, parameters, prog, SA[instance])
ProgramInvocationData(shader::GraphicsShaderComponent, parameters, prog, primitive::Primitive) = ProgramInvocationData(shader, parameters, prog, SA[primitive])
ProgramInvocationData(shader::GraphicsShaderComponent, parameters, prog, primitives::AbstractVector{<:Primitive}) = ProgramInvocationData(shader, parameters, prog, Instance(primitives))

function ProgramInvocationData(shader::GraphicsShaderComponent, parameters::ShaderParameters, prog, instances::AbstractVector{<:Instance{IT,PT,VD}}) where {IT,PT,VD}
  Tuple{VD,PT,IT} <: interface(shader) || throw(ArgumentError("The provided instances do not respect the interface declared by $(nameof(typeof(shader))): ($VD,$PT,$IT) ≠ $((interface(shader).parameters...,))"))
  vertex_data, primitive_data, instance_data = data_container.((VD, PT, IT))
  vertex_locations = Vec3[]
  vertex_normals = Vec3[]
  primitive_indices = UInt32[]
  fac = scaling_factor(parameters)
  for instance in instances
    for (i, primitive) in enumerate(instance.primitives)
      (; mesh) = primitive
      VD !== Nothing && append!(vertex_data, mesh.vertex_data)
      normals = @something(mesh.vertex_normals, fill(Vec3(1, 0, 0), nv(mesh)))
      for (location, normal) in zip(mesh.vertex_locations, normals)
        location = vec3(location) .* fac
        push!(vertex_locations, apply_transform(location, primitive.transform))
        push!(vertex_normals, apply_rotation(normal, primitive.transform.rotation))
        push!(primitive_indices, i)
      end
      PT !== Nothing && push!(primitive_data, primitive.data)
    end
    IT !== Nothing && push!(instance_data, instance.data)
  end

  @invocation_data prog begin
    vlocs = PhysicalBuffer{Vec3}(length(vertex_locations), @address(@block vertex_locations))
    vnorms = PhysicalBuffer{Vec3}(length(vertex_normals), @address(@block vertex_normals))
    vdata = VD === Nothing ? DeviceAddress(0) : @address(@block vertex_data)
    pdata = PT === Nothing ? DeviceAddress(0) : @address(@block primitive_data)
    pinds = @address(@block primitive_indices)
    idata = IT === Nothing ? DeviceAddress(0) : @address(@block instance_data)
    data = user_data(shader, __context__)
    udata = isnothing(data) ? DeviceAddress(0) : @address(@block data)
    ar = aspect_ratio(reference_attachment(parameters))
    @block InvocationData(vlocs, vnorms, vdata, pdata, pinds, idata, udata, parameters.camera, ar)
  end
end

apply_unit(value, unit::Unit, parameters::ShaderParameters) = value * scaling_factor(unit, parameters)

scaling_factor(parameters::ShaderParameters) = scaling_factor(parameters.unit, parameters)
function scaling_factor(unit::Unit, parameters::ShaderParameters)
  unit === UNIT_NONE && return 1
  unit === UNIT_PIXEL && return pixel_size(parameters)
  unit === UNIT_METRIC && return pixels_par_millimeters(parameters) * pixel_size(parameters)
  error("Unknown unit: $unit")
end

function pixels_par_millimeter(parameters::ShaderParameters)
  isnothing(parameters.dpmm) && error("Dots per millimeter is missing; to use a metric unit, the millimeter equivalent of the DPI must be set in the provided `ShaderParameters`")
  dpmm_x, dpmm_y = parameters.dpmm
  dpmm_x == dpmm_y || error("Non-uniform DPI values are not supported at the moment")
  dpmm_x
end

vector_data(T) = Union{<:Vector{<:T}, <:PhysicalBuffer{<:T}}
vector_data(T1, T2) = Union{<:Vector{<:T1}, <:PhysicalBuffer{<:T2}}

"""
    instantiate(data, ctx)
    instantiate(T, data, ctx)

Transform data in a way that is compatible with shaders.

Here are notable transformations:
- `Vector{T}` -> `PhysicalBuffer{T}`
- `Vector{T1}` -> `PhysicalBuffer{T2}` (if `T2` is provided as first argument to `instantiate`)
- `Texture` -> `DescriptorIndex`

This function may be extended as `instantiate(data::T1, ctx::InvocationDataContext) -> T2` to perform an instantiation from `T1` into `T2`; then, `instantiate(T2, data::Vector{T1}, ctx)` will generate an appropriate `PhysicalBuffer{T2}`.
"""
function instantiate end

instantiate(data::Texture, ctx::InvocationDataContext) = DescriptorIndex(data, ctx)
instantiate(data::PhysicalBuffer, ctx::InvocationDataContext) = data
instantiate(data::AbstractVector{T}, ctx::InvocationDataContext) where {T} = instantiate(T, data, ctx)
function instantiate(::Type{T}, data::AbstractVector, ctx::InvocationDataContext) where {T}
  T === eltype(data) && return instantiate(collect(data), ctx)
  isempty(data) && return PhysicalBuffer{T}()
  result = T[]
  for x in data
    push!(result, instantiate(x, ctx)::T)
  end
  instantiate(result, ctx)
end
function instantiate(::Type{T}, data::AbstractVector{T}, ctx::InvocationDataContext) where {T}
  block = DataBlock(data, ctx)
  address = DeviceAddress(block, ctx)
  PhysicalBuffer{eltype(data)}(length(data), address)
end

"""
Turn aspect ratio independent `xy` 2D coordinates to aspect ratio dependent device coordinates.

For example, if rendering on a viewport of 100x200 px, device coordinates consider the square [-1, 1] on either the X or Y axis to map into the full extent of the viewport, i.e. [-1, 1] -> [1, 100] pixels for the X coordinate and [-1, 1] -> [1, 200] pixels for the Y coordinate. This non-uniform scaling distorts objects, which this transform corrects.

In the case where `aspect_ratio == 1`, this transformation has no effect.
If `aspect_ratio > 1`, the viewport is wider than it is tall, and X coordinates between 1 and `aspect_ratio` in absolute value will fall outside the central square but within the rectangle viewport.
If `aspect_ratio < 1`, the viewport is taller than it is wide, and Y coordinates between 1 and `1/aspect_ratio` in absolute value will fall outside the central square but within the rectangle viewport.

See also: [`aspect_ratio`](@ref)
"""
function device_coordinates(xy, aspect_ratio)
  xmax, ymax = max(1F, aspect_ratio), max(1F, 1F/aspect_ratio)
  remap.(xy, (-xmax, -ymax), (xmax, ymax), -1F, 1F)
end

pixel_size(parameters::ShaderParameters) = pixel_size(dimensions(reference_attachment(parameters)))
pixel_size((width, height)) = 2aspect_ratio((width, height)) / ifelse(width > height, width, height)

"""
Compute the aspect ratio from the given dimensions, taken as the ratio `width`/`height`.

This aspect ratio is notably useful to compute distortion-free device coordinates; see [`device_coordinates`](@ref).
"""
function aspect_ratio end

aspect_ratio(r::Resource) = aspect_ratio(dimensions(r.data::Union{Image, LogicalImage, Attachment, LogicalAttachment}))
aspect_ratio(area::RenderArea) = aspect_ratio((area.rect.extent.width, area.rect.extent.height))
aspect_ratio(dims) = Float32(dims[1] / dims[2])
aspect_ratio(::Nothing) = error("Dimensions must be specified for the reference attachment.")

vec2(x) = convert(Vec2, x)
vec2(x::Vec{3}) = @swizzle x.xy
vec2(x::Vec{4}) = @swizzle x.xy
vec3(x) = convert(Vec3, x)
vec3(x::Vec{2}) = Vec3(x..., 0)
vec3(x::Vec{4}) = @swizzle x.xyz
vec4(x::Vec{3}) = Vec4(x..., 1)
vec4(x) = convert(Vec4, x)

world_to_screen_coordinates(position, data::InvocationData) = world_to_screen_coordinates(position, data.camera, data.aspect_ratio)
function world_to_screen_coordinates(position, camera::Camera, aspect_ratio)
  position = project(position, camera)
  xy = device_coordinates(@swizzle(position.xy), aspect_ratio)
  Vec3(xy..., position.z)
end
