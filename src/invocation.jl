struct InvocationData
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
  for instance in instances
    for primitive in instance.primitives
      VT !== Nothing && append!(vertex_data, primitive.vertex_data)
      PT !== Nothing && push!(primitive_data, primitive.data)
    end
    IT !== Nothing && push!(instance_data, instance.data)
  end

  @invocation_data prog begin
    vdata = VT === Nothing ? DeviceAddress(0) : @address(@block vertex_data)
    pdata = PT === Nothing ? DeviceAddress(0) : @address(@block primitive_data)
    idata = IT === Nothing ? DeviceAddress(0) : @address(@block instance_data)
    udata = isnothing(data) ? DeviceAddress(0) : @address(@block data)
    @block InvocationData(vdata, pdata, idata, udata)
  end
end
