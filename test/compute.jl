# XXX: There are race conditions are only small portions of the image are covered, probably the workgroup size isn't set right.
@testset "Computing with compute shaders" begin
  @testset "Gamma correction" begin
    texture = read_texture("boid.png")
    image = image_resource(device, texture; usage_flags = Vk.IMAGE_USAGE_STORAGE_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT)
    @test collect(image, device) == texture
    shader = GammaCorrection(image)
    compute(device, shader, ShaderParameters(), (64, 64, 1))
    data = collect(shader.color, device)
    save_test_render("gamma_correction.png", data, 0x27e9f0ff2d1cdf12)
  end

  @testset "Gaussian blur" begin
    texture = read_texture("normal.png")
    source = image_resource(device, texture; usage_flags = Vk.IMAGE_USAGE_STORAGE_BIT)
    destination = similar(source; usage_flags = Vk.IMAGE_USAGE_STORAGE_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT)
    shader = GaussianBlurDirectionalComp{RGBA{Float16}}(source, destination, BLUR_HORIZONTAL, 8)
    compute(device, shader, ShaderParameters(), (64, 64, 1))
    data = collect(shader.destination, device)
    save_test_render("gaussian_blur_vertical.png", data, 0x695881f9d0a08c2c)

    destination = similar(source; usage_flags = Vk.IMAGE_USAGE_STORAGE_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT)
    shader = GaussianBlurComp{RGBA{Float16}}(source, destination, 8)
    compute(device, shader, ShaderParameters(), (64, 64, 1))
    data = collect(shader.destination, device)
    save_test_render("gaussian_blur.png", data, 0x448e00ba66f81552)
  end

  @testset "Large-scale terrain erosion" begin
    nx, ny = (256, 256)
    drainage_image = image_resource(device, zeros(Float32, nx, ny); format = Vk.FORMAT_R32_SFLOAT)
    new_drainage_image = image_resource(device, zeros(Float32, nx, ny); format = Vk.FORMAT_R32_SFLOAT)
    elevation_image = image_resource(device, zeros(Float32, nx, ny); format = Vk.FORMAT_R32_SFLOAT)
    new_elevation_image = image_resource(device, zeros(Float32, nx, ny); format = Vk.FORMAT_R32_SFLOAT)
    uplift_image = image_resource(device, zeros(Float32, nx, ny); format = Vk.FORMAT_R32_SFLOAT)
    new_uplift_image = image_resource(device, zeros(Float32, nx, ny); format = Vk.FORMAT_R32_SFLOAT)
    maps = ErosionMaps(drainage_image, new_drainage_image, elevation_image, new_elevation_image, uplift_image, new_uplift_image)
    model = TectonicBasedErosion(1; execution = Erosion.GPU())
    shader = LargeScaleErosion{Float32, typeof(model)}(model, maps)
    # XXX: `image::(SPIRV.Image)[grid_point::GridPoint] = ...` throws a `MethodError`.
    @test_broken compute(device, shader, ShaderParameters(), (32, 32, 1))
  end
end;
