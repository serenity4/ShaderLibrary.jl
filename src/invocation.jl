struct InvocationData
  vertex_locations::DeviceAddress # Vector{Vec3} indexed by VertexIndex
  vertex_data::DeviceAddress # optional vector indexed by VertexIndex
  primitive_data::DeviceAddress # optional vector indexed by a user-defined primitive index
  instance_data::DeviceAddress # optional vector indexed by InstanceIndex
  user_data::DeviceAddress # user-defined data
end

data_container(::Type{Nothing}) = nothing
data_container(::Type{T}) where {T} = T[]

ProgramInvocationData(shader::ShaderComponent, prog, instance::Instance) = ProgramInvocationData(shader, prog, SA[instance])
ProgramInvocationData(shader::ShaderComponent, prog, primitive::Primitive) = ProgramInvocationData(shader, prog, SA[primitive])
ProgramInvocationData(shader::ShaderComponent, prog, primitives::AbstractVector{<:Primitive}) = ProgramInvocationData(shader, prog, Instance(primitives))

function ProgramInvocationData(shader::ShaderComponent, prog, instances::AbstractVector{<:Instance{IT,PT,VT}}) where {IT,PT,VT}
  data = user_data(shader)
  Tuple{VT,PT,IT,typeof(data)} <: interface(shader) || throw(ArgumentError("The provided instances do not respect the interface declared by $shader: ($VT,$PT,$IT,$(typeof(data))) ≠ $((interface(shader).parameters...,))"))
  vertex_data, primitive_data, instance_data = data_container.((VT, PT, IT))
  vertex_locations = Vec3[]
  for instance in instances
    for primitive in instance.primitives
      for vertex in vertices(primitive.mesh)
        VT !== Nothing && push!(vertex_data, vertex.data)
        push!(vertex_locations, apply_transform(vec3(vertex.location), primitive.transform))
      end
      PT !== Nothing && push!(primitive_data, primitive.data)
    end
    IT !== Nothing && push!(instance_data, instance.data)
  end

  @invocation_data prog begin
    vlocs = @address(@block vertex_locations)
    vdata = VT === Nothing ? DeviceAddress(0) : @address(@block vertex_data)
    pdata = PT === Nothing ? DeviceAddress(0) : @address(@block primitive_data)
    idata = IT === Nothing ? DeviceAddress(0) : @address(@block instance_data)
    udata = isnothing(data) ? DeviceAddress(0) : @address(@block data)
    @block InvocationData(vlocs, vdata, pdata, idata, udata)
  end
end

vec3(x::Vec3) = x
vec3(x) = convert(Vec3, x)
vec3(x::Vec{2}) = Vec3(x..., 1)
