@testset "Program cache" begin
  cache = ProgramCache(device)

  shader = Gradient()
  program = get!(cache, shader)
  @test program === get!(cache, shader)
  @test length(cache.programs) == 1

  dims = [512, 512]
  image = image_resource(device, nothing; format = RGBA{Float16}, dims, usage_flags = Vk.IMAGE_USAGE_STORAGE_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT)
  mipmap = image_resource(device, nothing; format = RGBA{Float16}, dims = dims .÷ 2, usage_flags = Vk.IMAGE_USAGE_STORAGE_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT)
  shader = MipmapGamma(image, mipmap)
  program_1 = get!(cache, shader)
  @test program_1 === get!(cache, shader)
  @test length(cache.programs) == 2

  image = image_resource(device, nothing; format = RGBA{Float32}, dims, usage_flags = Vk.IMAGE_USAGE_STORAGE_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_TRANSFER_DST_BIT, mip_levels = 6)
  shader = MipmapGamma(image, mipmap)
  program_2 = get!(cache, shader)
  @test program_2 === get!(cache, shader)
  @test program_1 !== program_2
  @test length(cache.programs) == 3
end;
