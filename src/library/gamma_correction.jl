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

function gamma_correction_comp((; data)::PhysicalRef{GammaCorrectionData}, images, global_id::Vec3U)
  color = images[data.image]
  (i, j) = global_id.x + 1U, global_id.y + 1U
  all(1U .≤ (i, j) .≤ data.size) || return
  pixel = color[i, j]
  color[i, j] = Vec4(gamma_corrected(@swizzle(pixel.rgb), data.factor)..., @swizzle pixel.a)
  nothing
end

function Program(::Type{GammaCorrection}, device)
  I = spirv_image_type(Vk.Format(RGBA{Float16}), Val(:image))
  comp = @compute device gamma_correction_comp(
    ::PhysicalRef{GammaCorrectionData}::PushConstant,
    ::Arr{512,I}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_STORAGE_IMAGE)},
    ::Vec3U::Input{GlobalInvocationId},
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
