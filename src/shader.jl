abstract type ShaderComponent end

"""
    interface(::ShaderComponent)

Return a tuple type `Tuple{VT,PT,IT,UT}` representing expected types for primitive, vertex, instance and user data.
A type of `Nothing` indicates the absence of value.
"""
function interface end

user_data(::ShaderComponent) = nothing

RenderTargets(shader::ShaderComponent) = RenderTargets(shader.color)

function Command(shader::ShaderComponent, device, geometry, prog = Program(shader, device))
  graphics_command(
    DrawIndexed(geometry),
    prog,
    ProgramInvocationData(shader, prog, geometry),
    RenderTargets(shader),
    RenderState(),
    setproperties(ProgramInvocationState(), (;
      primitive_topology = Vk.PrimitiveTopology(geometry),
      triangle_orientation = Vk.FrontFace(geometry),
    )),
    resource_dependencies(shader),
  )
end

resource_dependencies(shader::ShaderComponent) = @resource_dependencies @write (shader.color => (0.08, 0.05, 0.1, 1.0))::Color
