module ShaderLibrary

using Random: Random, MersenneTwister, AbstractRNG
using StaticArrays
using Accessors: @set, setproperties
using ColorTypes
using SPIRV: SPIRV, validate, U, F, image_type
using SPIRV.MathFunctions
using GeometryExperiments
using Lava
using SPIRV
using SymbolicGA: @ga
using OpenType
using OpenType: curves, curves_normalized, Line

import Lava: RenderTargets, Program, Command, ProgramInvocationData, DrawIndexed, render

include("transforms.jl")
include("primitive.jl")
include("shader.jl")
include("invocation.jl")

include("library/gradient.jl")
include("library/rectangle.jl")
include("library/sprite.jl")
include("library/blur.jl")
include("library/quadratic_bezier_fill.jl")
include("library/text.jl")

export
  TriangleList,
  TriangleStrip,
  Vertex, TriangleMesh,
  FACE_ORIENTATION_CLOCKWISE,
  FACE_ORIENTATION_COUNTERCLOCKWISE,
  Primitive,
  Instance,

  ShaderComponent,
  Gradient, PosColor,
  Rectangle,
  Sprite,
  QuadraticBezierFill, QuadraticBezierPrimitiveData,
  GaussianBlurDirectional, BlurDirection, BLUR_HORIZONTAL, BLUR_VERTICAL,
  GaussianBlur,
  ProgramCache,

  PinholeCamera,
  Rotation,
  Plane,
  Transform,
  project,
  apply_rotation,
  apply_transform,
  remap

end
