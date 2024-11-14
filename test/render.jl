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
    save_test_render("triangle.png", data, 0xe13e13a928971a82)

    # This time, specify vertex locations in pixels.
    vertex_locations = Vec2[(-40, -40), (40, -40), (0, 60)]
    mesh = VertexMesh(1:3, vertex_locations; vertex_data)
    primitive = Primitive(mesh, FACE_ORIENTATION_COUNTERCLOCKWISE)
    command = Command(grad, (@set parameters.unit = UNIT_PIXEL), device, primitive)
    render(device, command)
    data = collect(color, device)
    save_test_render("small_triangle.png", data, 0xd2a6f09f2469722f)
  end

  @testset "Rectangle" begin
    grad = Gradient()
    rect = Rectangle(Vec2(0.5, 0.5), fill(Vec3(1.0, 0.0, 1.0), 4), nothing) # actually a square
    primitive = Primitive(rect, Vec2(-0.4, -0.4))
    render(device, grad, parameters, primitive)
    data = collect(color, device)
    save_test_render("rectangle.png", data, 0x79bb773f3f4ca5e1)
  end

  @testset "Sprites" begin
    texture = image_resource(device, read_texture("normal.png"); usage_flags = Vk.IMAGE_USAGE_SAMPLED_BIT)
    vertex_locations = Vec2[(-0.4, -0.4), (0.4, -0.4), (0.0, 0.6)]
    uvs = Vec2[(0.0, 1.0), (1.0, 1.0), (0.5, 0.0)]
    mesh = VertexMesh(1:3, vertex_locations; vertex_data = uvs)
    sprite = Sprite(texture)
    primitive = Primitive(mesh, FACE_ORIENTATION_COUNTERCLOCKWISE)
    render(device, sprite, parameters, primitive)
    data = collect(color, device)
    save_test_render("sprite_triangle.png", data, 0x836d666543dc2f87)

    texture = image_resource(device, read_texture("normal.png"); usage_flags = Vk.IMAGE_USAGE_SAMPLED_BIT)
    uvs = Vec2[(0.0, 1.0), (1.0, 1.0), (0.0, 0.0), (1.0, 0.0)]
    rect = Rectangle(Point2(0.5, 0.5), uvs, nothing)
    sprite = Sprite(texture)
    primitive = Primitive(rect)
    render(device, sprite, parameters, primitive)
    data = collect(color, device)
    save_test_render("sprite_rectangle.png", data, 0x83c64ebd09e13704)
  end

  @testset "Blur" begin
    texture = image_resource(device, read_texture("normal.png"); usage_flags = Vk.IMAGE_USAGE_SAMPLED_BIT, name = :normal_map)
    vertex_locations = Vec2[(-0.4, -0.4), (0.4, -0.4), (0.0, 0.6)]
    uvs = Vec2[(0.0, 1.0), (1.0, 1.0), (0.5, 0.0)]
    mesh = VertexMesh(1:3, vertex_locations; vertex_data = uvs)
    primitive = Primitive(mesh, FACE_ORIENTATION_COUNTERCLOCKWISE)

    directional_blur = GaussianBlurDirectional(texture, BLUR_HORIZONTAL, 0.02)
    render(device, directional_blur, parameters, primitive)
    data = collect(color, device)
    save_test_render("blurred_triangle_horizontal.png", data, 0x0676ff22a882d5f1)

    directional_blur = GaussianBlurDirectional(texture, BLUR_VERTICAL, 0.02)
    render(device, directional_blur, parameters, primitive)
    data = collect(color, device)
    save_test_render("blurred_triangle_vertical.png", data, 0xb38fadbdbc250416)

    # Need to specify dimensions of the whole texture for the first pass.
    blur = GaussianBlur(texture, 0.02)
    render(device, blur, parameters, primitive)
    data = collect(color, device)
    save_test_render("blurred_triangle.png", data, 0xc980df4399b8e477)
  end

  @testset "Glyph rendering" begin
    @testset "Alpha calculation" begin
      @testset "Winding number calculation" begin
        control_points = Vec2[(0, 0), (1, 1), (1, 0)]
        point = Vec2(0, 0)
        alpha = ShaderLibrary.intensity(BezierCurve(control_points .- (point,)), 1F)
        @test isa(alpha, Float32)
        point = Vec2(0, 0.5) # outside
        alpha = ShaderLibrary.intensity(BezierCurve(control_points .- (point,)), 1F)
        @test alpha === 0F
        point = Vec2(0.5, 0.25) # inside
        alpha = ShaderLibrary.intensity(BezierCurve(control_points .- (point,)), 1F)
        @test alpha ≥ 1F
      end

      @testset "Weighted containment test" begin
        # Normalized curves.
        font = OpenTypeFont(font_file("juliamono-regular.ttf"));
        glyph = font['A']
        curves = map(x -> Arr{3,Vec2}(Vec2.(x)), OpenType.curves_normalized(glyph))
        point = Vec2(0.05, 0.01) # inside
        alpha = ShaderLibrary.intensity(point, curves, 100F)
        @test alpha === 1F
        point = Vec2(0, 0.5) # outside
        alpha = ShaderLibrary.intensity(point, curves, 100F)
        @test alpha === 0F

        # Unnormalized curves.
        curves = map(x -> Arr{3,Vec2}(Vec2.(x)), OpenType.curves(glyph))
        point = Vec2(47, 3) # inside
        alpha = ShaderLibrary.intensity(point, curves, 100F)
        point = Vec2(100, 34) # inside
        alpha = ShaderLibrary.intensity(point, curves, 100F)
        point = Vec2(100, 34.000095f0) # inside
        alpha = ShaderLibrary.intensity(point, curves, 100F)
        @test alpha === 1F
        point = Vec2(45, 300) # outside
        alpha = ShaderLibrary.intensity(point, curves, 100F)
        @test alpha === 0F

        # For debugging on the CPU.
        # data = [ShaderLibrary.intensity(Vec2(x, y), curves, 100000F) for x in 1:550, y in 1:550]
        # data = RGBA{Float16}.(1, 1, 1, data)
        # save_test_render("glyph.png", data)
      end
    end

    font = OpenTypeFont(font_file("juliamono-regular.ttf"));
    glyph = font['A']
    curves = map(x -> Arr{3,Vec2}(Vec2.(x)), OpenType.curves_normalized(glyph))
    qbf = QuadraticBezierFill(curves)
    data = QuadraticBezierPrimitiveData(eachindex(curves), 0.5/pixel_size(parameters), Vec3(0.6, 0.4, 1.0))
    uvs = Vec2[(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)]
    rect = Rectangle(Vec2(0.5, 0.5), uvs, data)
    primitive = Primitive(rect)
    render(device, qbf, parameters, primitive)
    data = collect(color, device)
    save_test_render("glyph.png", data, 0x09f925148855e2bc)

    font = OpenTypeFont(font_file("juliamono-regular.ttf"));
    glyph = font['A']
    curves = map(x -> Arr{3,Vec2}(Vec2.(x)), OpenType.curves(glyph))
    qbf = QuadraticBezierFill(curves)
    data = QuadraticBezierPrimitiveData(eachindex(curves), 100000F, Vec3(0.6, 0.4, 1.0))
    vertex_data = Vec2[(0, 0), (550, 0), (0, 550), (550, 550)]
    rect = Rectangle(Vec2(0.5, 0.5), vertex_data, data)
    primitive = Primitive(rect)
    render(device, qbf, parameters, primitive)
    data = collect(color, device)
    save_test_render("glyph_unnormalized.png", data, 0x0b7ae4fb246f7a73; keep = false)
  end

  @testset "Text rendering" begin
    font = OpenTypeFont(font_file("juliamono-regular.ttf"));
    px = pixel_size(parameters)
    options = FontOptions(ShapingOptions(tag"latn", tag"fra "), 48px)
    text = OpenType.Text("The brown fox jumps over the lazy dog.", TextOptions())
    line = only(lines(text, [font => options]))
    segment = only(line.segments)
    (; quads, curves) = glyph_quads(line, segment, zero(Vec3), Vec3(1, 1, 1))
    @test length(quads) == count(!isspace, text.chars)
    @test length(unique(rect.data.range for rect in quads)) == length(line.outlines)

    # Enable fragment supersampling to reduce aliasing artifacts.
    parameters_ssaa = @set parameters.render_state.enable_fragment_supersampling = true

    text = OpenType.Text("The brown fox jumps over the lazy dog.", TextOptions())
    render(device, Text(text, font, options), parameters_ssaa, (-1, 0))
    data = collect(color, device)
    save_test_render("text.png", data, 0x8aa232d949de880a)

    text = OpenType.Text(styled"The{background=red: }{color=brown:brown} {underline:fo{size=$(30px):x}}{size=$(108px): {background=orange:jumps} {cyan:over} }the {color=purple:{strikethrough:l{size=$(100px):a}zy} beautiful} dog.", TextOptions())
    render(device, Text(text, font, options), parameters_ssaa, (-1.7, 0))
    data = collect(color, device)
    save_test_render("text_rich.png", data, 0xaf02396a74ffda42)

    font = OpenTypeFont(font_file("NotoSerifLao.ttf"));
    options = FontOptions(ShapingOptions(tag"lao ", tag"dflt"; enabled_features = Set([tag"aalt"])), 200px)
    text = OpenType.Text("ກີບ ສົ \ue99\ueb5\uec9", TextOptions())
    render(device, Text(text, font, options), parameters_ssaa, (-1, 0))
    data = collect(color, device)
    save_test_render("text_lao.png", data, 0xead7f7a2819b944f)
  end

  @testset "Meshes" begin
    gltf = read_gltf("cube.gltf")
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
    mesh = import_mesh(gltf)
    mesh = VertexMesh(mesh.encoding, mesh.vertex_locations; mesh.vertex_normals, vertex_data = colors)
    primitive = Primitive(mesh, FACE_ORIENTATION_COUNTERCLOCKWISE)
    grad = Gradient()
    camera = import_camera(gltf)
    cube_parameters = setproperties(parameters, (; camera))
    render(device, grad, cube_parameters, primitive)
    data = collect(color, device)
    save_test_render("colored_cube_perspective.png", data, 0xdc62ddd8daf0638c)
    @reset camera.focal_length = 0
    @reset camera.near_clipping_plane = -10
    @reset camera.far_clipping_plane = 10
    @reset camera.extent = (6F, 6F)
    cube_parameters = setproperties(parameters, (; camera))
    render(device, grad, cube_parameters, primitive)
    data = collect(color, device)
    save_test_render("colored_cube_orthographic.png", data, 0xa7b8106a1ce942eb)
  end
end;
