module ShaderLibrary

using Random: Random, MersenneTwister, AbstractRNG
using StyledStrings: @styled_str
using Preferences
using StaticArrays
using Accessors: Accessors, @set, @reset, setproperties
using ColorTypes
using SPIRV: SPIRV, validate, U, F, image_type
using SPIRV.MathFunctions
using Reexport
@reexport using GeometryExperiments
using Lava
using SPIRV
using Lava: Image
using OpenType
using OpenType: curves, curves_normalized, Line
using Erosion
using Erosion: ErosionMaps
using StructEquality: @struct_hash_equal, @struct_hash_equal_isapprox
using LinearAlgebra: ⋅, ×
using GLTF

const Optional{T} = Union{T, Nothing}

import Lava: RenderTargets, Program, Command, ProgramInvocationData, DrawIndexed, render

include("preferences.jl")
include("camera.jl")
include("primitive.jl")
include("shader.jl")
include("invocation.jl")
include("lights.jl")

include("library/gradient.jl")
include("library/rectangle.jl")
include("library/sprite.jl")
include("library/blur.jl")
include("library/blur_comp.jl")
include("library/quadratic_bezier_fill.jl")
include("library/text.jl")
include("library/pbr.jl")
include("library/erosion.jl")
include("library/gamma_correction.jl")
include("library/environment.jl")
include("library/ibl_irradiance.jl")
include("library/ibl_prefilter.jl")
include("library/ibl_brdf_integration.jl")

include("cubemap.jl")
include("ibl.jl")

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
  PBR, BSDF,

  # Geometries
  Rectangle,
  screen_semidiagonal,
  screen_box,

  # Lights
  Light, LightType, LIGHT_TYPE_POINT, LIGHT_TYPE_SPOT, LIGHT_TYPE_DIRECTION,
  LightProbe,

  # Environment
  create_cubemap, create_cubemap_from_equirectangular,
  collect_cubemap_faces, CubeMapFaces, CUBEMAP_FACE_DIRECTIONS,
  Environment, environment_from_cubemap, environment_from_equirectangular,

  # Graphics shader components
  GaussianBlurDirectional, BLUR_HORIZONTAL, BLUR_VERTICAL, GaussianBlur,
  Text,
  IrradianceConvolution, compute_irradiance,
  PrefilteredEnvironmentConvolution, compute_prefiltered_environment,

  # Compute shader components
  GammaCorrection,
  LargeScaleErosion,

  Camera, focal_length,
  field_of_view, horizontal_field_of_view, vertical_field_of_view,
  project,
  remap,

  # Imports
  import_mesh,
  import_camera,
  import_lights,
  import_transform

end
