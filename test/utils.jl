render_file(filename; tmp = false) = joinpath(@__DIR__, "renders", tmp ? "tmp" : "", filename)
texture_file(filename) = joinpath(@__DIR__, "textures", filename)
font_file(filename) = joinpath(@__DIR__, "fonts", filename)
gltf_file(filename) = joinpath(@__DIR__, "assets", filename)
read_mesh(filename) = load_mesh_gltf(gltf_file(filename))
read_texture(filename) = convert(Matrix{RGBA{Float16}}, load(texture_file("normal.png")))

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

function read_normal_map(device)
  normal = convert(Matrix{RGBA{Float16}}, load(texture_file("normal.png")))
  image_resource(device, normal; usage_flags = Vk.IMAGE_USAGE_SAMPLED_BIT)
end

function read_boid_image(device)
  boid = convert(Matrix{RGBA{Float16}}, load(texture_file("boid.png"))')
  image_resource(device, boid; usage_flags = Vk.IMAGE_USAGE_SAMPLED_BIT)
end
