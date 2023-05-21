abstract type ShaderComponent end

"""
    interface(::ShaderComponent)

Return a tuple type `Tuple{VT,PT,IT,UT}` representing expected types for primitive, vertex, instance and user data.
A type of `Nothing` indicates the absence of value.
"""
function interface end

struct ProgramCache
  device::Device
  programs::IdDict{Type,Program}
end
ProgramCache(device) = ProgramCache(device, IdDict{Type,Program}())
Base.get!(cache::ProgramCache, T::Type) = get!(() -> Program(T, cache.device), cache.programs, T)
Base.empty!(cache::ProgramCache) = empty!(cache.programs)

user_data(::ShaderComponent, ctx) = nothing

renderables(cache::ProgramCache, shader::ShaderComponent, geometry, args...) = Command(cache, shader, geometry, args...)
renderables(shader::ShaderComponent, device, args...) = renderables(ProgramCache(device), shader, args...)
render(device, shader::ShaderComponent, geometry, args...) = render(device, renderables(shader, device, geometry, args...))

default_texture(image::Resource) = Texture(image, setproperties(DEFAULT_SAMPLING, (magnification = Vk.FILTER_LINEAR, minification = Vk.FILTER_LINEAR)))

abstract type GraphicsShaderComponent <: ShaderComponent end

color_attachments(shader::GraphicsShaderComponent) = [color_attachment(shader)]
color_attachment(shader::GraphicsShaderComponent) = shader.color
reference_attachment(shader::GraphicsShaderComponent) = color_attachment(shader)
RenderTargets(shader::GraphicsShaderComponent) = RenderTargets(color_attachments(shader))

function Command(cache::ProgramCache, shader::GraphicsShaderComponent, geometry)
  prog = get!(cache, typeof(shader))
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
Command(shader::GraphicsShaderComponent, device, args...) = Command(ProgramCache(device), shader, args...)

const CLEAR_VALUE = (0.08, 0.05, 0.1, 1.0)

resource_dependencies(shader::GraphicsShaderComponent) = @resource_dependencies @write (shader.color => CLEAR_VALUE)::Color
