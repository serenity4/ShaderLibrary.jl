using EzXML: EzXML, parsexml, readxml, Document

function strip_linenums!(ex)
  !Meta.isexpr(ex, :macrocall) && return Base.remove_linenums!(ex)
  ex.args[2] = nothing
  for arg in @view ex.args[3:end]
    strip_linenums!(arg)
  end
  ex
end

struct InvalidXML <: Exception
  msg::String
end
Base.showerror(io::IO, exc::InvalidXML) = print(io, "InvalidXML: ", exc.msg)
error_invalid_xml(msg...) = throw(InvalidXML(string(msg...)))

function getattr(node, attr; default = nothing, symbol = false, parse = false)
  haskey(node, attr) || return default
  value = node[attr]
  parse === true && return Meta.parse(value)
  parse !== false && return Meta.parse(parse, value)
  symbol && return Symbol(value)
  value
end

function parse_type(node)
  type = getattr(node, "type"; parse = true)
  isnothing(type) && return nothing
  validate_type(type)
  type
end

@inline function validate_type(type)
  isa(type, Symbol) || isa(type, Expr) || error_invalid_xml("type `$type` is not a valid Julia type; a symbol or expression input is expected")
end

function parse_types(xml::Document)
  enums = Expr[]
  for decl in findall("/shader-components/types/enum", xml)
    ename = getattr(decl, "name"; symbol = true)
    isnothing(ename) && error_invalid_xml("missing name for enum: $decl")
    type = parse_type(decl)
    isnothing(type) && error_invalid_xml("missing type for enum: $decl")
    members = Expr[]
    for member in findall("./member", decl)
      name = getattr(member, "name"; symbol = true)
      isnothing(name) && error_invalid_xml("missing name for enum member: $member")
      value = getattr(member, "value"; parse = true)
      isnothing(value) && error_invalid_xml("missing value for enum member: $member")
      push!(members, :($name = $value))
    end
    isempty(members) && error_invalid_xml("no members defined for enum: $decl")
    push!(enums, strip_linenums!(:(@enum $ename::$type begin $(members...) end)))
  end

  structs = Expr[]
  for decl in findall("/shader-components/types/struct", xml)
    sname = getattr(decl, "name"; symbol = true)
    isnothing(sname) && error_invalid_xml("missing name for struct: $decl")
    members = Expr[]
    for member in findall("./member", decl)
      name = getattr(member, "name"; symbol = true)
      isnothing(name) && error_invalid_xml("missing name for struct member: $member")
      type = parse_type(member)
      isnothing(type) && error_invalid_xml("missing type for struct member: $member")
      push!(members, :($name::$type))
    end
    isempty(members) && error_invalid_xml("no members defined for struct: $decl")
    push!(structs, strip_linenums!(:(struct $sname; $(members...) end)))
  end

  enums, structs
end

struct XMLShaderStageOutput
  name::Symbol
  type::Union{Symbol, Expr}
  export_name::Optional{Symbol}
  vertex_output::Bool # indicates whether this output is per-vertex, i.e. whether this should be then interpolated as an Output variable.
  interpolation::Optional{Symbol} # :linear, :flat or default
  builtin::Optional{SPIRV.BuiltIn}
end
XMLShaderStageOutput(name, type, builtin::SPIRV.BuiltIn) = XMLShaderStageOutput(name, type, nothing, false, nothing, builtin)

struct XMLShaderStageInput
  name::Symbol
  type::Union{Symbol, Expr}
  from::Optional{XMLShaderStageOutput} # nothing means unresolved yet
  builtin::Optional{SPIRV.BuiltIn}
end
XMLShaderStageInput(name, type, builtin::SPIRV.BuiltIn) = XMLShaderStageInput(name, type, nothing, builtin)

@enum DataCategory::UInt8 begin
  DATA_CATEGORY_PARAMETER = 0
  DATA_CATEGORY_INVOCATION_DATA = 1
  DATA_CATEGORY_CAMERA = 2
  DATA_CATEGORY_VERTEX_LOCATION = 11
  DATA_CATEGORY_VERTEX_NORMAL = 12
  DATA_CATEGORY_VERTEX_DATA = 13
  DATA_CATEGORY_PRIMITIVE_DATA = 21
end

ispervertex(category::DataCategory) = 10 < UInt8(category) < 20
isperprimitive(category::DataCategory) = 20 < UInt8(category) < 30
iscustomdata(category::DataCategory) = category in (DATA_CATEGORY_PARAMETER, DATA_CATEGORY_VERTEX_DATA, DATA_CATEGORY_PRIMITIVE_DATA)

function DataCategory(category::Optional{Symbol})
  category === nothing && return DATA_CATEGORY_PARAMETER
  category === Symbol("invocation-data") && return DATA_CATEGORY_INVOCATION_DATA
  category === Symbol("camera") && return DATA_CATEGORY_CAMERA
  category === Symbol("vertex-location") && return DATA_CATEGORY_VERTEX_LOCATION
  category === Symbol("vertex-normal") && return DATA_CATEGORY_VERTEX_NORMAL
  category === Symbol("vertex-data") && return DATA_CATEGORY_VERTEX_DATA
  category === Symbol("primitive-data") && return DATA_CATEGORY_PRIMITIVE_DATA
  error_invalid_xml("unknown data category: $category")
end

function data_type(category::DataCategory)
  category === DATA_CATEGORY_INVOCATION_DATA && return :InvocationData
  category === DATA_CATEGORY_CAMERA && return :Camera
  category === DATA_CATEGORY_VERTEX_LOCATION && return :Vec3
  category === DATA_CATEGORY_VERTEX_NORMAL && return :Vec3
  error("No data type is known for `$category`")
end

struct XMLShaderStageData
  name::Symbol
  category::DataCategory
  type::Union{Symbol, Expr}
  default::Optional{QuoteNode}
end

mutable struct XMLShaderStage
  name::Symbol
  inputs::Vector{XMLShaderStageInput}
  outputs::Vector{XMLShaderStageOutput}
  data::Vector{XMLShaderStageData}
  invocation_data::Vector{Symbol}
  camera::Vector{Symbol}
  vertex_normal::Vector{Symbol}
  vertex_location::Vector{Symbol}
  vertex_data::Vector{Symbol}
  primitive_data::Vector{Symbol}
  builtins::Vector{Symbol}
  exports::Vector{Symbol}
  code::Expr
  XMLShaderStage(name) = new(name, [], [], [], [], [], [], [], [], [], [], [])
end


struct XMLShaderComponent
  name::Symbol
  stages::Vector{XMLShaderStage}
end

const SHADER_STAGE_ORDERS = [
  [:vertex, :tesselation, :geometry, :fragment],
  # others?
]

"Returns whether `x` is the shader stage prior to `stage` among `stages`."
function is_previous_stage(x::Symbol, stage::Symbol, stages)
  i = findfirst(order -> in(stage, order), SHADER_STAGE_ORDERS)
  isnothing(i) && return false
  order = SHADER_STAGE_ORDERS[i]
  !in(x, order) && return false
  j = findfirst(==(stage), order)::Int
  j == firstindex(order) && return false
  for k in reverse(1:(j - 1))
    prev = order[k]
    !in(prev, stages) && continue
    prev === x && return true
    in(prev, stages) && return false
  end
  false
end

"""
For each component stage, check that all present stages are correctly ordered.

For example, if a `vertex` and a `fragment` stage are both present, `vertex` should be provided first.
This is to facilitate input resolution during parsing.

More formally, if a set of shader stages (Sᵢ)ᵢ are interdependent, and a subset (S′ᵢ)ᵢ ⊂ (Sᵢ)ᵢ of shader stages is provided, ensure that all stages in this subset possess the same order they are meant to be consumed by a graphics API.

If `vertex` is provided but `fragment` is not, or vice-versa, this remains valid.
"""
function validate_shader_stages(stages, stnodes = nothing)
  provided_stages = Set{Symbol}()
  xmlinfo(stage) = isnothing(stnodes) ? "" : ": $(stnodes[findfirst(==(stage), stages)])"
  error_invalid_order(stage, required) = error_invalid_xml("shader stage `$stage` must come after a `$required` shader stage", xmlinfo(stage))
  for stage in stages
    in(stage, provided_stages) && error_invalid_xml("shader stage `$stage` is provided multiple times; a given shader stage may be provided only once", xmlinfo(stage))
    in(stage, (:vertex, :fragment, :compute)) || error_invalid_xml("unsupported shader stage `$stage`", xmlinfo(stage))
    i = findfirst(order -> in(stage, order), SHADER_STAGE_ORDERS)
    isnothing(i) && continue
    order = SHADER_STAGE_ORDERS[i]
    j = findfirst(==(stage), order)
    for later_stage in @view order[(j + 1):end]
      in(later_stage, provided_stages) && error_invalid_order(later_stage, stage)
    end
    push!(provided_stages, stage)
  end
  true
end

function resolve_builtin_input(builtin)
  builtin === :FragDepth && return XMLShaderStageInput(:FragDepth, :Float32, SPIRV.BuiltInFragDepth)
  builtin === :VertexIndex && return XMLShaderStageInput(:VertexIndex, :UInt32, SPIRV.BuiltInVertexIndex)
  builtin === :PrimitiveId && return XMLShaderStageInput(:PrimitiveId, :UInt32, SPIRV.BuiltInPrimitiveId)
  error_invalid_xml("builtin \"$builtin\" is not a valid SPIR-V builtin input or isn't yet recognized.")
end

function resolve_builtin_output(builtin)
  builtin === :FragCoord && return XMLShaderStageOutput(:FragCoord, :Vec4, SPIRV.BuiltInFragCoord)
  builtin === :Position && return XMLShaderStageOutput(:Position, :Vec4, SPIRV.BuiltInPosition)
  error_invalid_xml("builtin \"$builtin\" is not a valid SPIR-V builtin output or isn't yet recognized.")
end

function resolve_input(name::Symbol, current_stage::XMLShaderStage, stages, stage_types = unique!(Symbol[stage.name for stage in stages]))
  for stage in Iterators.reverse(stages)
    is_previous_stage(stage.name, current_stage.name, stage_types) || continue
    for output in stage.outputs
      output.name === name && return output
    end
    return nothing
  end
end

function add_data!(stage::XMLShaderStage, data::XMLShaderStageData)
  data.category === DATA_CATEGORY_INVOCATION_DATA && push!(stage.invocation_data, data.name)
  data.category === DATA_CATEGORY_CAMERA && push!(stage.camera, data.name)
  data.category === DATA_CATEGORY_VERTEX_LOCATION && push!(stage.vertex_location, data.name)
  data.category === DATA_CATEGORY_VERTEX_NORMAL && push!(stage.vertex_normal, data.name)
  data.category === DATA_CATEGORY_VERTEX_DATA && push!(stage.vertex_data, data.name)
  push!(stage.data, data)
end

function parse_shader_components(xml::Document)
  components = XMLShaderComponent[]
  for cnode in findall("/shader-components/shader-component", xml)
    cname = getattr(cnode, "name"; symbol = true)
    isnothing(cname) && error_invalid_xml("missing name for shader component: $cnode")
    component = XMLShaderComponent(cname, XMLShaderStage[])
    push!(components, component)
    stnodes = findall("./*", cnode)
    stage_types = [Symbol(component_stage.name) for component_stage in stnodes]
    validate_shader_stages(stage_types, stnodes)
    for (stnode, stage_type) in zip(stnodes, stage_types)
      stage = XMLShaderStage(stage_type)
      push!(component.stages, stage)
      decls = findall("./data|input|output", stnode)
      for decl in decls
        dtype = Symbol(decl.name)
        dname = getattr(decl, "name"; symbol = true)
        if dtype === :data
          isnothing(dname) && error_invalid_xml("missing name for $dtype: $decl")
          category = DataCategory(getattr(decl, "category"; symbol = true))
          ispervertex(category) && (stage_type === :vertex || error_invalid_xml("per-vertex data is only allowed in vertex shader stages: $decl"))
          isperprimitive(category) && (stage_type in (:vertex, :fragment) || error_invalid_xml("per-primitive data is only allowed in vertex or fragment shader stages: $decl"))
          type = parse_type(decl)
          if !iscustomdata(category)
            expected = data_type(category)
            !isnothing(type) && (type == expected || error_invalid_xml("type `$type` was specified but does not match with the corresponding known data type `$expected`: $decl"))
            type = something(type, expected)
          else
            isnothing(type) && error_invalid_xml("a type must be specified for custom data: $decl")
          end
          default = getattr(decl, "default"; parse = true)
          isnothing(default) || (category !== DATA_CATEGORY_PARAMETER && error_invalid_xml("default values are only valid for parameters - that is, for `data` entries with no `category`"))
          data = XMLShaderStageData(dname, category, type, QuoteNode(default))
          add_data!(stage, data)
        elseif dtype === :input
          builtin = getattr(decl, "builtin"; symbol = true)
          if !isnothing(builtin)
            input = resolve_builtin_input(builtin)
            push!(stage.inputs, input)
            push!(stage.builtins, input.name)
            continue
          end
          isnothing(dname) && error_invalid_xml("missing name for $dtype: $decl")
          resolved = resolve_input(dname, stage, @view(component.stages[1:(end - 1)]), stage_types)
          if isnothing(resolved)
            type = parse_type(decl)
            isnothing(type) && error_invalid_xml("input `$dname` requires a type because it could not be resolved from a previous output: $decl")
            push!(stage.inputs, XMLShaderStageInput(dname, type, nothing, nothing))
          else
            type = parse_type(decl)
            if !isnothing(type)
              type == resolved.type || error_invalid_xml("input `$dname` with type `$type` was resolved to `$(resolved.name)` with a different type `$type`; the types of matching output/input pairs must be the same: $decl")
            end
            push!(stage.inputs, XMLShaderStageInput(dname, resolved.type, resolved, nothing))
          end
        elseif dtype === :output
          builtin = getattr(decl, "builtin"; symbol = true)
          if !isnothing(builtin)
            output = resolve_builtin_output(builtin)
            push!(stage.outputs, output)
            push!(stage.builtins, output.name)
            continue
          end
          category = getattr(decl, "category"; symbol = true)
          type = parse_type(decl)
          if !isnothing(category)
            stage_type === :vertex || error_invalid_xml("an output category may only be specified for the vertex stage: $decl")
            data_category = DataCategory(category)
            ispervertex(data_category) || error_invalid_xml("per-vertex categories only are allowed for output annotations: $decl")
            if data_category === DATA_CATEGORY_VERTEX_DATA
              isnothing(type) && error_invalid_xml("a type must be provided if the \"vertex-data\" category is used for outputs: $decl")
            else
              expected = data_type(data_category)
              !isnothing(type) && (type == expected || error_invalid_xml("type `$type` was specified but does not match with the corresponding known data type `$expected`: $decl"))
              type = something(type, expected)
            end
            data = XMLShaderStageData(dname, data_category, type, nothing)
            add_data!(stage, data)
          end
          isnothing(dname) && error_invalid_xml("missing name for $dtype: $decl")
          isnothing(type) && error_invalid_xml("output `$dname` must have a type: $decl")
          export_name = getattr(decl, "export"; symbol = true)
          !isnothing(export_name) && push!(stage.exports, export_name)
          vertex_output = stage_type === :vertex
          interpolation = getattr(decl, "interpolation"; symbol = true)
          if !isnothing(interpolation)
            vertex_output || error_invalid_xml("interpolation can only be specified for vertex outputs: $decl")
            interpolation in (:linear, :flat) || error_invalid_xml("Only \"linear\" or \"flat\" interpolation attributes are supported: $decl")
          end
          push!(stage.outputs, XMLShaderStageOutput(dname, type, export_name, vertex_output, interpolation, nothing))
        elseif dtype === :code
          decl === last(decls) || error_invalid_xml("the <code> attribute must come last: $decl")
          code = strip_linenums!(Meta.parse("begin $(decl.content) end"))
          Meta.isexpr(code, :block, 1) && (code = code.args[1])
          stage.code = code
        end
      end
    end
  end
  components
end

struct XMLShader
  name::Symbol
  arguments::Vector{XMLShaderStageData}
  components::Vector{XMLShaderComponent}
end

function parse_shaders(xml::Document, components)
  shaders = XMLShader[]
  components = Dict(component.name => component for component in components)
  for snode in findall("/shaders/shader", xml)
    sname = getattr(snode, "name"; symbol = true)
    isnothing(sname) && error_invalid_xml("missing name for shader: $snode")
    shader = XMLShader(sname, XMLShaderStageData[], XMLShaderComponent[])
    push!(shaders, shader)
    for cnode in findall("./component", snode)
      cname = getattr(cnode, "name"; symbol = true)
      isnothing(cname) && error_invalid_xml("missing name for shader component: $cnode")
      component = get(components, cname, nothing)
      isnothing(component) && error("shader \"$sname\" references unknown shader component \"$cname\": $cnode")
      push!(shader.components, component)
    end
    define_arguments!(shader)
    resolve_inputs!(shader)
  end
  shaders
end

function define_arguments!(shader::XMLShader)
  for component in shader.components
    for stage in component.stages
      for data in stage.data
        iscustomdata(data.category) && !in(data, shader.arguments) && push!(shader.arguments, data)
      end
    end
  end
  shader
end

function resolve_inputs!(shader::XMLShader)
  stages = XMLShaderStage[]
  unresolved = Pair{XMLShaderStage,Int}[]
  for component in shader.components
    for stage in component.stages
      for (i, input) in enumerate(stage.inputs)
        isnothing(input.builtin) || continue
        isnothing(input.from) || continue
        push!(unresolved, stage => i)
      end
      push!(stages, stage)
    end
  end
  stage_types = unique!(Symbol[stage.name for stage in stages])
  for (stage, i) in unresolved
    input = stage.inputs[i]
    resolved = resolve_input(input.name, stage, stages, stage_types)
    isnothing(resolved) && error("input `$(input.name)` in shader stage `$(stage.name))` of shader \"$sname\" is unresolved; an `output` from a previous stage must match")
    stage.inputs[i] = @set input.from = resolved
  end
  shader
end

function emit_types(io::IO, enums, types)
  for decl in enums
    println(io, decl)
    println(io)
  end
  for decl in structs
    println(io, decl)
    println(io)
  end
end

function emit_components(io::IO, components)
end

function emit_shader(io::IO, shaders)
end

xmldocument(input::AbstractString) = parsexml(input)
xmldocument(input::IO) = readxml(input)
xmldocument(xml::Document) = xml

generate_shaders(components, shaders) = generate_shaders(xmldocument(components), xmldocument(shaders))

function generate_shaders(components::Document, shaders::Document)
  enums, structs = parse_types(components)
  components = parse_shader_components(components)
  shaders = parse_shaders(shaders, components)
  (; enums, structs, components, shaders)
end

function generate_shaders(output, components, shaders)
  (; enums, structs, components, shaders) = generate_shaders(components, shaders)
  open(output, "w+") do io
    emit_types(io, enums, structs)
    emit_components(io, components)
    emit_shaders(io, shaders)
  end
end
