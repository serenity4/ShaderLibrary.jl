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
  for instance in instances
    for (i, primitive) in enumerate(instance.primitives)
      (; mesh) = primitive
      VD !== Nothing && append!(vertex_data, mesh.vertex_data)
      append!(vertex_locations, apply_transform(vec3(location), primitive.transform) for location in mesh.vertex_locations)
      normals = @something(mesh.vertex_normals, Vec3(1, 0, 0) for _ in 1:nv(mesh))
      append!(vertex_normals, apply_rotation(normal, primitive.transform.rotation) for normal in normals)
      append!(primitive_indices, i * ones(nv(mesh)))
      PT !== Nothing && push!(primitive_data, primitive.data)
    end
    IT !== Nothing && push!(instance_data, instance.data)
  end

  @assert length(vertex_locations) == length(vertex_normals)

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

function device_coordinates(xy, ar)
  xmax, ymax = max(1F, ar), max(1F, 1F/ar)
  remap.(xy, (-xmax, -ymax), (xmax, ymax), -1F, 1F)
end

aspect_ratio(r::Resource) = aspect_ratio(dimensions(r.attachment))
aspect_ratio(dims) = Float32(dims[1] / dims[2])
aspect_ratio(::Nothing) = error("Dimensions must be specified for the reference attachment.")

point3(x::Point{2}) = Point{3,eltype(x)}(x..., 0)
point3(x::Point{3}) = x
point4(x::Point{3}) = Point{4,eltype(x)}(x..., 1)
point4(x::Point{4}) = x

vec3(x::Vec3) = x
vec3(x::Tuple) = vec3(Point(x))
vec3(x) = convert(Vec3, x)
vec3(x::Vec{2}) = Vec3(x..., 0)
vec3(x::Point{2}) = Vec3(x..., 0)
vec3(x::Point{3}) = Vec3(x...)
vec4(x::Vec{3}) = Vec4(x..., 1)
vec4(x::Point{3}) = Vec4(x..., 1)
vec4(x) = convert(Vec4, x)

world_to_screen_coordinates(position, data::InvocationData) = world_to_screen_coordinates(position, data.camera, data.aspect_ratio)
function world_to_screen_coordinates(position, camera::Camera, aspect_ratio)
  position = project(position, camera)
  position.xy = device_coordinates(position.xy, aspect_ratio)
  position
end
