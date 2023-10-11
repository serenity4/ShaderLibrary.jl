@testset "Rendering" begin
  @testset "Triangle" begin
    grad = Gradient(color)
    vertices = [Vertex(Vec2(-0.4, -0.4), Vec3(1.0, 0.0, 0.0)), Vertex(Vec2(0.4, -0.4), Vec3(0.0, 1.0, 0.0)), Vertex(Vec2(0.0, 0.6), Vec3(0.0, 0.0, 1.0))]
    primitive = Primitive(TriangleStrip(1:3), vertices, FACE_ORIENTATION_COUNTERCLOCKWISE)
    command = Command(grad, device, primitive)
    render(device, command)
    data = collect(color, device)
    save_test_render("triangle.png", data)
  end

  @testset "Rectangle" begin
    grad = Gradient(color)
    rect = Rectangle(Point2(0.5, 0.5), Point2(-0.4, -0.4), fill(Vec3(1.0, 0.0, 1.0), 4), nothing) # actually a square
    primitive = Primitive(rect)
    render(device, grad, primitive)
    data = collect(color, device)
    save_test_render("rectangle.png", data, 0xe0c150b540769d0b)
  end

  @testset "Sprites" begin
    texture = image_resource(device, read_texture("normal.png"); usage_flags = Vk.IMAGE_USAGE_SAMPLED_BIT)
    sprite = Sprite(color, texture)
    vertices = [Vertex(Vec2(-0.4, -0.4), Vec2(0.0, 0.0)), Vertex(Vec2(0.4, -0.4), Vec2(1.0, 0.0)), Vertex(Vec2(0.0, 0.6), Vec2(0.5, 1.0))]
    primitive = Primitive(TriangleStrip(1:3), vertices, FACE_ORIENTATION_COUNTERCLOCKWISE)
    render(device, sprite, primitive)
    data = collect(color, device)
    save_test_render("sprite_triangle.png", data, 0x231cf3602440b50c)
  end

  @testset "Glyph rendering" begin
    font = OpenTypeFont(font_file("juliamono-regular.ttf"));
    glyph = font['A']
    curves = map(x -> Arr{3,Vec2}(Vec2.(x)), OpenType.curves_normalized(glyph))
    qbf = QuadraticBezierFill(color, curves)
    data = QuadraticBezierPrimitiveData(eachindex(curves) .- 1, 3.6, Vec3(0.6, 0.4, 1.0))
    coordinates = Vec2[(0, 0), (1, 0), (0, 1), (1, 1)]
    rect = Rectangle(Point2(0.5, 0.5), Point2(0.0, 0.0), coordinates, data)
    primitive = Primitive(rect)
    render(device, qbf, primitive)
    data = collect(color, device)
    save_test_render("glyph.png", data, 0xc3d62747ac33c5af)
  end

  @testset "Blur" begin
    texture = image_resource(device, read_texture("normal.png"); usage_flags = Vk.IMAGE_USAGE_SAMPLED_BIT, name = :normal_map)
    vertices = [Vertex(Vec2(-0.4, -0.4), Vec2(0.0, 0.0)), Vertex(Vec2(0.4, -0.4), Vec2(1.0, 0.0)), Vertex(Vec2(0.0, 0.6), Vec2(0.5, 1.0))]
    primitive = Primitive(TriangleStrip(1:3), vertices, FACE_ORIENTATION_COUNTERCLOCKWISE)

    directional_blur = GaussianBlurDirectional(color, texture, BLUR_HORIZONTAL, 0.02)
    render(device, directional_blur, primitive)
    data = collect(color, device)
    save_test_render("blurred_triangle_horizontal.png", data, 0x41c9e4d0f035ba4d)

    directional_blur = GaussianBlurDirectional(color, texture, BLUR_VERTICAL, 0.02)
    render(device, directional_blur, primitive)
    data = collect(color, device)
    save_test_render("blurred_triangle_vertical.png", data, 0xdbbcc39255604205)

    # Need to specify dimensions of the whole texture for the first pass.
    blur = GaussianBlur(color, texture, 0.02)
    render(device, blur, primitive)
    data = collect(color, device)
    save_test_render("blurred_triangle.png", data)
  end

  @testset "Text rendering" begin
    font = OpenTypeFont(font_file("juliamono-regular.ttf"));
    options = FontOptions(ShapingOptions(tag"latn", tag"fra "), 1/10)
    text = OpenType.Text("The brown fox jumps over the lazy dog.", TextOptions())
    line = only(lines(text, [font => options]))
    segment = only(line.segments)
    (; quads, curves) = glyph_quads(line, segment)
    @test length(quads) == count(!isspace, text.chars)
    @test length(unique(rect.data.range for rect in quads)) == length(line.outlines)

    render(device, Text(color, text), font, options, (-1, 0))
    data = collect(color, device)
    save_test_render("text.png", data)

    font = OpenTypeFont(font_file("NotoSerifLao.ttf"));
    options = FontOptions(ShapingOptions(tag"lao ", tag"dflt"; enabled_features = Set([tag"aalt"])), 1/10)
    text = OpenType.Text("ກີບ ສົ \ue99\ueb5\uec9", TextOptions())
    render(device, Text(color, text), font, options, (-1, 0))
    data = collect(color, device)
    save_test_render("text_lao.png", data, 0xa943dc8cae349055)
  end
end;
