macro assertion()
  @load_preference("DISABLE_ASSERTIONS", "false") == "true" ? :(return) : :nothing
end
