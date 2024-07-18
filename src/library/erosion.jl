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

function large_scale_erosion_comp!(data_address::DeviceAddressBlock, images, global_id::SVector{3,UInt32}, workgroup_size::SVector{3,UInt32}, ::Type{M}) where {M}
  data = @load data_address::LargeScaleErosionData{M}
  (; dispatch_size) = data
  index = linear_index(global_id, workgroup_size)
  (nx, ny) = data.size
  (i, j) = image_index(index, (nx, ny))
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

eltype_to_image_format(::Type{Float32}) = SPIRV.ImageFormatR32f
eltype_to_image_format(T) = SPIRV.ImageFormat(T)

function Program(::Type{S}, device) where {T,M,S<:LargeScaleErosion{T,M}}
  I = SPIRV.image_type(eltype_to_image_format(T), SPIRV.Dim2D, 0, false, false, 1)
  compute = @compute device large_scale_erosion_comp!(
    ::DeviceAddressBlock::PushConstant,
    ::Arr{2048,I}::UniformConstant{@DescriptorSet($GLOBAL_DESCRIPTOR_SET_INDEX), @Binding($BINDING_COMBINED_IMAGE_SAMPLER)},
    ::SVector{3,UInt32}::Input{GlobalInvocationId},
    ::SVector{3,UInt32}::Input{WorkgroupSize},
    ::Type{M},
  ) options = ComputeExecutionOptions(local_size = (8, 8, 1))
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
    @block LargeScaleErosionData(maps, shader.model, (nx, ny), invocations)
  end
end
