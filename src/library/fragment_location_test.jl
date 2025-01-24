struct FragmentLocationTest{F} <: GraphicsShaderComponent
  f::F
end

function fragment_location_test_shader_vert(position, frag_location, index, (; data)::PhysicalRef{InvocationData})
  location = data.vertex_locations[index + 1U]
  @swizzle position.xyz = world_to_screen_coordinates(location, data)
  frag_location[] = @swizzle location.xy
end

function fragment_location_test_shader_frag(::Type{F}, frag_location, (; data)::PhysicalRef{InvocationData}) where {F}
  f = Base.issingletontype(F) ? F.instance::F : @load data.user_data::F
  inside = @inline f(frag_location)
  !inside && @discard
  nothing
end

function Program(::Type{FragmentLocationTest{F}}, device) where {F}
  vert = @vertex device fragment_location_test_shader_vert(::Mutable{Vec4}::Output{Position}, ::Mutable{Vec2}::Output, ::UInt32::Input{VertexIndex}, ::PhysicalRef{InvocationData}::PushConstant)
  frag = @fragment device fragment_location_test_shader_frag(::Type{F}, ::Vec2::Input, ::PhysicalRef{InvocationData}::PushConstant)
  Program(vert, frag)
end

interface(::FragmentLocationTest) = Tuple{Nothing,Nothing,Nothing}

function user_data(shader::FragmentLocationTest{F}, __context__) where {F}
  Base.issingletontype(typeof(shader.f)) && return nothing
  shader.f
end
