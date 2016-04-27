import eve
using DataFrames
o = get(eve.latestMarketLog())
t = eve.importMarketLog()
s = eve.summerizeItem(t)



df = eve.importMarketLog()
