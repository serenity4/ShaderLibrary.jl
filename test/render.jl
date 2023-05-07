@testset "Rendering" begin
  @testset "Rectangle" begin
    grad = Gradient(color)
    rect = Rectangle((0.5, 0.5), (-0.2, -0.2), (1.0, 0.0, 1.0))
    primitive = Primitive(rect)
    command = Command(grad, device, primitive)
  end
end;
