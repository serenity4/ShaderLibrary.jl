@testset "Computing with compute shaders" begin
  @testset "Gamma correction" begin
    texture = read_texture("boid.png")
    image = image_resource(device, texture; usage_flags = Vk.IMAGE_USAGE_STORAGE_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT)
    @test collect(image, device) == texture
    shader = GammaCorrection(image)
    compute(device, shader, ShaderParameters(), (64, 64, 1))
    data = collect(shader.color, device)
    save_test_render("gamma_correction.png", data, 0x70b485a2e3edf5b9)
  end

  @testset "Gaussian blur" begin
    texture = read_texture("normal.png")
    source = image_resource(device, texture; usage_flags = Vk.IMAGE_USAGE_STORAGE_BIT)
    destination = similar(source; usage_flags = Vk.IMAGE_USAGE_STORAGE_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT)
    shader = GaussianBlurDirectionalComp{RGBA{Float16}}(source, destination, BLUR_HORIZONTAL, 8)
    compute(device, shader, ShaderParameters(), (64, 64, 1))
    data = collect(shader.destination, device)
    save_test_render("gaussian_blur_vertical.png", data, 0xd9e6eed17d68e31a)

    destination = similar(source; usage_flags = Vk.IMAGE_USAGE_STORAGE_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT)
    shader = GaussianBlurComp{RGBA{Float16}}(source, destination, 8)
    compute(device, shader, ShaderParameters(), (64, 64, 1))
    data = collect(shader.destination, device)
    save_test_render("gaussian_blur.png", data, 0x24482d322565a305)
  end

  @testset "Mipmap generation" begin
    texture = read_texture("normal.png")
    image = image_resource(device, texture; usage_flags = Vk.IMAGE_USAGE_STORAGE_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT)
    @test collect(image, device) == texture
    nx, ny = size(texture)
    mipmap = image_resource(device, fill(RGBA{Float16}(0.0, 0.0, 0.0, 1.0), nx ÷ 2, ny ÷ 2); usage_flags = Vk.IMAGE_USAGE_STORAGE_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT)
    shader = MipmapGamma(image, mipmap)
    compute(device, shader, ShaderParameters(), (64, 64, 1))
    data = collect(shader.mipmap, device)
    save_test_render("mipmap_gamma.png", data, 0xf371ddeeadd54ab0)

    image = image_resource(device, nothing; dims = size(texture), format = eltype(texture), usage_flags = Vk.IMAGE_USAGE_STORAGE_BIT | Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_TRANSFER_DST_BIT, mip_levels = 6)
    copyto!(image, texture, device; mip_level = 1)
    generate_mipmaps(image, device)
    data = collect(image, device; mip_level = 4)
    save_test_render("texture_mipmap_4.png", data, 0xe4a93750f02b4be5)
  end

  @testset "Large-scale terrain erosion" begin
    resolution = 256
    nx, ny = (resolution, resolution)
    uplift = imresize(read_png(Float32, asset("uplift/radial.png")), (nx, ny))
    uplift = remap.(uplift, extrema(uplift)..., 0.4F, 10F)
    elevation = zeros(Float32, nx, ny)

    usage_flags = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_STORAGE_BIT
    elevation_image = image_resource(device, elevation; format = Vk.FORMAT_R32_SFLOAT, usage_flags)
    uplift_image = image_resource(device, uplift; format = Vk.FORMAT_R32_SFLOAT, usage_flags)
    drainage_image = image_resource(device, zeros(Float32, nx, ny); format = Vk.FORMAT_R32_SFLOAT, usage_flags)
    new_elevation_image = image_resource(device, zeros(Float32, nx, ny); format = Vk.FORMAT_R32_SFLOAT, usage_flags)
    new_uplift_image = image_resource(device, zeros(Float32, nx, ny); format = Vk.FORMAT_R32_SFLOAT, usage_flags)
    new_drainage_image = image_resource(device, zeros(Float32, nx, ny); format = Vk.FORMAT_R32_SFLOAT, usage_flags)
    maps = ErosionMaps(drainage_image, new_drainage_image, elevation_image, new_elevation_image, uplift_image, new_uplift_image)
    model = TectonicBasedErosion{GPU,Float32,UInt32}(nothing, 2000; speed = 100, smooth_factor = 0, stream_power = 0.0005, uplift_factor = 0.01, inverse_momentum_power = Inf32, scale = (150_000, 150_000), execution = Erosion.GPU())
    shader = LargeScaleErosion{Float32, typeof(model)}(model, maps)
    commands = renderables(shader, ShaderParameters(), device, (cld(nx, 32), cld(ny, 32), 1))
    for i in 1:model.iterations
      render(device, commands)
      # i % 20 == 0 && (data = collect(elevation_image, device); display(save_test_render(tempname() * ".png", remap.(data, extrema(data)..., 0F, 1F))))
    end
    # XXX: This used to render fine and faster, but now seems to run into race conditions.
    # nodes = RenderNode[]
    # for i in 1:model.iterations
    #   for command in commands
    #     push!(nodes, RenderNode(command))
    #   end
    # end
    # @time render(device, nodes)

    data = collect(elevation_image, device)
    data = remap.(data, extrema(data)..., 0F, 1F)
    save_test_render("erosion.png", data, 0xb11688314b664975)
  end
end;
