struct LargeScaleErosion{T<:AbstractFloat,M<:TectonicBasedErosion} <: ComputeShaderComponent
  model::M
  maps::ErosionMaps{Resource}
end

struct LargeScaleErosionData{M<:TectonicBasedErosion}
  model::M
  maps::ErosionMaps{DescriptorIndex}
  size::Tuple{UInt32, UInt32}
  dispatch_size::NTuple{3,UInt32}
end

function large_scale_erosion_comp!(data_address::DeviceAddressBlock, images, global_id::Vec3U, ::Type{M}) where {M}
  data = @load data_address::LargeScaleErosionData{M}
  (; dispatch_size) = data
  (i, j) = global_id.x + 1U, global_id.y + 1U
  all(1U .< (i, j) .< data.size) || return
  (; maps, model) = data
  maps = ErosionMaps(
    images[maps.drainage],
    images[maps.new_drainage],
    images[maps.elevation],
    images[maps.new_elevation],
    images[maps.uplift],
    images[maps.new_uplift],
  )
  @inline Erosion.simulate!(maps, model, Erosion.GridPoint(i, j), data.size)
  nothing
end

function renderables(cache::ProgramCache, shader::LargeScaleErosion, parameters::ShaderParameters, invocations)
  prog = get!(cache, shader)
  simulation_step = compute_command(
    Dispatch(invocations...),
    prog,
    ProgramInvocationData(shader, prog, invocations),
    simulation_dependencies(shader),
  )
  (; maps) = shader
  elevation_update_step = transfer_command(maps.new_elevation, maps.elevation)
  drainage_update_step = transfer_command(maps.new_drainage, maps.drainage)
  # uplift_update_step = transfer_command(maps.new_uplift, maps.uplift)
  [simulation_step, elevation_update_step, drainage_update_step]
end

function simulation_dependencies(shader::LargeScaleErosion)
  @resource_dependencies begin
    @read
    shader.maps.uplift::Image::Storage
    shader.maps.elevation::Image::Storage
    shader.maps.drainage::Image::Storage
    @write
    shader.maps.new_uplift::Image::Storage
    shader.maps.new_elevation::Image::Storage
    shader.maps.new_drainage::Image::Storage
  end
end

function Program(::Type{S}, device) where {T,M,S<:LargeScaleErosion{T,M}}
  I = spirv_image_type(Vk.Format(T), Val(:image))
  compute = @compute device large_scale_erosion_comp!(
    ::DeviceAddressBlock::PushConstant,
    ::Arr{512,I}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_STORAGE_IMAGE)},
    ::Vec3U::Input{GlobalInvocationId},
    ::Type{M},
  ) options = ComputeExecutionOptions(local_size = (32, 32, 1))
  Program(compute)
end

function ProgramInvocationData(shader::LargeScaleErosion, prog, invocations)
  (; maps) = shader
  (nx, ny) = UInt32.(dimensions(maps.elevation))
  M = typeof(shader.model)
  @invocation_data prog begin
    maps = ErosionMaps(
      @descriptor(storage_image_descriptor(maps.drainage)),
      @descriptor(storage_image_descriptor(maps.new_drainage)),
      @descriptor(storage_image_descriptor(maps.elevation)),
      @descriptor(storage_image_descriptor(maps.new_elevation)),
      @descriptor(storage_image_descriptor(maps.uplift)),
      @descriptor(storage_image_descriptor(maps.new_uplift)),
    )
    @block LargeScaleErosionData{M}(shader.model, maps, (nx, ny), invocations)
  end
end
