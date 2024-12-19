struct MipmapGamma <: ComputeShaderComponent
  image::Resource
  mipmap::Resource
end

struct MipmapGammaData
  image::DescriptorIndex
  mipmap::DescriptorIndex
end

function mipmap_gamma_comp((; data)::PhysicalRef{MipmapGammaData}, images, mipmaps, global_id::Vec3U)
  image = images[data.image]
  mipmap = mipmaps[data.mipmap]
  (i, j) = global_id.x, global_id.y
  all(1U .≤ (i, j) .≤ size(mipmap)) || return
  k = (2U)i
  l = (2U)j
  k₋₁ = k - 1U
  l₋₁ = l - 1U
  a = image[k₋₁, l₋₁]
  b = image[k, l₋₁]
  c = image[k₋₁, l]
  d = image[k, l]
  mipmap[i, j] = sqrt.(a*a + b*b + c*c + d*d) ./ 2F
  nothing
end

function Program(::Type{MipmapGamma}, device)
  I1 = spirv_image_type(Vk.Format(RGBA{Float16}), Val(:image))
  I2 = spirv_image_type(Vk.Format(RGBA{Float16}), Val(:image))
  comp = @compute device mipmap_gamma_comp(
    ::PhysicalRef{MipmapGammaData}::PushConstant,
    ::Arr{512,I1}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_STORAGE_IMAGE)},
    ::Arr{512,I2}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_STORAGE_IMAGE)},
    ::Vec3U::Input{GlobalInvocationId},
  ) options = ComputeExecutionOptions(local_size = (8U, 8U, 1U))
  Program(comp)
end

resource_dependencies(shader::MipmapGamma) = @resource_dependencies begin
  @read
  shader.image::Image::Storage
  @write
  shader.mipmap::Image::Storage
end

function ProgramInvocationData(shader::MipmapGamma, prog, invocations)
  image = storage_image_descriptor(shader.image)
  mipmap = storage_image_descriptor(shader.mipmap)
  @invocation_data prog begin
    @block MipmapGammaData(@descriptor(image), @descriptor(mipmap))
  end
end
