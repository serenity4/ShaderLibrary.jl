abstract type ShaderComponent end

struct ShaderParameters
  color::Vector{Resource}
  color_clear::Vector{Optional{ClearValue}}
  depth::Optional{Resource}
  depth_clear::Optional{ClearValue}
  stencil::Optional{Resource}
  stencil_clear::Optional{ClearValue}
  render_state::RenderState
  invocation_state::ProgramInvocationState
  camera::Camera
end

ShaderParameters(color...; color_clear = [DEFAULT_CLEAR_VALUE for _ in 1:length(color)], depth = nothing, depth_clear = nothing, stencil = nothing, stencil_clear = nothing, render_state = RenderState(), invocation_state = ProgramInvocationState(), camera = Camera()) = ShaderParameters(collect(color), color_clear, depth, depth_clear, stencil, stencil_clear, render_state, invocation_state, camera)

RenderTargets(parameters::ShaderParameters) = RenderTargets(parameters.color, parameters.depth, parameters.stencil)

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

"""
Logical object that can be converted into a GPU rendering command as a `Command` (if available for a given component) or as
a list of `RenderNode`s.
"""
abstract type GraphicsShaderComponent <: ShaderComponent end

reference_attachment(parameters::ShaderParameters) = parameters.color[1]

function resource_dependencies(shader::GraphicsShaderComponent, parameters::ShaderParameters)
  (; color, color_clear, depth, depth_clear, stencil, stencil_clear) = parameters
  dependencies = resource_dependencies(shader)
  for (attachment, clear) in zip(color, color_clear)
    insert!(dependencies, attachment, ResourceDependency(RESOURCE_USAGE_COLOR_ATTACHMENT, WRITE, clear, nothing))
  end
  !isnothing(depth) && insert!(dependencies, depth, ResourceDependency(RESOURCE_USAGE_DEPTH_ATTACHMENT, READ | WRITE, depth_clear, nothing))
  !isnothing(stencil) && insert!(dependencies, stencil, ResourceDependency(RESOURCE_USAGE_STENCIL_ATTACHMENT, READ, stencil_clear, nothing))
  dependencies
end

function Command(cache::ProgramCache, shader::GraphicsShaderComponent, parameters::ShaderParameters, geometry)
  !isempty(parameters.color) || throw(ArgumentError("At least one color attachment must be provided."))
  prog = get!(cache, typeof(shader))
  graphics_command(
    DrawIndexed(geometry),
    prog,
    ProgramInvocationData(shader, parameters, prog, geometry),
    RenderTargets(parameters),
    parameters.render_state,
    setproperties(parameters.invocation_state, (;
      primitive_topology = Vk.PrimitiveTopology(geometry),
      triangle_orientation = Vk.FrontFace(geometry),
    )),
    resource_dependencies(shader, parameters),
  )
end
Command(shader::ShaderComponent, parameters::ShaderParameters, device, args...) = Command(ProgramCache(device), shader, parameters, args...)

const DEFAULT_CLEAR_VALUE = ClearValue((0.08, 0.05, 0.1, 1.0))

resource_dependencies(shader::GraphicsShaderComponent) = Lava.Dictionary{Resource,ResourceDependency}()

"""
Way to shade a geometry in context of a rendering process.

While [`GraphicsShaderComponent`](@ref) are not necessarily parametrized by a geometry, and may instead
generate one based on inputs (e.g. [`Text`](@ref) generating a set of bounding boxes for individual glyphs),
materials require a geometry to function.

Materials are applicable to 2D and 3D objects alike, with the note that 2D objects are required
to be embedded within 3D space with a third coordinate corresponding to depth, such that drawing
order may be well-defined.
"""
abstract type Material <: GraphicsShaderComponent end

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
