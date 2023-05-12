abstract type ShaderComponent end

"""
    interface(::ShaderComponent)

Return a tuple type `Tuple{VT,PT,IT,UT}` representing expected types for primitive, vertex, instance and user data.
A type of `Nothing` indicates the absence of value.
"""
function interface end

user_data(::ShaderComponent, ctx) = nothing

renderables(shader::ShaderComponent, device, geometry, args...) = Command(shader, device, geometry, args...)
render(device, shader::ShaderComponent, geometry, args...) = render(device, renderables(shader, device, geometry, args...))

default_texture(image::Resource) = Texture(image, setproperties(DEFAULT_SAMPLING, (magnification = Vk.FILTER_LINEAR, minification = Vk.FILTER_LINEAR)))

abstract type GraphicsShaderComponent <: ShaderComponent end

color_attachments(shader::GraphicsShaderComponent) = [color_attachment(shader)]
color_attachment(shader::GraphicsShaderComponent) = shader.color
reference_attachment(shader::GraphicsShaderComponent) = color_attachment(shader)
RenderTargets(shader::GraphicsShaderComponent) = RenderTargets(color_attachments(shader))

function Command(shader::GraphicsShaderComponent, device, geometry, prog = Program(shader, device))
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

const CLEAR_VALUE = (0.08, 0.05, 0.1, 1.0)

resource_dependencies(shader::GraphicsShaderComponent) = @resource_dependencies @write (shader.color => CLEAR_VALUE)::Color
