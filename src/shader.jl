abstract type ShaderComponent end

"""
    interface(::ShaderComponent)

Return a tuple type `Tuple{VT,PT,IT,UT}` representing expected types for primitive, vertex, instance and user data.
A type of `Nothing` indicates the absence of value.
"""
function interface end

struct ShaderParameters
  targets::RenderTargets
  render_state::RenderState
  invocation_state::ProgramInvocationState
end

ShaderParameters(color...; depth = nothing, stencil = nothing, render_state = RenderState(), invocation_state = ProgramInvocationState()) = ShaderParameters(RenderTargets(color...; depth, stencil), render_state, invocation_state)

struct ProgramCache
  device::Device
  programs::IdDict{Type,Program}
end
ProgramCache(device) = ProgramCache(device, IdDict{Type,Program}())
Base.get!(cache::ProgramCache, T::Type) = get!(() -> Program(T, cache.device), cache.programs, T)
Base.empty!(cache::ProgramCache) = empty!(cache.programs)

user_data(::ShaderComponent, ctx) = nothing

renderables(cache::ProgramCache, shader::ShaderComponent, parameters::ShaderParameters, geometry, args...) = Command(cache, shader, parameters, geometry, args...)
renderables(shader::ShaderComponent, parameters::ShaderParameters, device, args...) = renderables(ProgramCache(device), shader, parameters, args...)

default_texture(image::Resource) = Texture(image, setproperties(DEFAULT_SAMPLING, (magnification = Vk.FILTER_LINEAR, minification = Vk.FILTER_LINEAR)))

abstract type GraphicsShaderComponent <: ShaderComponent end

reference_attachment(parameters::ShaderParameters) = parameters.targets.color[1]

function resource_dependencies(shader::GraphicsShaderComponent, parameters::ShaderParameters)
  (; color, depth, stencil) = parameters.targets
  dependencies = resource_dependencies(shader)
  for attachment in color
    insert!(dependencies, attachment, ResourceDependency(RESOURCE_USAGE_COLOR_ATTACHMENT, WRITE, CLEAR_VALUE, nothing))
  end
  !isnothing(depth) && insert!(dependencies, depth, ResourceDependency(RESOURCE_USAGE_DEPTH_ATTACHMENT, READ | WRITE))
  !isnothing(depth) && insert!(dependencies, stencil, ResourceDependency(RESOURCE_USAGE_STENCIL_ATTACHMENT, READ))
  dependencies
end

function Command(cache::ProgramCache, shader::GraphicsShaderComponent, parameters::ShaderParameters, geometry)
  !isempty(parameters.targets.color) || throw(ArgumentError("At least one color attachment must be provided."))
  prog = get!(cache, typeof(shader))
  graphics_command(
    DrawIndexed(geometry),
    prog,
    ProgramInvocationData(shader, parameters, prog, geometry),
    parameters.targets,
    parameters.render_state,
    setproperties(parameters.invocation_state, (;
      primitive_topology = Vk.PrimitiveTopology(geometry),
      triangle_orientation = Vk.FrontFace(geometry),
    )),
    resource_dependencies(shader, parameters),
  )
end
Command(shader::ShaderComponent, parameters::ShaderParameters, device, args...) = Command(ProgramCache(device), shader, parameters, args...)

const CLEAR_VALUE = (0.08, 0.05, 0.1, 1.0)

resource_dependencies(shader::GraphicsShaderComponent) = Lava.Dictionary{Resource,ResourceDependency}()

abstract type ComputeShaderComponent <: ShaderComponent end

function Command(cache::ProgramCache, shader::ComputeShaderComponent, parameters::ShaderParameters, invocations)
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

render(device, shader::GraphicsShaderComponent, parameters::ShaderParameters, args...) = render(device, renderables(shader, parameters, device, args...))
compute(device, shader::ComputeShaderComponent, parameters::ShaderParameters, args...) = compute(device, renderables(shader, parameters, device, args...))
