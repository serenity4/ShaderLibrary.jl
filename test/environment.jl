@testset "Environment" begin
  # We use a square color attachment for tests to avoid artifacts
  # caused by a nonzero precision gradient due to otherwise rendering
  # on a wide attachment from a square texture.
  # See `environment_zp_wide.png` which contains such artifacts.
  color_square = color_attachment(device, [1024, 1024])
  parameters_square = ShaderParameters(color_square)
  screen = screen_box(color_square)

  @testset "CubeMap creation & sampling" begin
    images = [read_png(asset("cubemap", face)) for face in ("px.png", "nx.png", "py.png", "ny.png", "pz.png", "nz.png")]
    cubemap = CubeMap(images)
    shader = Environment(cubemap, device)
    @test isa(shader, Environment)

    hs = [0xd1a6f182e503cd7a, 0xa2491a5a7110082b, 0xcbfd32a0a2878353, 0x4ca916f836758feb, 0x4003c906192c6c9c, 0xaec665db4e257198]
    for (directions, name, h) in zip(face_directions(CubeMap), fieldnames(CubeMap), hs)
      geometry = Primitive(Rectangle(screen, directions, nothing))
      render(device, shader, parameters_square, geometry)
      data = collect(color_square, device)
      save_test_render("environment_$name.png", data, h)
    end

    geometry = Primitive(Rectangle(color))
    render(device, shader, parameters, geometry)
    data = collect(color, device)
    save_test_render("environment_zp_wide.png", data, 0x46289a67db54dec4)
  end

  @testset "Equirectangular map sampling and conversion to CubeMap" begin
    equirectangular = EquirectangularMap(read_jpeg(asset("equirectangular.jpeg")))
    shader = Environment(equirectangular, device)

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

    hs = [0xd3941e06837b58df, 0x8f59a7dd59eadec6, (0x3c8f8f5b3535ff3f, 0xcc0b4c5a06ba5247), (0x8d9ce4330af39594, 0xccfeef55a725388c), 0xa5192e2c31023afd, 0x45a62f8c8992d9ed]
    for (directions, name, h) in zip(face_directions(CubeMap), fieldnames(CubeMap), hs)
      geometry = Primitive(Rectangle(screen, directions, nothing))
      render(device, shader, parameters_square, geometry)
      data = collect(color_square, device)
      save_test_render("environment_equirectangular_$name.png", data, h; keep = false)
    end

    cubemap = CubeMap(equirectangular, device)
    shader = Environment(cubemap, device)
    for (name, h) in zip(fieldnames(CubeMap), hs)
      val = getproperty(cubemap, name)
      save_test_render("equirectangular_to_cubemap_$name.png", val, h; keep = false)
    end

    for (directions, name, h) in zip(face_directions(CubeMap), fieldnames(CubeMap), hs)
      geometry = Primitive(Rectangle(screen, directions, nothing))
      render(device, shader, parameters_square, geometry)
      data = collect(color_square, device)
      save_test_render("environment_from_equirectangular_$name.png", data, h; keep = false)
    end
  end
end;
