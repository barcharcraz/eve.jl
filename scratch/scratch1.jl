using Escher
using DataFrames
import eve
function makeFrameCol(col :: DataArray)
  vbox(map(x -> pad(0.5em, string(x)), col)) |> borderwidth(1px) |> borderstyle([left, right, top, bottom], solid)
end
function makeFrameRow(row :: DataFrameRow)
  hbox(map(x -> pad(0.5em, string(x[2])), row))
end
function makeFrameTable(df :: DataFrame)
  #cols = map(x -> pad([left, right], 1em, makeFrameCol(x)), eachcol(df))
  #for k in eachindex(cols)
  #  if iseven(k)
  #    cols[k] = fillcolor("#892", v[k])
  #  else
  #    cols[k] = fillcolor("#859", v[k])
  #  end
  #end
  vbox(map(makeFrameRow, eachrow(df))) |> packlines(center)
  #hbox(cols) |> packitems(spacebetween)
end
key_input = Signal(Key, nokey)

selection = Signal(leftbutton)
function main(window)
  t = eve.importOrders()
  name = names(t)
  name = map(string, name)
  #name = map(plaintext, name)
  #t = vbox("a", "b", "c", "d")
  #v = vbox("f", string(1.0))
  #makeFrameTable(t)
  #tbl.body = map(pad(3em), eachrow(tbl.body))
  #tbl

  tbl = table(t) |> borderwidth(1px) |> borderstyle(solid)
  cont = container(40em, 40em) |> fillcolor("#f1f3f1")


  sub = clickable(cont) >>> selection
  vbox(tbl, cont, selection, sub)
end
