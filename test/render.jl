render_file(filename; tmp = false) = joinpath(@__DIR__, "renders", tmp ? "tmp" : "", filename)

function save_render(filename, data; tmp = false)
  filename = render_file(filename; tmp)
  mkpath(dirname(filename))
  ispath(filename) && rm(filename)
  save(filename, data')
  filename
end

function save_test_render(filename, data, h::Union{Nothing, UInt} = nothing; tmp = false)
  file = save_render(filename, data; tmp)
  @test stat(file).size > 0
  h′ = hash(data)
  isnothing(h) && return (h′, file)
  @test h′ == h
  file
end

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
    rect = Rectangle((0.5, 0.5), (-0.2, -0.2), (1.0, 0.0, 1.0))
    primitive = Primitive(rect)
    command = Command(grad, device, primitive)
    render(device, command)
    data = collect(color, device)
    save_test_render("rectangle.png", data, 0x3ddf0e2dbe8ebfdb)
  end
end;
