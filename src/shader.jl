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
  depth_clear::Optional{Float32}
  stencil::Optional{Resource}
  stencil_clear::Optional{UInt32}
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
  lock::SpinLock
end
ProgramCache(device) = ProgramCache(device, IdDict{Type,Program}(), SpinLock())

@forward_methods ProgramCache field=:lock Base.lock Base.unlock

Base.show(io::IO, cache::ProgramCache) = print(io, ProgramCache, '(', length(cache.programs), " programs)")

cache_program_by_type(::Type{<:ShaderComponent}) = true
cache_key(::ShaderComponent) = error("Shaders implementing their own caching behavior must extend `cache_key(shader)` with the key to be used for caching")

function Base.get!(cache::ProgramCache, shader::ShaderComponent)
  T = typeof(shader)
  key, argument = cache_program_by_type(T) ? (T, T) : (cache_key(shader), shader)

  program = @lock cache get(cache.programs, key, nothing)
  program !== nothing && return program
  # This takes a while, so it's best to do it while not holding the lock.
  program = Program(argument, cache.device)

  @lock cache begin
    # Try again to get a program, in case someone cached one in the meantime.
    existing = get(cache.programs, key, nothing)
    existing !== nothing && return existing
    # It's now time to store the created program.
    cache.programs[key] = program
  end

  return program
end
Base.empty!(cache::ProgramCache) = @lock cache empty!(cache.programs)

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
  for (i, attachment) in enumerate(color)
    clear = color_clear === nothing ? nothing : get(color_clear, i, nothing)
    insert!(dependencies, attachment, ResourceDependency(RESOURCE_USAGE_COLOR_ATTACHMENT, WRITE, clear, nothing))
  end
  samples = !isempty(color) ? Lava.samples(color[1]) : nothing
  if !isnothing(depth) || !isnothing(stencil)
    usage, depth_stencil_clear, resource = @match (depth, stencil) begin
      (::Resource, ::Nothing) => (RESOURCE_USAGE_DEPTH_ATTACHMENT, isnothing(depth_clear) ? nothing : ClearValue(depth_clear), depth)
      (::Nothing, ::Resource) => (RESOURCE_USAGE_STENCIL_ATTACHMENT, isnothing(stencil_clear) ? nothing : ClearValue(stencil_clear), stencil)
      (::Resource, ::Resource) => begin
        depth === stencil || error("The depth and stencil attachments must be the same resource if both are provided")
        depth_stencil_clear = isnothing(depth_clear) && isnothing(stencil_clear) ? nothing : ClearValue((depth_clear, stencil_clear))
        (RESOURCE_USAGE_DEPTH_ATTACHMENT | RESOURCE_USAGE_STENCIL_ATTACHMENT, depth_stencil_clear, depth)
      end
    end
    insert!(dependencies, resource, ResourceDependency(usage, READ | WRITE, depth_stencil_clear, samples))
  end
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
