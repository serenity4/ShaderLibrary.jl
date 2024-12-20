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

function generate_mipmaps(resource::Resource, device::Device, submission::Optional{SubmissionInfo} = nothing)
  assert_type(resource, RESOURCE_TYPE_IMAGE)
  generate_mipmaps(resource.image, device, submission)
end

function generate_mipmaps(image::Image, device::Device, submission::Optional{SubmissionInfo} = nothing)
  range = mip_range(image)
  length(range) == 1 && throw(ArgumentError("Mipmap generation requires more than one mip level"))
  mip_levels = range[2]:last(range)
  parameters = ShaderParameters()
  ni, nj = dimensions(image)
  invocations = (cld(ni, 8), cld(nj, 8))
  render_graph = RenderGraph(device)
  for layer in layer_range(image)
    base_level = first(range)
    for mip_level in mip_levels
      base = image_view_resource(image; layer_range = layer:layer, mip_range = base_level:base_level)
      mipmap = image_view_resource(image; layer_range = layer:layer, mip_range = mip_level:mip_level)
      shader = MipmapGamma(base, mipmap)
      command = renderables(shader, parameters, device, invocations)
      add_node!(render_graph, command)
      base_level = mip_level
    end
  end
  isnothing(submission) && return render!(render_graph)
  render!(render_graph, submission)
end
