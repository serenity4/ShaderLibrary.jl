render_file(filename; tmp = false) = joinpath(@__DIR__, "renders", tmp ? "tmp" : "", filename)
texture_file(filename) = joinpath(@__DIR__, "textures", filename)
font_file(filename) = joinpath(@__DIR__, "fonts", filename)
asset(filename, filenames...) = joinpath(@__DIR__, "assets", filename, filenames...)
read_transposed(::Type{T}, file) where {T<:AbstractRGBA} = permutedims(convert(Matrix{T}, load(file)), (2, 1))
read_transposed(file) = read_transposed(RGBA{Float16}, file)
read_png(file) = read_transposed(file)
read_jpeg(file) = read_transposed(file)
read_texture(filename) = read_png(texture_file(filename))
save_png(filename, data) = save(filename, PermutedDimsArray(data, (2, 1)))
read_gltf(filename) = GLTF.load(asset(filename))

function color_attachment(device, dimensions)
  color = attachment_resource(device, nothing; name = :color_target, format = RGBA{Float16}, samples = 4, usage_flags = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT, dims = dimensions)
end

function save_render(path, data)
  mkpath(dirname(path))
  ispath(path) && rm(path)
  save_png(path, data)
  path
end

function save_test_render(filename, data, h = nothing; keep = true)
  path = render_file(filename)
  path_tmp = tempname() * ".png"
  if isnothing(h)
    save_render(path, data)
    return (path, hash(data))
  end
  save_render(path_tmp, data)
  @test stat(path_tmp).size > 0
  h′ = hash(data)
  isnothing(h) && return (h′, file)
  (success, op_success, op_failure) = isa(h, UInt) ? (h′ == h, "==", "≠") : (h′ in h, "in", "∉")
  if success
    mkpath(dirname(path))
    ispath(path) && rm(path)
    mv(path_tmp, path)
  else
    msg = "Test failed: h′ $op_failure h ($(repr(h′)) $op_failure $(repr(h)))\nh′ -> $path_tmp"
    if isfile(path)
      existing = read_png(path)
      h′′ = hash(existing)
      if isa(h, UInt) && h′′ == h || h′′ in h
        msg *= "\nh -> $path"
      else
        msg *= "\n(the existing render $path has an unexpected value of h = $(repr(h′′))"
      end
    end
    @warn "$msg"
  end
  isa(h, UInt) ? (@test h′ == h) : (@test h′ in h)
  keep && return (path, h′)
  success && rm(path)
  h′
end

function read_normal_map(device)
  normal = convert(Matrix{RGBA{Float16}}, load(texture_file("normal.png")))
  image_resource(device, normal; usage_flags = Vk.IMAGE_USAGE_SAMPLED_BIT)
end

function read_boid_image(device)
  boid = convert(Matrix{RGBA{Float16}}, load(texture_file("boid.png"))')
  image_resource(device, boid; usage_flags = Vk.IMAGE_USAGE_SAMPLED_BIT)
end
