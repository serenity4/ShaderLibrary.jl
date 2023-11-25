module ShaderLibrary

using Random: Random, MersenneTwister, AbstractRNG
using StaticArrays
using Accessors: @set, setproperties
using ColorTypes
using SPIRV: SPIRV, validate, U, F, image_type
using SPIRV.MathFunctions
using Reexport
@reexport using GeometryExperiments
using Lava
using SPIRV
using SPIRV: unsigned_index
using OpenType
using OpenType: curves, curves_normalized, Line
using Erosion
using Erosion: ErosionMaps
using StructEquality: @struct_hash_equal, @struct_hash_equal_isapprox
using LinearAlgebra: ⋅, ×
using GLTF

const Optional{T} = Union{T, Nothing}

import Lava: RenderTargets, Program, Command, ProgramInvocationData, DrawIndexed, render

include("camera.jl")
include("primitive.jl")
include("shader.jl")
include("invocation.jl")
include("lights.jl")

include("library/gradient.jl")
include("library/rectangle.jl")
include("library/sprite.jl")
include("library/blur.jl")
include("library/quadratic_bezier_fill.jl")
include("library/text.jl")
include("library/pbr.jl")
# include("library/erosion.jl")

include("gltf.jl")

export
  MeshTopology,
  MESH_TOPOLOGY_TRIANGLE_LIST,
  MESH_TOPOLOGY_TRIANGLE_STRIP,
  MESH_TOPOLOGY_TRIANGLE_FAN,
  MeshEncoding,

  Vertex, VertexMesh,
  FACE_ORIENTATION_CLOCKWISE,
  FACE_ORIENTATION_COUNTERCLOCKWISE,
  Primitive,
  Instance,

  ShaderComponent, GraphicsShaderComponent, ComputeShaderComponent,
  ShaderParameters, ClearValue,
  ProgramCache,
  renderables, render, compute,
  PhysicalBuffer, PhysicalRef,

  # Materials
  Gradient,
  Sprite,
  QuadraticBezierFill, QuadraticBezierPrimitiveData,
  PBR, BSDF, PointLight,

  # Geometries
  Rectangle,

  # Lights
  Light, LightType, LIGHT_TYPE_POINT, LIGHT_TYPE_SPOT, LIGHT_TYPE_DIRECTION,

  # Graphics shader components
  GaussianBlurDirectional, BlurDirection, BLUR_HORIZONTAL, BLUR_VERTICAL, GaussianBlur,
  LargeScaleErosion,

  Camera, project,
  remap

end
