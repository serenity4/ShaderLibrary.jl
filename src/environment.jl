struct CubeMap{T}
  xp::Matrix{T}
  xn::Matrix{T}
  yp::Matrix{T}
  yn::Matrix{T}
  zp::Matrix{T}
  zn::Matrix{T}
end

check_number_of_images(images) = length(images) == 6 || throw(ArgumentError("Expected 6 face images for CubeMap, got $(length(images)) instead"))

function CubeMap(images::AbstractVector{Matrix{T}}) where {T}
  check_number_of_images(images)
  allequal(size(image) for image in images) || throw(ArgumentError("Expected all face images to have the same size, obtained multiple sizes $(unique(size.(images)))"))
  CubeMap(images...)
end

function CubeMap(images::AbstractVector{T}) where {T<:Matrix}
  check_number_of_images(images)
  xp, xn, yp, yn, zp, zn = promote(ntuple(i -> images[i], 6)...)
  CubeMap(@SVector [xp, xn, yp, yn, zp, zn])
end

function Lava.Image(device::Device, cubemap::CubeMap)
  (; xp, xn, yp, yn, zp, zn) = cubemap
  data = [xp, xn, yp, yn, zp, zn]
  Image(device; data, array_layers = 6)
end

struct Environment
  image::Image
end

Environment(device::Device, cubemap::CubeMap) = Environment(Image(device, cubemap))
