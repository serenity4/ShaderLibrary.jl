const BLUR_HORIZONTAL = 0
const BLUR_VERTICAL = 1

struct GaussianBlurDirectionalComp{T} <: ComputeShaderComponent
  source::Resource
  destination::Resource
  direction::UInt32
  radius::Float32
end
GaussianBlurDirectionalComp{T}(source::Resource, destination::Resource, direction) where {T} = GaussianBlurDirectionalComp{T}(source, destination, direction, 32)

struct GaussianBlurDirectionalCompData
  source::DescriptorIndex
  destination::DescriptorIndex
  direction::UInt32
  radius::Float32
  dispatch_size::NTuple{3,UInt32}
end

function gaussian_blur_directional_pixel(source, pixel, direction, radius)
  res = zero(Vec3)
  image_size = size(source)
  rx, ry = Int32.(min.(ceil.(3radius .* image_size), image_size))
  if direction == BLUR_HORIZONTAL
    for i in -rx:rx
      weight = gaussian_1d(i, radius)
      sampled = source[pixel.x + i, pixel.y]
      color = sampled.rgb
      res .+= color * weight
    end
  else
    for j in -ry:ry
      weight = gaussian_1d(j, radius)
      sampled = source[pixel.x, pixel.y + j]
      color = sampled.rgb
      res .+= color * weight
    end
  end
  res
end

function gaussian_blur_directional_comp(::Type{T}, (; data)::PhysicalRef{GaussianBlurDirectionalCompData}, images, global_id::SVector{3,UInt32}) where {T}
  source, destination = images[data.source], images[data.destination]
  (i, j) = global_id.x + 1U, global_id.y + 1U
  all(1U .< (i, j) .< size(destination)) || return
  result = gaussian_blur_directional_pixel(source, SVector(i, j), data.direction, data.radius)
  if T <: RGBA
    destination[i, j] = Vec4(result..., source[i, j].a)
  else
    destination[i, j] = result
  end
  nothing
end

function Program(::Type{GaussianBlurDirectionalComp{T}}, device) where {T}
  I = SPIRV.image_type(eltype_to_image_format(T), SPIRV.Dim2D, 0, false, false, 2)
  comp = @compute device gaussian_blur_directional_comp(
    ::Type{T},
    ::PhysicalRef{GaussianBlurDirectionalCompData}::PushConstant,
    ::Arr{512,I}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_STORAGE_IMAGE)},
    ::SVector{3,UInt32}::Input{GlobalInvocationId},
  ) options = ComputeExecutionOptions(local_size = (8U, 8U, 1U))
  Program(comp)
end

resource_dependencies(blur::GaussianBlurDirectionalComp) = @resource_dependencies begin
  @read
  blur.source::Image::Storage
  @write
  blur.destination::Image::Storage
end

function ProgramInvocationData(shader::GaussianBlurDirectionalComp, prog, invocations)
  dimensions(shader.source) == dimensions(shader.destination) || throw(ArgumentError("Dimensions between blur source and destination don't match: $(dimensions(shader.source)) ≠ $(dimensions(shader.destination))"))
  (nx, ny) = dimensions(shader.source)
  source = storage_image_descriptor(shader.source)
  destination = storage_image_descriptor(shader.destination)
  @invocation_data prog begin
    @block GaussianBlurDirectionalCompData(@descriptor(source), @descriptor(destination), shader.direction, shader.radius, invocations)
  end
end

struct GaussianBlurComp{T} <: ComputeShaderComponent
  source::Resource
  destination::Resource
  size::Float32
end
GaussianBlurComp{T}(image::Resource) where {T} = GaussianBlurComp{T}(image, 0.01)

function renderables(cache::ProgramCache, blur::GaussianBlurComp{T}, parameters::ShaderParameters, invocations) where {T}
  (; source, destination) = blur
  transient = similar(destination; name = :transient)

  # Blur image along X.
  blur_x_shader = GaussianBlurDirectionalComp{T}(source, transient, BLUR_HORIZONTAL, blur.size)
  blur_x = RenderNode(Command(cache, blur_x_shader, parameters, invocations), :directional_blur_x)

  # Blur image along Y.
  blur_y_shader = GaussianBlurDirectionalComp{T}(transient, destination, BLUR_VERTICAL, blur.size)
  blur_y = RenderNode(Command(cache, blur_y_shader, parameters, invocations), :directional_blur_y)

  (blur_x, blur_y)
end
