module s
using Gtk.ShortNames

import eve
using DataFrames

immutable WinPoint
  x :: Clong
  y :: Clong
end
immutable WinMsg
  hwnd :: Ptr{GObject}
  msg :: Cuint
  wparam :: Ptr{Cuint}
  lparam :: Ptr{Void}
  time :: Culong
  pt :: WinPoint
end

function DataFrameView(df)
  store = @ListStore(eltypes(df)...)
  for r in eachrow(df)
    push!(store, (Array(r)...))
  end
  view = @TreeView(TreeModel(store))
  renderer = @CellRendererText()
  for i in eachindex(names(df))
    push!(view, @TreeViewColumn(string(names(df)[i]), renderer, Dict("text"=>i-1)))
  end
  view
end

function MarginToolView(data :: eve.ItemSummery)
  grid = @Grid()
  setproperty!(grid, "orientation", 1)
  push!(grid, @Label(string(data.itemID)))
  push!(grid, @Label("Max Buy: $(data.maxbuy)"))
  push!(grid, @Label("Min Sell: $(data.minsell)"))
  push!(grid, @Label("Margin: $(100data.margin)%"))
  grid
end
function HotkeyFilter(xevt :: Ptr{WinMsg}, gevt :: Ptr{Gtk.GdkEventKey}, data :: Ptr{Void})
  evt = unsafe_load(xevt)
  if evt.msg == 0x0312
    return Cint(2)
    GAccessor.
  else
    return Cint(0)
  end
end
function UITest()
  t = eve.importOrders()
  win = @Window("test", 1920, 1080)
  (sells, buys) = groupby(t, :bid)
  listViewSells = DataFrameView(sells)
  listViewBuys = DataFrameView(buys)

  f = @Frame("Orders")
  panes = @Paned(true)
  panes[1] = listViewSells
  panes[2] = listViewBuys
  push!(f, panes)
  margin = @Grid()
  dv = MarginDataView()
  push!(margin, dv)
  importOrdersBtn = @Button("Import Orders")
  push!(margin, importOrdersBtn)
  signal_connect(importOrdersBtn, "clicked") do widget
    UpdateMarginToolView(dv, eve.summerizeItem(eve.importMarketLog()))
  end
  tabs = @Notebook()
  push!(tabs, f, "Orders")
  push!(tabs, margin, "Margin Tool")

  push!(win, tabs)
  gdkWin = Gtk.gdk_window(win)
  ccall( (:gdk_window_add_filter, Gtk.libgdk), Void, (Ptr{Void}, Ptr{TreeView}, Ptr{Void}),
    gdkWin,
    cfunction(HotkeyFilter, Cint, (Ptr{WinMsg}, Ptr{Void}, Ptr{Void})),
    pointer_from_objref(listViewSells))
  hwnd = ccall( (:gdk_win32_window_get_impl_hwnd, Gtk.libgdk),  Ptr{Void}, (Ptr{Void},), gdkWin)
  result = ccall( (:RegisterHotKey, "User32"), stdcall, Cint, (Ptr{Void}, Cint, Cuint, Cuint),
    hwnd, 1, 0, 0x28)
  #sel = getproperty(listViewSells, :selection, TreeSelection)
  sel = Gtk.GAccessor.selection(listViewSells)
  signal_connect(sel, "changed") do selection
    print(selected(selection))
  end
  showall(win)
end
end
