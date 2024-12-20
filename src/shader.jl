abstract type ShaderComponent end

@enum Unit::UInt32 begin
  UNIT_NONE = 0
  UNIT_PIXEL = 1
  UNIT_METRIC = 2
end

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
  unit::Optional{Unit}
  # Dots (pixels) per millimeters. Metric equivalent of the DPI.
  dpmm::Optional{Vec2U}
end

ShaderParameters(color...; color_clear = fill(DEFAULT_CLEAR_VALUE, length(color)), depth = nothing, depth_clear = nothing, stencil = nothing, stencil_clear = nothing, render_state = RenderState(), invocation_state = ProgramInvocationState(), camera = Camera(), unit = UNIT_NONE, dpmm = nothing) = ShaderParameters(collect(color), color_clear, depth, depth_clear, stencil, stencil_clear, render_state, invocation_state, camera, unit, dpmm)

RenderTargets(parameters::ShaderParameters) = RenderTargets(parameters.color, parameters.depth, parameters.stencil)

struct ProgramCache
  device::Device
  programs::IdDict{Any,Program}
end
ProgramCache(device) = ProgramCache(device, IdDict{Type,Program}())

cache_program_by_type(::Type{<:ShaderComponent}) = true
cache_key(::ShaderComponent) = error("Shaders implementing their own caching behavior must extend `cache_key(shader)` with the key to be used for caching")

function Base.get!(cache::ProgramCache, shader::ShaderComponent)
  T = typeof(shader)
  if cache_program_by_type(T)
    get!(() -> Program(T, cache.device), cache.programs, T)
  else
    get!(() -> Program(shader, cache.device), cache.programs, cache_key(shader))
  end
end
Base.empty!(cache::ProgramCache) = empty!(cache.programs)

user_data(::ShaderComponent, ctx) = nothing

renderables(cache::ProgramCache, shader::ShaderComponent, parameters::ShaderParameters, geometry, args...) = Command(cache, shader, parameters, geometry, args...)
renderables(shader::ShaderComponent, parameters::ShaderParameters, device, args...) = renderables(ProgramCache(device), shader, parameters, args...)

function default_texture(image::Resource; minification = Vk.FILTER_LINEAR, magnification = Vk.FILTER_LINEAR, kwargs...)
  Texture(image, setproperties(DEFAULT_SAMPLING, (; minification, magnification, values(kwargs)...)))
end
const CLAMP_TO_EDGE = ntuple(_ -> Vk.SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE, 3)

"""
Logical object that can be converted into a GPU rendering command as a `Command` (if available for a given component) or as
a list of `RenderNode`s.
"""
abstract type GraphicsShaderComponent <: ShaderComponent end

reference_attachment(parameters::ShaderParameters) = parameters.color[1]
GeometryExperiments.Box(parameters::ShaderParameters) = Box(parameters.camera, reference_attachment(parameters))

function resource_dependencies(shader::GraphicsShaderComponent, parameters::ShaderParameters)
  (; color, color_clear, depth, depth_clear, stencil, stencil_clear) = parameters
  dependencies = @something(resource_dependencies(shader), Dictionary{Resource,ResourceDependency}())
  for (attachment, clear) in zip(color, color_clear)
    insert!(dependencies, attachment, ResourceDependency(RESOURCE_USAGE_COLOR_ATTACHMENT, WRITE, clear, nothing))
  end
  samples = !isempty(color) ? Lava.samples(color[1]) : nothing
  !isnothing(depth) && insert!(dependencies, depth, ResourceDependency(RESOURCE_USAGE_DEPTH_ATTACHMENT, READ | WRITE, depth_clear, samples))
  !isnothing(stencil) && insert!(dependencies, stencil, ResourceDependency(RESOURCE_USAGE_STENCIL_ATTACHMENT, READ, stencil_clear, samples))
  dependencies
end

function Command(cache::ProgramCache, shader::GraphicsShaderComponent, parameters::ShaderParameters, geometry)
  !isempty(parameters.color) || throw(ArgumentError("At least one color attachment must be provided."))
  prog = get!(cache, shader)
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

interface(::ShaderComponent) = Tuple{Nothing,Nothing,Nothing}
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
  prog = get!(cache, shader)
  compute_command(
    Dispatch(invocations...),
    prog,
    ProgramInvocationData(shader, prog, invocations),
    resource_dependencies(shader),
  )
end

render(device, shader::GraphicsShaderComponent, parameters::ShaderParameters, args...) = render(device, renderables(shader, parameters, device, args...))
compute(device, shader::ComputeShaderComponent, parameters::ShaderParameters, args...) = render(device, renderables(shader, parameters, device, args...))
