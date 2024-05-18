@testset "Physically-based rendering" begin
  gltf = read_gltf("blob.gltf")
  lights = import_lights(gltf)
  camera = import_camera(gltf)
  mesh = import_mesh(gltf)
  mesh_transform = import_transform(gltf.nodes[end]; apply_rotation = false)
  i = last(findmin(v -> distance2(lights[1].position, apply_transform(v, mesh_transform)), mesh.vertex_locations))
  position = apply_transform(mesh.vertex_locations[i], mesh_transform)
  normal = apply_rotation(mesh.vertex_normals[i], mesh_transform.rotation)
  bsdf = BSDF{Float32}((1.0, 0.0, 0.0), 0, 0.5, 0.02)
  scattered = scatter_light_sources(bsdf, position, normal, lights, camera)
  @test all(scattered .≥ 0)

  pbr = PBR(bsdf, lights)
  scattered = compute_lighting_from_sources(pbr, position, normal, camera)
  @test all(scattered .≥ 0)

  # Notes for comparisons with Blender scenes:
  # - GLTF XYZ <=> Blender XZ(-Y)
  # - Blender XYZ <=> GLTF X(-Z)Y

  equirectangular = EquirectangularMap(read_jpeg(asset("equirectangular.jpeg")))
  environment = CubeMap(equirectangular, device)
  irradiance = compute_irradiance(environment, device)

  shader = Environment(irradiance, device)
  screen = screen_box(color)
  directions = face_directions(CubeMap)[1]
  geometry = Primitive(Rectangle(screen, directions, nothing))
  render(device, shader, parameters, geometry)
  data = collect(color, device)
  save_test_render("irradiance_nx.png", data, 0x19d4950653f3984c)

  bsdf = BSDF{Float32}((1.0, 1.0, 1.0), 0.0, 0.1, 0.5)
  lights = [Light{Float32}(LIGHT_TYPE_POINT, (2.0, 1.0, 1.0), (1.0, 1.0, 1.0), 1.0)]
  pbr = PBR(bsdf, lights)
  prog = Program(typeof(pbr), device)
  @test isa(prog, Program)

  @testset "Shaded cube" begin
    gltf = read_gltf("cube.gltf")
    mesh = import_mesh(gltf)
    primitive = Primitive(mesh, FACE_ORIENTATION_COUNTERCLOCKWISE; transform = Transform(rotation = Rotation(RotationPlane(1.0, 0.0, 1.0), 0.3π)))
    camera = import_camera(gltf)
    pbr_parameters = setproperties(parameters, (; camera))

    render(device, pbr, pbr_parameters, primitive)
    data = collect(color, device)
    save_test_render("shaded_cube_pbr.png", data, 0x18e6e9146b6d3548)
  end

  @testset "Shaded blob" begin
    gltf = read_gltf("blob.gltf")
    bsdf = BSDF{Float32}((0.9, 0.4, 1.0), 0, 0.5, 0.02)
    camera = import_camera(gltf)
    mesh = import_mesh(gltf)
    primitive = Primitive(mesh, FACE_ORIENTATION_COUNTERCLOCKWISE; transform = import_transform(gltf.nodes[end]; apply_rotation = false))
    pbr_parameters = setproperties(parameters; camera)

    lights = import_lights(gltf)
    pbr = PBR(bsdf, lights)
    render(device, pbr, pbr_parameters, primitive)
    data = collect(color, device)
    save_test_render("shaded_blob_pbr.png", data, 0x7971a675275af2c8)

    probe = LightProbe(irradiance, irradiance, device)
    pbr = PBR(bsdf, Light{Float32}[], [probe])
    env = Environment(environment, device)
    depth = attachment_resource(Vk.FORMAT_D32_SFLOAT, dimensions(color))
    env_parameters = setproperties(parameters, (; depth, depth_clear = ClearValue(1f0)))
    pbr_parameters = setproperties(parameters, (; camera, depth, color_clear = [nothing]))
    nodes = RenderNode[renderables(env, env_parameters, device, Primitive(Rectangle(color; camera.transform))), renderables(pbr, pbr_parameters, device, primitive)]
    render(device, nodes)
    data = collect(color, device)
    save_test_render("shaded_blob_pbr_ibl.png", data)
  end
end;
