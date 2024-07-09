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
    pbr_parameters = setproperties(parameters; camera)

    render(device, pbr, pbr_parameters, primitive)
    data = collect(color, device)
    save_test_render("shaded_cube_pbr.png", data, 0x6462f25893468519)
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
    save_test_render("shaded_blob_pbr.png", data, 0x4a2cb75b7bc83a4f)
  end

  @testset "Image-based lighting" begin
    equirectangular = image_resource(device, read_jpeg(asset("equirectangular.jpeg")); usage_flags = Vk.IMAGE_USAGE_SAMPLED_BIT)
    cubemap = create_cubemap_from_equirectangular(device, equirectangular)
    screen = screen_box(color)

    irradiance = compute_irradiance(cubemap, device)
    shader = environment_from_cubemap(irradiance)
    directions = CUBEMAP_FACE_DIRECTIONS[1]
    geometry = Primitive(Rectangle(screen, directions, nothing))
    render(device, shader, parameters, geometry)
    data = collect(color, device)
    save_test_render("irradiance_nx.png", data, 0x6f7797a2c29a23c9)

    prefiltered_environment = compute_prefiltered_environment(cubemap, device; mip_levels = 1)
    shader = environment_from_cubemap(prefiltered_environment)
    directions = CUBEMAP_FACE_DIRECTIONS[5]
    geometry = Primitive(Rectangle(screen, directions, nothing))
    render(device, shader, parameters, geometry)
    data = collect(color, device)
    save_test_render("prefiltered_pz_mip1.png", data, 0x11deaf2c1a86fd84)

    prefiltered_environment = compute_prefiltered_environment(cubemap, device; base_resolution = 1024)
    @test prefiltered_environment.image.mip_levels > 4
    data = collect(ImageView(prefiltered_environment.image; layer_range = 5:5, mip_range = 2:2), device)
    @test size(data) == (512, 512)
    save_test_render("prefiltered_pz_mip2.png", data, 0x19afaa4e20b9bd72)
    data = collect(ImageView(prefiltered_environment.image; layer_range = 5:5, mip_range = 4:4), device)
    @test size(data) == (128, 128)
    save_test_render("prefiltered_pz_mip4.png", data, 0x6607c8646b2745f9)

    uvs = Vec2[(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)]
    shader = BRDFIntegration()
    brdf_integration_map_color = similar(color; dims = [512, 512], usage_flags = color.attachment.view.image.usage_flags | Vk.IMAGE_USAGE_SAMPLED_BIT)
    geometry = Primitive(Rectangle(screen_box(1.0), uvs, nothing))
    render(device, shader, (@set parameters.color[1] = brdf_integration_map_color), geometry)
    data = collect(brdf_integration_map_color, device)
    save_test_render("brdf_integration_map.png", data, 0x2fa125c4d084a5b5)
    brdf_integration_map = Resource(brdf_integration_map_color.attachment.view.image; name = :brdf_integration_map)

    @testset "Shading" begin
      gltf = read_gltf("blob.gltf")
      camera = import_camera(gltf)
      mesh = import_mesh(gltf)
      primitive = Primitive(mesh, FACE_ORIENTATION_COUNTERCLOCKWISE; transform = import_transform(gltf.nodes[end]; apply_rotation = false))
      probe = LightProbe(irradiance, prefiltered_environment, brdf_integration_map, device)

      function render_pbr_blob(bsdf::BSDF)
        pbr = PBR(bsdf, Light{Float32}[], [probe])
        env = environment_from_cubemap(cubemap)
        depth = attachment_resource(Vk.FORMAT_D32_SFLOAT, dimensions(color))
        env_parameters = setproperties(parameters, (; depth, depth_clear = ClearValue(1f0)))
        pbr_parameters = setproperties(parameters, (; camera, depth, color_clear = [nothing]))
        background = renderables(env, env_parameters, device, Primitive(Rectangle(color, camera)))
        blob = renderables(pbr, pbr_parameters, device, primitive)
        nodes = RenderNode[background, blob]
        render(device, nodes)
      end

      @testset "Specular only" begin
        # Dielectric
        bsdf = BSDF{Float32}((0.0, 0.0, 0.0), 0, 0.3, 0.02)
        render_pbr_blob(bsdf)
        data = collect(color, device)
        save_test_render("shaded_blob_pbr_ibl_dielectric.png", data)

        # Metallic (black)
        bsdf = BSDF{Float32}((0.0, 0.0, 0.0), 1, 0.3, 0.02)
        render_pbr_blob(bsdf)
        data = collect(color, device)
        save_test_render("shaded_blob_pbr_ibl_metallic.png", data)

        # Metallic (colored)
        bsdf = BSDF{Float32}((0.9, 0.4, 1.0), 1, 0.3, 0.02)
        render_pbr_blob(bsdf)
        data = collect(color, device)
        save_test_render("shaded_blob_pbr_ibl_metallic_colored.png", data)
      end

      @testset "Specular + Diffuse" begin
        # Dielectric (colored)
        bsdf = BSDF{Float32}((0.9, 0.4, 1.0), 0, 0.3, 0.02)
        render_pbr_blob(bsdf)
        data = collect(color, device)
        save_test_render("shaded_blob_pbr_ibl_dielectric_colored.png", data)
      end
    end
  end
end;
