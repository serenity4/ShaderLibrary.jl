@testset "Scene" begin
  @testset "Camera" begin
    camera = Camera(; focal_length = 0.35, far_clipping_plane = 10)
    p = Vec3(0.4, 0.5, 1.7)
    p′ = project(p, camera)
    @test isa(p′, Vec3)
    @test camera.near_clipping_plane < -p′.z < camera.far_clipping_plane
    p.z = -camera.near_clipping_plane
    @test project(p, camera).z == 0
    p.z = -camera.far_clipping_plane
    @test project(p, camera).z == 1
    p.z = -(camera.near_clipping_plane + camera.far_clipping_plane) / 2
    @test project(p, camera).z == 0.5

    ir = @compile project(::Vec3, ::Camera)
    @test unwrap(validate(ir))
  end

  @testset "Lights" begin
    light = Light(LIGHT_TYPE_POINT, (1.0, 1.0, 1.0), (0.8, 0.8, 0.8), 1000.0, 1.0)
    normal = normalize(light.position) # full incidence
    position = zero(Vec3)
    value = ShaderLibrary.intensity(light, position, normal)
    @test isa(value, Float32)
    @test value > 0
  end

  @testset "GLTF imports" begin
    gltf = read_gltf("blob.gltf");

    camera = read_camera(gltf)
    @test isa(camera, Camera)
    @test camera.transform.translation === Translation(4.1198707F, 3.02657F, 4.3737516F)

    lights = read_lights(gltf)
    @test length(lights) == 1
    light = lights[1]
    @test isa(light, Light)
    @test light.position == Vec3(4.0256276, 4.5642242, -0.28052378)
  end
end;
