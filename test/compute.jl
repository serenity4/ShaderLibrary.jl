using ShaderLibrary: linearize_index, image_index

@testset "Computing with compute shaders" begin
  @testset "Index computation" begin
    @test linearize_index((0, 0, 0), (8, 1, 1), (0, 0, 0), (8, 8, 1)) == 0
    @test linearize_index((1, 0, 0), (8, 1, 1), (0, 0, 0), (8, 8, 1)) == 64
    @test linearize_index((1, 0, 0), (8, 1, 1), (1, 0, 0), (8, 8, 1)) == 65
    @test linearize_index((7, 0, 0), (8, 1, 1), (7, 7, 0), (8, 8, 1)) == 511
  
    @test image_index(0, (20, 10)) == (0, 0)
    @test image_index(13, (20, 10)) == (13, 0)
    @test image_index(184, (20, 10)) == (4, 9)
  end;

  @testset "Large-scale terrain erosion" begin
    nx, ny = (256, 256)
    drainage_image = image_resource(device, zeros(Float32, nx, ny); format = Vk.FORMAT_R32_SFLOAT)
    new_drainage_image = image_resource(device, zeros(Float32, nx, ny); format = Vk.FORMAT_R32_SFLOAT)
    elevation_image = image_resource(device, zeros(Float32, nx, ny); format = Vk.FORMAT_R32_SFLOAT)
    new_elevation_image = image_resource(device, zeros(Float32, nx, ny); format = Vk.FORMAT_R32_SFLOAT)
    uplift_image = image_resource(device, zeros(Float32, nx, ny); format = Vk.FORMAT_R32_SFLOAT)
    new_uplift_image = image_resource(device, zeros(Float32, nx, ny); format = Vk.FORMAT_R32_SFLOAT)
    maps = ErosionMaps(drainage_image, new_drainage_image, elevation_image, new_elevation_image, uplift_image, new_uplift_image)
    model = TectonicBasedErosion{Erosion.GPU}(nothing, 1)
    shader = LargeScaleErosion{Float32, typeof(model)}(model, maps)
    compute(device, shader, (32, 32, 1))
  end
end
