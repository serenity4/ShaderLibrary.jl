using ShaderLibrary: scatter_light_sources

@testset "Physically-based rendering" begin
  gltf = read_gltf("blob.gltf")
  lights = read_lights(gltf)
  camera = read_camera(gltf)
  mesh = VertexMesh(gltf)
  mesh_transform = Transform(gltf.nodes[end])
  i = last(findmax(v -> v.y, mesh.vertex_locations))
  location = apply_transform(mesh.vertex_locations[i], mesh_transform)
  normal = apply_transform(mesh.vertex_normals[i], mesh_transform)
  bsdf = BSDF{Float32}((1.0, 0.0, 0.0), 0, 0.5, 0.02)
  scattered = scatter_light_sources(bsdf, location, normal, lights, camera)
  @test isa(scattered, Point3f)

  # Notes for comparisons with Blender scenes:
  # - GLTF XYZ <=> Blender XZ(-Y)
  # - Blender XYZ <=> GLTF X(-Z)Y
end;
