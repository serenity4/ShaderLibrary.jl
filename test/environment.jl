@testset "Environment" begin
  # We use a square color attachment for tests to avoid artifacts
  # caused by a nonzero precision gradient due to otherwise rendering
  # on a wide attachment from a square texture.
  # See `environment_zp_wide.png` which contains such artifacts.
  color_square = color_attachment(device, [1024, 1024])
  parameters_square = ShaderParameters(color_square)
  screen = screen_box(color_square)

  @testset "CubeMap creation & sampling" begin
    cubemap = create_cubemap(device, [read_png(asset("cubemap", face)) for face in ("px.png", "nx.png", "py.png", "ny.png", "pz.png", "nz.png")])
    shader = environment_from_cubemap(cubemap)
    @test isa(shader, Environment)

    hs = [0xd1a6f182e503cd7a, 0xa2491a5a7110082b, 0xcbfd32a0a2878353, 0x4ca916f836758feb, 0x4003c906192c6c9c, 0xaec665db4e257198]
    for (directions, name, h) in zip(CUBEMAP_FACE_DIRECTIONS, fieldnames(CubeMapFaces), hs)
      geometry = Primitive(Rectangle(screen, directions, nothing))
      render(device, shader, parameters_square, geometry)
      data = collect(color_square, device)
      save_test_render("environment_$name.png", data, h)
    end

    geometry = Primitive(Rectangle(color))
    @reset geometry.mesh.vertex_data = cubemap_to_world.(geometry.mesh.vertex_data)
    render(device, shader, parameters, geometry)
    data = collect(color, device)
    save_test_render("environment_zp_wide.png", data, 0xc8cd92c69b67a265)
  end

  @testset "Equirectangular map sampling and conversion to CubeMap" begin
    equirectangular = image_resource(device, read_jpeg(asset("equirectangular.jpeg")); usage_flags = Vk.IMAGE_USAGE_SAMPLED_BIT)
    shader = environment_from_equirectangular(equirectangular)

    uv = spherical_uv_mapping(Vec3(1, 0, 0))
    @test uv == Vec2(0.5, 0.5)
    uv = spherical_uv_mapping(Vec3(0, 1, 0))
    @test uv == Vec2(0.25, 0.5)
    uv = spherical_uv_mapping(Vec3(-1, 0, 0))
    @test uv == Vec2(0, 0.5)
    uv = spherical_uv_mapping(Vec3(0, -1, 0))
    @test uv == Vec2(0.75, 0.5)
    uv = spherical_uv_mapping(Vec3(-1, prevfloat(0F), 0))
    @test uv ≈ Vec2(1, 0.5)

    uv = spherical_uv_mapping(Vec3(0, 0, 1))
    @test uv == Vec2(0.5, 0)
    uv = spherical_uv_mapping(Vec3(0, 0, -1))
    @test uv == Vec2(0.5, 1)
    uv = spherical_uv_mapping(Vec3(-0.0001, 0, 1))
    @test uv == Vec2(0, 0)
    uv = spherical_uv_mapping(Vec3(0.0001, 0, 1))
    @test uv == Vec2(0.5, 0)
    uv = spherical_uv_mapping(Vec3(1, 0, 1))
    @test uv == Vec2(0.5, 0.25)

    hs = [0xd0462159e4ff23f0, 0x2b3a5361a4190c00, 0xb95289590525156a, 0xf8c699acf9480ee8, 0xfa63c70265a4a58f, 0x534bbcf7f4dc1be6]
    for (directions, name, h) in zip(CUBEMAP_FACE_DIRECTIONS, fieldnames(CubeMapFaces), hs)
      geometry = Primitive(Rectangle(screen, directions, nothing))
      render(device, shader, parameters_square, geometry)
      data = collect(color_square, device)
      save_test_render("environment_equirectangular_$name.png", data, h; keep = false)
    end

    cubemap = create_cubemap_from_equirectangular(device, equirectangular)
    cubemap_faces = collect_cubemap_faces(cubemap, device)
    for (name, h) in zip(fieldnames(CubeMapFaces), hs)
      save_test_render("equirectangular_to_cubemap_$name.png", getproperty(cubemap_faces, name), h; keep = false)
    end

    shader = environment_from_cubemap(cubemap)
    for (directions, name, h) in zip(CUBEMAP_FACE_DIRECTIONS, fieldnames(CubeMapFaces), hs)
      geometry = Primitive(Rectangle(screen, directions, nothing))
      render(device, shader, parameters_square, geometry)
      data = collect(color_square, device)
      save_test_render("environment_from_equirectangular_$name.png", data, h; keep = false)
    end
  end

  @testset "Perspective rendering of environments" begin
    equirectangular = image_resource(device, read_jpeg(asset("equirectangular.jpeg")); usage_flags = Vk.IMAGE_USAGE_SAMPLED_BIT)
    cubemap = create_cubemap_from_equirectangular(device, equirectangular)

    gltf = read_gltf("blob.gltf")
    camera = import_camera(gltf)
    env = environment_from_cubemap(cubemap)
    background = renderables(env, parameters, device, Primitive(Rectangle(color, camera)))
    render(device, background)
    data = collect(color, device)
    save_test_render("blob_background.png", data, 0x31c6ac6b43a5e783)
  end
end;
