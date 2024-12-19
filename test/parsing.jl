using ShaderLibrary, Test
using ShaderLibrary: generate_shaders, validate_shader_stages, is_previous_stage, emit_shader, xmldocument
using EzXML: readxml, parsexml

components = readxml(joinpath(dirname(@__DIR__), "src", "components.xml"))
shaders = readxml(joinpath(dirname(@__DIR__), "src", "shaders.xml"))
output = joinpath(@__DIR__, "generated.jl")

@testset "Component library parsing" begin
  @testset "Shader stages" begin
    stages = [:vertex, :fragment]
    @test validate_shader_stages(stages)
    stages = [:fragment, :vertex]
    @test_throws "`fragment` must come after" validate_shader_stages(stages)
    stages = [:fragment]
    @test validate_shader_stages(stages)
    stages = [:vertex, :unknown]
    @test_throws "unsupported shader stage `unknown`" validate_shader_stages(stages)
    stages = [:fragment, :fragment]
    @test_throws "shader stage `fragment` is provided multiple times" validate_shader_stages(stages)

    # Stages must be correctly ordered, so we won't need to cover invalid orders.
    stages = [:vertex, :geometry, :fragment]
    @test is_previous_stage(:geometry, :fragment, stages)
    @test !is_previous_stage(:vertex, :fragment, stages)
    @test !is_previous_stage(:geometry, :geometry, stages)
    stages = [:vertex, :fragment]
    @test !is_previous_stage(:geometry, :fragment, stages)
    @test is_previous_stage(:vertex, :fragment, stages)
  end

  xml = """
  <?xml version="1.0" encoding="UTF-8"?>
  <shader-components>
    <shader-component name="test">
      <fragment/>
      <vertex/>
    </shader-component>
  </shader-components>
  """
  @test_throws "`fragment` must come after" generate_shaders(xml, shaders)

  ret = generate_shaders(components, shaders)
  @test length(ret.components) ≥ 9
  @test length(ret.shaders) ≥ 3
  @test isa(emit_shader(stdout, ret.shaders[1]), String)
end;
