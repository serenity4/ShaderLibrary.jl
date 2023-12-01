using ShaderLibrary: scatter_light_sources, compute_lighting

@testset "Physically-based rendering" begin
  gltf = read_gltf("blob.gltf")
  lights = read_lights(gltf)
  camera = read_camera(gltf)
  mesh = VertexMesh(gltf)
  mesh_transform = Transform(gltf.nodes[end])
  i = last(findmax(v -> v.y, mesh.vertex_locations))
  position = apply_transform(mesh.vertex_locations[i], mesh_transform)
  normal = apply_transform(mesh.vertex_normals[i], mesh_transform)
  bsdf = BSDF{Float32}((1.0, 0.0, 0.0), 0, 0.5, 0.02)
  scattered = scatter_light_sources(bsdf, position, normal, lights, camera)
  @test scattered === zero(Point3f)

  scattered = compute_lighting(bsdf, position, normal, lights, camera)
  @test scattered === zero(Point3f)

  # Notes for comparisons with Blender scenes:
  # - GLTF XYZ <=> Blender XZ(-Y)
  # - Blender XYZ <=> GLTF X(-Z)Y
end;
