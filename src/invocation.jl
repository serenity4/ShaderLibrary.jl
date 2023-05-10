struct InvocationData
  vertex_locations::DeviceAddress # Vector{Vec3} indexed by VertexIndex
  vertex_data::DeviceAddress # optional vector indexed by VertexIndex
  primitive_data::DeviceAddress # optional vector indexed by primitive index
  primitive_indices::DeviceAddress # primitive index by vertex index
  instance_data::DeviceAddress # optional vector indexed by InstanceIndex
  user_data::DeviceAddress # user-defined data
end

data_container(::Type{Nothing}) = nothing
data_container(::Type{T}) where {T} = T[]

ProgramInvocationData(shader::ShaderComponent, prog, instance::Instance) = ProgramInvocationData(shader, prog, SA[instance])
ProgramInvocationData(shader::ShaderComponent, prog, primitive::Primitive) = ProgramInvocationData(shader, prog, SA[primitive])
ProgramInvocationData(shader::ShaderComponent, prog, primitives::AbstractVector{<:Primitive}) = ProgramInvocationData(shader, prog, Instance(primitives))

function ProgramInvocationData(shader::ShaderComponent, prog, instances::AbstractVector{<:Instance{IT,PT,VT}}) where {IT,PT,VT}
  Tuple{VT,PT,IT} <: interface(shader) || throw(ArgumentError("The provided instances do not respect the interface declared by $shader: ($VT,$PT,$IT) ≠ $((interface(shader).parameters...,))"))
  vertex_data, primitive_data, instance_data = data_container.((VT, PT, IT))
  vertex_locations = Vec3[]
  primitive_indices = UInt32[]
  for instance in instances
    for (i, primitive) in enumerate(instance.primitives)
      for vertex in vertices(primitive.mesh)
        VT !== Nothing && push!(vertex_data, vertex.data)
        push!(vertex_locations, apply_transform(vec3(vertex.location), primitive.transform))
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
    @block InvocationData(vlocs, vdata, pdata, pinds, idata, udata)
  end
end

vec3(x::Vec3) = x
vec3(x) = convert(Vec3, x)
vec3(x::Vec{2}) = Vec3(x..., 1)
vec3(x::SVector{2}) = Vec3(x..., 1)
