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
    light = Light{Float32}(LIGHT_TYPE_POINT, (1.0, 1.0, 1.0), (0.8, 0.8, 0.8), 1000.0)
    normal = normalize(light.position) # full incidence
    position = zero(Point3f)
    value = ShaderLibrary.radiance(light, position)
    @test isa(value, Point3f)
    @test all(value .> 0)
  end

  @testset "GLTF imports" begin
    gltf = read_gltf("camera.gltf");
    camera_transform = import_transform(only(gltf.nodes))
    @test camera_transform.rotation === Quaternion{Float32}(-1.0, 0.0, 0.0, -0.0)

    gltf = read_gltf("camera_with_rotation.gltf");
    camera_transform = import_transform(only(gltf.nodes))
    @test camera_transform.rotation === Quaternion{Float32}(0.5221549, 0.80560803, -0.11104996, -0.25693917)

    gltf = read_gltf("sphere.gltf");
    mesh_transform = import_transform(only(gltf.nodes); apply_rotation = false)
    @test mesh_transform.rotation === Quaternion{Float32}(1.0, 0.0, -0.0, 0.0)

    gltf = read_gltf("sphere_with_rotation.gltf");
    mesh_transform = import_transform(only(gltf.nodes); apply_rotation = false)
    @test mesh_transform.rotation === Quaternion{Float32}(0.25103843, -0.043489773, -0.92983365, 0.26551414)

    gltf = read_gltf("blob.gltf");

    camera = import_camera(gltf)
    @test isa(camera, Camera)
    @test camera.transform.translation === Translation(4.1198707F, -4.3737516F, 3.02657F)
    @test camera.transform.rotation === Quaternion{Float32}(-0.7725191, -0.5305388, -0.19752686, -0.28762126)
    @test camera.transform.scaling === one(Scaling{3,Float32})

    lights = import_lights(gltf)
    @test length(lights) == 1
    light = lights[1]
    @test isa(light, Light)
    @test light.position === Point3f(4.0256276, 0.28052378, 4.5642242)

    mesh = import_mesh(gltf)
    @test nv(mesh) == 8249

    mesh_transform = import_transform(gltf.nodes[end]; apply_rotation = false)
    @test mesh_transform.translation === Translation(0.8281484F, -0.32707256F, 0.8672217F)
    @test mesh_transform.rotation === Quaternion{Float32}(1.0, 0.0, -0.0, 0.0)
    @test mesh_transform.scaling === one(Scaling{3,Float32})
  end
end;
