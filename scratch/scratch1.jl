using Escher
function main(window)
  t = vbox("a", "b", "c", "d")
  v = vbox("f", string(1.0))
  hbox(t,v)
end
