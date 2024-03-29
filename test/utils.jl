render_file(filename; tmp = false) = joinpath(@__DIR__, "renders", tmp ? "tmp" : "", filename)
texture_file(filename) = joinpath(@__DIR__, "textures", filename)
font_file(filename) = joinpath(@__DIR__, "fonts", filename)
asset(filename, filenames...) = joinpath(@__DIR__, "assets", filename, filenames...)
read_png(file) = permutedims(convert(Matrix{RGBA{Float16}}, load(file)), (2, 1))
read_texture(filename) = read_png(texture_file(filename))
read_gltf(filename) = GLTF.load(asset(filename))

function color_attachment(device, dimensions)
  color = attachment_resource(device, nothing; name = :color_target, format = RGBA{Float16}, samples = 4, usage_flags = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT, dims = dimensions)
end

function save_render(filename, data; tmp = false)
  filename = render_file(filename; tmp)
  mkpath(dirname(filename))
  ispath(filename) && rm(filename)
  # PNG saving expects data in row-major format.
  save(filename, PermutedDimsArray(data, (2, 1)))
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
