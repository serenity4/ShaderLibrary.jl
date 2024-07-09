function compute_prefiltered_environment!(image::Image, mip_level::Integer, device::Device, shader::PrefilteredEnvironmentConvolution)
  screen = screen_box(1.0)
  for layer in 1:6
    directions = CUBEMAP_FACE_DIRECTIONS[layer]
    geometry = Primitive(Rectangle(screen, directions, nothing))
    attachment = attachment_resource(ImageView(image; layer_range = layer:layer, mip_range = mip_level:mip_level), WRITE; name = Symbol(:prefiltered_environment_mip_, mip_level, :_layer_, fieldnames(CubeMapFaces)[layer]))
    parameters = ShaderParameters(attachment)
    # Improvement: Parallelize face rendering with `render!` and a manually constructed render graph.
    # There is no need to synchronize sequentially with blocking functions as done here.
    render(device, shader, parameters, geometry)
  end
end

function compute_prefiltered_environment!(result::Resource, environment::Resource, device::Device)
  assert_is_cubemap(result)
  for mip_level in mip_range(result.image)
    roughness = (mip_level - 1) / (max(1, length(mip_range(result.image)) - 1))
    shader = PrefilteredEnvironmentConvolution{environment.image.format}(environment, roughness)
    compute_prefiltered_environment!(result.image, mip_level, device, shader)
  end
  result
end

function compute_prefiltered_environment(environment::Resource, device::Device; base_resolution = 256, mip_levels = Int(log2(base_resolution)) - 2, usage_flags = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_SAMPLED_BIT)
  result = image_resource(device, nothing; dims = [base_resolution, base_resolution], format = environment.image.format, layers = 6, mip_levels, usage_flags = Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT | usage_flags, name = :prefiltered_environment)
  compute_prefiltered_environment!(result, environment, device)
end
