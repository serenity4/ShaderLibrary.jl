@testset "Rendering" begin
  @testset "Triangle" begin
    grad = Gradient()
    vertex_locations = Vec2[(-0.4, -0.4), (0.4, -0.4), (0.0, 0.6)]
    vertex_data = Vec3[(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)]
    mesh = VertexMesh(1:3, vertex_locations; vertex_data)
    primitive = Primitive(mesh, FACE_ORIENTATION_COUNTERCLOCKWISE)
    @test_throws "At least one color attachment" Command(grad, ShaderParameters(), device, primitive)
    command = Command(grad, parameters, device, primitive)
    render(device, command)
    data = collect(color, device)
    save_test_render("triangle.png", data, 0x82c2a039f91ec3b2)
  end

  @testset "Rectangle" begin
    grad = Gradient()
    rect = Rectangle(Point2(0.5, 0.5), fill(Vec3(1.0, 0.0, 1.0), 4), nothing) # actually a square
    primitive = Primitive(rect, Point2(-0.4, -0.4))
    render(device, grad, parameters, primitive)
    data = collect(color, device)
    save_test_render("rectangle.png", data, 0xe0c150b540769d0b)
  end

  @testset "Sprites" begin
    texture = image_resource(device, read_texture("normal.png"); usage_flags = Vk.IMAGE_USAGE_SAMPLED_BIT)
    vertex_locations = Vec2[(-0.4, -0.4), (0.4, -0.4), (0.0, 0.6)]
    vertex_data = Vec2[(0.0, 1.0), (1.0, 1.0), (0.5, 0.0)]
    mesh = VertexMesh(1:3, vertex_locations; vertex_data)
    sprite = Sprite(texture)
    primitive = Primitive(mesh, FACE_ORIENTATION_COUNTERCLOCKWISE)
    render(device, sprite, parameters, primitive)
    data = collect(color, device)
    save_test_render("sprite_triangle.png", data, 0xed065808b4f1105a)
  end

  @testset "Glyph rendering" begin
    font = OpenTypeFont(font_file("juliamono-regular.ttf"));
    glyph = font['A']
    curves = map(x -> Arr{3,Vec2}(Vec2.(x)), OpenType.curves_normalized(glyph))
    qbf = QuadraticBezierFill(curves)
    data = QuadraticBezierPrimitiveData(eachindex(curves), 3.6, Vec3(0.6, 0.4, 1.0))
    coordinates = Vec2[(0, 0), (1, 0), (0, 1), (1, 1)]
    rect = Rectangle(Point2(0.5, 0.5), coordinates, data)
    primitive = Primitive(rect)
    render(device, qbf, parameters, primitive)
    data = collect(color, device)
    save_test_render("glyph.png", data, 0xc3d62747ac33c5af)
  end

  @testset "Blur" begin
    texture = image_resource(device, read_texture("normal.png"); usage_flags = Vk.IMAGE_USAGE_SAMPLED_BIT, name = :normal_map)
    vertex_locations = Vec2[(-0.4, -0.4), (0.4, -0.4), (0.0, 0.6)]
    vertex_data = Vec2[(0.0, 1.0), (1.0, 1.0), (0.5, 0.0)]
    mesh = VertexMesh(1:3, vertex_locations; vertex_data)
    primitive = Primitive(mesh, FACE_ORIENTATION_COUNTERCLOCKWISE)

    directional_blur = GaussianBlurDirectional(texture, BLUR_HORIZONTAL, 0.02)
    render(device, directional_blur, parameters, primitive)
    data = collect(color, device)
    save_test_render("blurred_triangle_horizontal.png", data, 0x7005c020ed6c6eee)

    directional_blur = GaussianBlurDirectional(texture, BLUR_VERTICAL, 0.02)
    render(device, directional_blur, parameters, primitive)
    data = collect(color, device)
    save_test_render("blurred_triangle_vertical.png", data, 0x62d575bcc0946a2b)

    # Need to specify dimensions of the whole texture for the first pass.
    blur = GaussianBlur(texture, 0.02)
    render(device, blur, parameters, primitive)
    data = collect(color, device)
    save_test_render("blurred_triangle.png", data, 0xd3ca709f7c08fdd6)
  end

  @testset "Text rendering" begin
    font = OpenTypeFont(font_file("juliamono-regular.ttf"));
    options = FontOptions(ShapingOptions(tag"latn", tag"fra "), 1/10)
    text = OpenType.Text("The brown fox jumps over the lazy dog.", TextOptions())
    line = only(lines(text, [font => options]))
    segment = only(line.segments)
    (; quads, curves) = glyph_quads(line, segment, zero(Point3f))
    @test length(quads) == count(!isspace, text.chars)
    @test length(unique(rect.data.range for rect in quads)) == length(line.outlines)

    render(device, Text(text, font, options), parameters, (-1, 0))
    data = collect(color, device)
    save_test_render("text.png", data, 0x18a71da4d048546b)

    font = OpenTypeFont(font_file("NotoSerifLao.ttf"));
    options = FontOptions(ShapingOptions(tag"lao ", tag"dflt"; enabled_features = Set([tag"aalt"])), 1/2)
    text = OpenType.Text("ກີບ ສົ \ue99\ueb5\uec9", TextOptions())
    render(device, Text(text, font, options), parameters, (-1, 0))
    data = collect(color, device)
    save_test_render("text_lao.png", data, 0x3a656604417e8f07)
  end

  @testset "Environment" begin
    images = [read_png(asset("cubemap", face)) for face in ("px.png", "nx.png", "py.png", "ny.png", "pz.png", "nz.png")]
    cubemap = CubeMap(images)
    shader = Environment(device, cubemap)
    @test isa(shader, Environment)

    # We use a square color attachment for tests to avoid artefacts
    # caused by a nonzero precision gradient due to otherwise rendering
    # on a wide attachment from a square texture.
    # See `environment_3_wide.png` which contains such artefacts.
    color_square = color_attachment(device, [1024, 1024])
    parameters_square = ShaderParameters(color_square)
    screen = screen_box(color_square)

    rotation = Rotation(RotationPlane((1, 0, 0), (0, 1, 0)), 0°)
    directions = [apply_rotation(Point3f(xy..., -1), rotation) for xy in PointSet(screen)]
    geometry = Primitive(Rectangle(screen, directions, nothing))
    render(device, shader, parameters_square, geometry)
    data = collect(color_square, device)
    save_test_render("environment_1.png", data, 0xac54a6902a9f609a)

    rotation = Rotation(RotationPlane((1, 0, 0), (0, 1, 0)), 10°)
    directions = [apply_rotation(Point3f(xy..., -1), rotation) for xy in PointSet(screen)]
    geometry = Primitive(Rectangle(screen, directions, nothing))
    render(device, shader, parameters_square, geometry)
    data = collect(color_square, device)
    save_test_render("environment_2.png", data, 0x99950cb2f16d317c)

    rotation = Rotation(RotationPlane((1, 0, 0), (0, 0, 1)), 45°)
    directions = [apply_rotation(Point3f(xy..., -1), rotation) for xy in PointSet(screen)]
    geometry = Primitive(Rectangle(screen, directions, nothing))
    render(device, shader, parameters_square, geometry)
    data = collect(color_square, device)
    save_test_render("environment_3.png", data, 0x54be001651e90148)

    screen = screen_box(color)
    rotation = Rotation(RotationPlane((1, 0, 0), (0, 0, 1)), 45°)
    directions = [apply_rotation(Point3f(xy..., -1), rotation) for xy in PointSet(screen)]
    geometry = Primitive(Rectangle(screen, directions, nothing))
    render(device, shader, parameters, geometry)
    data = collect(color, device)
    save_test_render("environment_3_wide.png", data, 0x6dc080b417c2e94f)
  end

  @testset "Meshes" begin
    colors = Vec3[(0.43, 0.18, 0.68),
                  (0.76, 0.37, 0.76),
                  (0.02, 0.27, 0.27),
                  (0.10, 0.17, 0.57),
                  (0.60, 0.71, 0.60),
                  (0.84, 0.73, 0.35),
                  (0.41, 0.19, 0.54),
                  (0.61, 0.49, 0.44),
                  (0.70, 0.75, 0.27),
                  (0.91, 0.06, 0.61),
                  (0.17, 0.78, 0.39),
                  (0.39, 0.28, 0.25),
                  (0.31, 0.15, 0.65),
                  (0.03, 0.96, 0.54),
                  (0.49, 0.05, 0.29),
                  (0.53, 0.81, 0.18),
                  (0.90, 0.63, 0.97),
                  (0.70, 0.51, 0.09),
                  (0.90, 0.84, 0.74),
                  (0.66, 0.30, 0.86),
                  (0.01, 0.78, 0.18),
                  (0.91, 0.53, 0.98),
                  (0.16, 0.01, 0.53),
                  (0.49, 0.05, 0.38)]
    mesh = import_mesh(read_gltf("cube.gltf"))
    mesh = VertexMesh(mesh.encoding, mesh.vertex_locations; mesh.vertex_normals, vertex_data = colors)
    primitive = Primitive(mesh, FACE_ORIENTATION_COUNTERCLOCKWISE; transform = Transform(rotation = Rotation(RotationPlane(1.0, 0.0, 1.0), 0.3π)))
    grad = Gradient()
    camera = Camera(focal_length = 2, near_clipping_plane = -2)
    cube_parameters = setproperties(parameters, (; camera))
    render(device, grad, cube_parameters, primitive)
    data = collect(color, device)
    save_test_render("colored_cube.png", data, 0x6c3e00f2bce3a00a)
  end

  @testset "PBR" begin
    bsdf = BSDF{Float32}((1.0, 1.0, 1.0), 0.0, 0.1, 0.5)
    lights = [Light{Float32}(LIGHT_TYPE_POINT, (2.0, 1.0, 1.0), (1.0, 1.0, 1.0), 1.0)]
    lights_buffer = Buffer(device; data = lights)
    pbr = PBR(bsdf, PhysicalBuffer{Light{Float32}}(length(lights), lights_buffer))
    prog = Program(typeof(pbr), device)
    @test isa(prog, Program)

    mesh = import_mesh(read_gltf("cube.gltf"))
    primitive = Primitive(mesh, FACE_ORIENTATION_COUNTERCLOCKWISE; transform = Transform(rotation = Rotation(RotationPlane(1.0, 0.0, 1.0), 0.3π)))
    camera = Camera(focal_length = 2, near_clipping_plane = -2)
    cube_parameters = setproperties(parameters, (; camera))

    render(device, pbr, cube_parameters, primitive)
    data = collect(color, device)
    save_test_render("shaded_cube_pbr.png", data)

    # empty!(device.shader_cache)
    gltf = read_gltf("blob.gltf")
    bsdf = BSDF{Float32}((1.0, 0.0, 0.0), 0, 0.5, 0.02)
    lights = import_lights(gltf)
    lights_buffer = Buffer(device; data = lights)
    pbr = PBR(bsdf, PhysicalBuffer{Light{Float32}}(length(lights), lights_buffer))
    camera = import_camera(gltf)
    mesh = import_mesh(gltf)
    primitive = Primitive(mesh, FACE_ORIENTATION_COUNTERCLOCKWISE; transform = import_transform(gltf.nodes[end]; apply_rotation = false))
    cube_parameters = setproperties(parameters, (; camera))

    render(device, pbr, cube_parameters, primitive)
    data = collect(color, device)
    # XXX: specular reflections seem off under high-intensity lighting at high incidence.
    save_test_render("shaded_blob_pbr.png", data, 0xc3b162f3709518d0)
  end
end;
