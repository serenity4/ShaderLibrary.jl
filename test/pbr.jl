using ShaderLibrary: scatter_light_sources, compute_lighting_from_sources

@testset "Physically-based rendering" begin
  gltf = read_gltf("blob.gltf")
  lights = import_lights(gltf)
  camera = import_camera(gltf)
  mesh = import_mesh(gltf)
  mesh_transform = import_transform(gltf.nodes[end]; apply_rotation = false)
  i = last(findmin(v -> distance2(lights[1].position, apply_transform(v, mesh_transform)), mesh.vertex_locations))
  position = apply_transform(mesh.vertex_locations[i], mesh_transform)
  normal = apply_rotation(mesh.vertex_normals[i], mesh_transform.rotation)
  bsdf = BSDF{Float32}((1.0, 0.0, 0.0), 0, 0.5, 0.02)
  scattered = scatter_light_sources(bsdf, position, normal, lights, camera)
  @test all(scattered .≥ 0)

  pbr = PBR(bsdf, lights)
  scattered = compute_lighting_from_sources(pbr, position, normal, camera)
  @test all(scattered .≥ 0)

  # Notes for comparisons with Blender scenes:
  # - GLTF XYZ <=> Blender XZ(-Y)
  # - Blender XYZ <=> GLTF X(-Z)Y

  equirectangular = EquirectangularMap(read_jpeg(asset("equirectangular.jpeg")))
  environment = CubeMap(equirectangular, device)
  irradiance = compute_irradiance(environment, device)

  shader = Environment(irradiance, device)
  screen = screen_box(color)
  directions = face_directions(CubeMap)[1]
  geometry = Primitive(Rectangle(screen, directions, nothing))
  render(device, shader, parameters, geometry)
  data = collect(color, device)
  save_test_render("irradiance_nx.png", data, 0xe60d0e8e44988431)
end;
