struct LargeScaleErosion{T<:AbstractFloat,M<:TectonicBasedErosion} <: ComputeShaderComponent
  model::M
  maps::ErosionMaps{Resource}
end

struct LargeScaleErosionData{M<:TectonicBasedErosion}
  maps::ErosionMaps{DescriptorIndex}
  model::M
  size::Tuple{UInt32, UInt32}
  dispatch_size::NTuple{3,UInt32}
end

function large_scale_erosion_comp!(data_address::DeviceAddressBlock, images, local_id::Vec{3,UInt32}, global_id::Vec{3,UInt32}, ::Type{M}) where {M}
  data = @load data_address::LargeScaleErosionData{M}
  (; dispatch_size) = data
  li = linearize_index(global_id, dispatch_size, local_id, workgroup_size(LargeScaleErosion))
  (nx, ny) = data.size
  (i, j) = image_index(li, (nx, ny))
  (; maps, model) = data
  maps = ErosionMaps(
    images[maps.drainage],
    images[maps.new_drainage],
    images[maps.elevation],
    images[maps.new_elevation],
    images[maps.uplift],
    images[maps.new_uplift],
  )
  @inline Erosion.simulate!(maps, model, Erosion.GridPoint(i, j), (nx, ny))
  nothing
end

function renderables(cache::ProgramCache, shader::LargeScaleErosion, invocations)
  prog = get!(cache, typeof(shader))
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

workgroup_size(::Type{<:LargeScaleErosion}) = (8, 8, 1)
# dispatch_size(shader::LargeScaleErosion) = # TODO

eltype_to_image_format(::Type{Float32}) = SPIRV.ImageFormatR32f
eltype_to_image_format(T) = SPIRV.ImageFormat(T)

function Program(::Type{S}, device) where {T,M,S<:LargeScaleErosion{T,M}}
  I = SPIRV.image_type(eltype_to_image_format(T), SPIRV.Dim2D, 0, false, false, 1)
  compute = @compute device large_scale_erosion_comp!(
    ::DeviceAddressBlock::PushConstant,
    ::Arr{2048,I}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_COMBINED_IMAGE_SAMPLER)},
    ::Vec{3,UInt32}::Input{LocalInvocationId},
    ::Vec{3,UInt32}::Input{WorkgroupId},
    ::Type{M},
  ) options = ComputeExecutionOptions(local_size = workgroup_size(S))
  Program(compute)
end

function ProgramInvocationData(shader::LargeScaleErosion, prog, invocations)
  (; maps) = shader
  (nx, ny) = dimensions(maps.elevation)
  @invocation_data prog begin
    maps = ErosionMaps(
      @descriptor(maps.drainage),
      @descriptor(maps.new_drainage),
      @descriptor(maps.elevation),
      @descriptor(maps.new_elevation),
      @descriptor(maps.uplift),
      @descriptor(maps.new_uplift),
    )
    @block LargeScaleErosionData(shader.model, maps, (nx, ny), invocations)
  end
end
