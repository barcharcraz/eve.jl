using Gtk.ShortNames

import eve
using DataFrames

immutable WinPoint
  x :: Clong
  y :: Clong
end
immutable WinMsg
  hwnd :: Ptr{Void}
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
function MarginToolView(itemName, maxbuy, minsell)
  grid = @Grid()
  setproperty!(grid, "orientation", 1)
  push!(grid, @Label(itemName))
  push!(grid, @Label("Max Buy: $maxbuy"))
  push!(grid, @Label("Min Sell: $minsell"))
  margin = (minsell - maxbuy)/minsell
  push!(grid, @Label("Margin: $(100margin)%"))
  grid
end
function HotkeyFilter(xevt :: Ptr{WinMsg}, gevt :: Ptr{Void}, data :: Ptr{Void})
  evt = unsafe_load(xevt)
  if evt.msg == 0x0312
    print("Hotkey Pressed")
    return Cint(2)
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

  margin = MarginToolView("Raven", 100000000, 200000000)

  tabs = @Notebook()
  push!(tabs, f, "Orders")
  push!(tabs, margin, "Margin Tool")

  push!(win, tabs)
  gdkWin = Gtk.gdk_window(win)
  ccall( (:gdk_window_add_filter, Gtk.libgdk), Void, (Ptr{Void}, Ptr{Void}, Ptr{Void}),
    gdkWin,
    cfunction(HotkeyFilter, Cint, (Ptr{WinMsg}, Ptr{Void}, Ptr{Void})),
    0)
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
