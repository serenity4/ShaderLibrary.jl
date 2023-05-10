@testset "Rendering" begin
  @testset "Triangle" begin
    grad = Gradient(color)
    vertices = [Vertex(Vec2(-0.4, -0.4), Vec3(1.0, 0.0, 0.0)), Vertex(Vec2(0.4, -0.4), Vec3(0.0, 1.0, 0.0)), Vertex(Vec2(0.0, 0.6), Vec3(0.0, 0.0, 1.0))]
    primitive = Primitive(TriangleStrip(1:3), vertices, FACE_ORIENTATION_COUNTERCLOCKWISE)
    command = Command(grad, device, primitive)
    render(device, command)
    data = collect(color, device)
    save_test_render("triangle.png", data, 0x110df7c912f605ab)
  end

  @testset "Rectangle" begin
    grad = Gradient(color)
    rect = Rectangle((0.5, 0.5), (-0.2, -0.2), fill(Vec3(1.0, 0.0, 1.0), 4), nothing)
    primitive = Primitive(rect)
    command = Command(grad, device, primitive)
    render(device, command)
    data = collect(color, device)
    save_test_render("rectangle.png", data, 0x3ddf0e2dbe8ebfdb)
  end

  @testset "Sprites" begin
    texture = image_resource(device, read_texture("normal.png"); usage_flags = Vk.IMAGE_USAGE_SAMPLED_BIT)
    sprite = Sprite(color, texture)
    vertices = [Vertex(Vec2(-0.4, -0.4), Vec2(0.0, 0.0)), Vertex(Vec2(0.4, -0.4), Vec2(1.0, 0.0)), Vertex(Vec2(0.0, 0.6), Vec2(0.5, 1.0))]
    primitive = Primitive(TriangleStrip(1:3), vertices, FACE_ORIENTATION_COUNTERCLOCKWISE)
    command = Command(sprite, device, primitive)
    render(device, command)
    data = collect(color, device)
    save_test_render("sprite_triangle.png", data, 0xf16897b4c86bc05b)
  end

  @testset "Glyph rendering" begin
    font = OpenTypeFont(font_file("juliamono-regular.ttf"));
    glyph = font['A']
    curves = map(x -> Arr{3,Vec2}(Vec2.(broadcast.(remap, x, 0.0, 1.0, -0.9, 0.9))), OpenType.curves_normalized(glyph))
    qbf = QuadraticBezierFill(color, curves)
    data = QuadraticBezierPrimitiveData(eachindex(curves) .- 1, 3.6, Vec3(0.6, 0.4, 1.0))
    rect = Rectangle((1.0, 1.0), (0.0, 0.0), nothing, data)
    primitive = Primitive(rect)
    command = Command(qbf, device, primitive)
    render(device, command)
    data = collect(color, device)
    save_test_render("glyph.png", data, 0x090b3ae40da4d980)
  end

  @testset "Blur" begin
    texture = image_resource(device, read_texture("normal.png"); usage_flags = Vk.IMAGE_USAGE_SAMPLED_BIT)
    vertices = [Vertex(Vec2(-0.4, -0.4), Vec2(0.0, 0.0)), Vertex(Vec2(0.4, -0.4), Vec2(1.0, 0.0)), Vertex(Vec2(0.0, 0.6), Vec2(0.5, 1.0))]
    primitive = Primitive(TriangleStrip(1:3), vertices, FACE_ORIENTATION_COUNTERCLOCKWISE)

    directional_blur = GaussianBlurDirectional(color, texture, BLUR_HORIZONTAL, 0.02)
    command = Command(directional_blur, device, primitive)
    render(device, command)
    data = collect(color, device)
    save_test_render("blurred_triangle_horizontal.png", data, 0xe2b7ec249d4bbcdb)

    directional_blur = GaussianBlurDirectional(color, texture, BLUR_VERTICAL, 0.02)
    command = Command(directional_blur, device, primitive)
    render(device, command)
    data = collect(color, device)
    save_test_render("blurred_triangle_vertical.png", data, 0xe66d87a2eea86345)

    blur = GaussianBlur(color, texture, 0.01)
    command = Command(blur, device, primitive)
    render(device, command)
    data = collect(color, device)
    save_test_render("blurred_triangle.png", data, 0x67b92c7515f9f507)
  end
end;
