@struct_hash_equal struct InvocationData
  vertex_locations::DeviceAddress # Vector{Vec3} indexed by VertexIndex
  vertex_data::DeviceAddress # optional vector indexed by VertexIndex
  primitive_data::DeviceAddress # optional vector indexed by primitive index
  primitive_indices::DeviceAddress # primitive index by vertex index
  instance_data::DeviceAddress # optional vector indexed by InstanceIndex
  user_data::DeviceAddress # user-defined data
  camera::Camera # provided as a shader parameter
end

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
  ar = Float32(aspect_ratio(reference_attachment(parameters)))
  for instance in instances
    for (i, primitive) in enumerate(instance.primitives)
      for vertex in primitive.mesh.vertex_attributes
        VT !== Nothing && push!(vertex_data, vertex.data)
        location = apply_transform(vertex.location, primitive.transform)
        location.xy = device_coordinates(location.xy, ar)
        push!(vertex_locations, location)
        push!(primitive_indices, i - 1)
      end
      PT !== Nothing && push!(primitive_data, primitive.data)
    end
    IT !== Nothing && push!(instance_data, instance.data)
  end

  @invocation_data prog begin
    vlocs = @address(@block vertex_locations)
    vdata = VT === Nothing ? DeviceAddress(0) : @address(@block vertex_data)
    pdata = PT === Nothing ? DeviceAddress(0) : @address(@block primitive_data)
    pinds = @address(@block primitive_indices)
    idata = IT === Nothing ? DeviceAddress(0) : @address(@block instance_data)
    data = user_data(shader, __context__)
    udata = isnothing(data) ? DeviceAddress(0) : @address(@block data)
    @block InvocationData(vlocs, vdata, pdata, pinds, idata, udata, parameters.camera)
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
