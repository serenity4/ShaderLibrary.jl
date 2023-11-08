struct PhysicalRef{T}
  address::DeviceAddress
end
Base.getindex(ref::PhysicalRef{T}) where {T} = @load ref.address::T
Base.getproperty(ref::PhysicalRef, name::Symbol) = name === :data ? ref[] : getfield(ref, name)

struct PhysicalBuffer{T}
  size::UInt32
  address::DeviceAddress
end

Base.getindex(buffer::PhysicalBuffer{T}, i) where {T} = @load buffer.address[unsigned_index(i)]::T
Base.iterate(buffer::PhysicalBuffer) = iterate(buffer, 0U)
function Base.iterate(buffer::PhysicalBuffer{T}, i) where {T}
  i > buffer.size && return nothing
  (buffer[i], i + one(i))
end
Base.IteratorEltype(::Type{PhysicalBuffer{T}}) where {T} = Base.HasEltype()
Base.eltype(::Type{PhysicalBuffer{T}}) where {T} = T
Base.length(buffer::PhysicalBuffer) = buffer.size

PhysicalBuffer{T}(size::Integer, buffer::Buffer) where {T} = PhysicalBuffer{T}(size, DeviceAddress(buffer))

@struct_hash_equal struct InvocationData
  vertex_locations::PhysicalBuffer{Vec3} # indexed by vertex index
  vertex_normals::PhysicalBuffer{Vec3} # indexed by vertex index
  vertex_data::DeviceAddress # optional vector indexed by vertex index
  primitive_data::DeviceAddress # optional vector indexed by primitive index
  primitive_indices::DeviceAddress # primitive index by vertex index
  instance_data::DeviceAddress # optional vector indexed by InstanceIndex
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

ProgramInvocationData(shader::GraphicsShaderComponent, parameters, prog, instance::Instance) = ProgramInvocationData(shader, parameters, prog, SA[instance])
ProgramInvocationData(shader::GraphicsShaderComponent, parameters, prog, primitive::Primitive) = ProgramInvocationData(shader, parameters, prog, SA[primitive])
ProgramInvocationData(shader::GraphicsShaderComponent, parameters, prog, primitives::AbstractVector{<:Primitive}) = ProgramInvocationData(shader, parameters, prog, Instance(primitives))

function ProgramInvocationData(shader::GraphicsShaderComponent, parameters::ShaderParameters, prog, instances::AbstractVector{<:Instance{IT,PT,VT}}) where {IT,PT,VT}
  Tuple{VT,PT,IT} <: interface(shader) || throw(ArgumentError("The provided instances do not respect the interface declared by $shader: ($VT,$PT,$IT) ≠ $((interface(shader).parameters...,))"))
  vertex_data, primitive_data, instance_data = data_container.((VT, PT, IT))
  vertex_locations = Vec3[]
  primitive_indices = UInt32[]
  ar = aspect_ratio(reference_attachment(parameters))
  for instance in instances
    for (i, primitive) in enumerate(instance.primitives)
      for vertex in primitive.mesh.vertex_attributes
        VT !== Nothing && push!(vertex_data, vertex.data)
        location = apply_transform(vertex.location, primitive.transform)
        push!(vertex_locations, location)
        push!(primitive_indices, i - 1)
      end
      PT !== Nothing && push!(primitive_data, primitive.data)
    end
    IT !== Nothing && push!(instance_data, instance.data)
  end

  @invocation_data prog begin
    vlocs = PhysicalBuffer{Vec3}(length(vertex_locations), @address(@block vertex_locations))
    vnorms = PhysicalBuffer{Vec3}(0, DeviceAddress(0))
    vdata = VT === Nothing ? DeviceAddress(0) : @address(@block vertex_data)
    pdata = PT === Nothing ? DeviceAddress(0) : @address(@block primitive_data)
    pinds = @address(@block primitive_indices)
    idata = IT === Nothing ? DeviceAddress(0) : @address(@block instance_data)
    data = user_data(shader, __context__)
    udata = isnothing(data) ? DeviceAddress(0) : @address(@block data)
    @block InvocationData(vlocs, vnorms, vdata, pdata, pinds, idata, udata, parameters.camera, ar)
  end
end

function device_coordinates(xy, ar)
  xmax, ymax = max(1F, ar), max(1F, 1F/ar)
  remap.(xy, (-xmax, -ymax), (xmax, ymax), -1F, 1F)
end

aspect_ratio(r::Resource) = aspect_ratio(dimensions(r.attachment))
aspect_ratio(dims) = dims[1] / dims[2]
aspect_ratio(::Nothing) = error("Dimensions must be specified for the reference attachment.")

point3(x::Point{2}) = Point{3,eltype(x)}(x..., 0)
point3(x::Point{3}) = x

vec3(x::Vec3) = x
vec3(x::Tuple) = vec3(Point(x))
vec3(x) = convert(Vec3, x)
vec3(x::Vec{2}) = Vec3(x..., 0)
vec3(x::Point{2}) = Vec3(x..., 0)
vec3(x::Point{3}) = Vec3(x...)

world_to_screen_coordinates(position, data::InvocationData) = world_to_screen_coordinates(position, data.camera, data.aspect_ratio)
function world_to_screen_coordinates(position, camera::Camera, aspect_ratio)
  position = project(position, camera)
  position.xy = device_coordinates(position.xy, aspect_ratio)
  position
end
