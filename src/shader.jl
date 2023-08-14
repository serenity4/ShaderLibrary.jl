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
Command(shader::ShaderComponent, device, args...) = Command(ProgramCache(device), shader, args...)

const CLEAR_VALUE = (0.08, 0.05, 0.1, 1.0)

resource_dependencies(shader::GraphicsShaderComponent) = @resource_dependencies @write (shader.color => CLEAR_VALUE)::Color

abstract type ComputeShaderComponent <: ShaderComponent end

function Command(cache::ProgramCache, shader::ComputeShaderComponent, invocations)
  prog = get!(cache, typeof(shader))
  compute_command(
    Dispatch(invocations...),
    prog,
    ProgramInvocationData(shader, prog),
    resource_dependencies(shader),
  )
end

linearize_index((x, y, z), (nx, ny, nz)) = x + y * nx + z * nx * ny
function linearize_index(global_id, global_size, local_id, local_size)
  linearize_index(local_id, local_size) + prod(local_size) * linearize_index(global_id, global_size)
end

image_index(linear_index, (ni, nj)) = (linear_index % ni, linear_index ÷ ni)

render(device, shader::GraphicsShaderComponent, geometry, args...) = render(device, renderables(shader, device, geometry, args...))
compute(device, shader::ComputeShaderComponent, args...) = compute(device, renderables(shader, device, args...))
