struct GammaCorrection <: ComputeShaderComponent
  factor::Float32
  color::Resource
end
GammaCorrection(resource) = GammaCorrection(2.2, resource)

struct GammaCorrectionData
  factor::Float32
  image::DescriptorIndex
  size::Tuple{UInt32, UInt32}
  dispatch_size::NTuple{3,UInt32}
end

function gamma_correction_comp((; data)::PhysicalRef{GammaCorrectionData}, images, global_id::SVector{3,UInt32}, workgroup_size::SVector{3,UInt32})
  color = images[data.image]
  index = linear_index(global_id, workgroup_size)
  index ≥ length(color) && return
  (i, j) = image_index(index, data.size)
  color[i + 1U, j + 1U] = Vec4(gamma_corrected(color[i, j].rgb, data.factor)..., color[i, j].a)
  nothing
end

function Program(::Type{GammaCorrection}, device)
  I = SPIRV.image_type(SPIRV.ImageFormatRgba16f, SPIRV.Dim2D, 0, false, false, 2)
  comp = @compute device gamma_correction_comp(
    ::PhysicalRef{GammaCorrectionData}::PushConstant,
    ::Arr{512,I}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_STORAGE_IMAGE)},
    ::SVector{3,UInt32}::Input{GlobalInvocationId},
    ::SVector{3,UInt32}::Input{WorkgroupSize},
  ) options = ComputeExecutionOptions(local_size = (8U, 8U, 1U))
  Program(comp)
end

resource_dependencies(gamma::GammaCorrection) = @resource_dependencies begin
  @read
  gamma.color::Image::Storage
  @write
  gamma.color::Image::Storage
end

function ProgramInvocationData(shader::GammaCorrection, prog, invocations)
  (nx, ny) = dimensions(shader.color)
  descriptor = storage_image_descriptor(shader.color)
  @invocation_data prog begin
    @block GammaCorrectionData(shader.factor, @descriptor(descriptor), (nx, ny), invocations)
  end
end
