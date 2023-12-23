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

function gamma_correction_comp((; data)::PhysicalRef{GammaCorrectionData}, images, local_id::SVector{3,UInt32}, global_id::SVector{3,UInt32})
  color = images[data.image]
  li = linearize_index(global_id, data.dispatch_size, local_id, workgroup_size(GammaCorrection))
  (i, j) = image_index(li, data.size)
  color[i, j] = Vec4(gamma_corrected(color[i, j].rgb, data.factor)..., color[i, j].a)
end

function Program(::Type{GammaCorrection}, device)
  I = SPIRV.image_type(SPIRV.ImageFormatRgba16f, SPIRV.Dim2D, 0, false, false, 2)
  comp = @compute device gamma_correction_comp(
    ::PhysicalRef{GammaCorrectionData}::PushConstant,
    ::Arr{512,I}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_STORAGE_IMAGE)},
    ::SVector{3,UInt32}::Input{LocalInvocationId},
    ::SVector{3,UInt32}::Input{WorkgroupId},
  ) options = ComputeExecutionOptions(local_size = workgroup_size(GammaCorrection))
  Program(comp)
end

workgroup_size(::Type{GammaCorrection}) = (8U, 8U, 1U)
# dispatch_size(shader::GammaCorrection) = # TODO

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
