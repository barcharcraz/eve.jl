include("CREST.jl")
include("SDE.jl")
import .CREST
import .SDE
using DataFrames
using SQLite


r = SDE.regionID("The Forge")
#itms = getItemsFromGroup(marketGroupID("Drones"))
itms = SDE.getAllEveItems()
l = get(CREST.latestLog())
o = readtable(l[1])
sort!(o, cols=[:typeID], by=SDE.itemName)
(sells, buys) = groupby(o, :bid)
itms = o[:typeID].data
itms = SDE.getItemsFromGroup(SDE.marketGroupID("Drones"))
q = CREST.getMarketHistory(r, itms)
db = SQLite.DB("testdb.sqlite")
CREST.storeHistoryData(db, q)
item = 28205
df = DataFrame(dbresp)
resp = CREST.getLatestOrders(r, itms)
test = CREST.loadMarketHistory(db, item, now() - Day(5))
# avg = ( buy * bvol + sell * svol )/ Volume
# Volume*avg = buy*bvol+sell*svol
# Volume = bvol + svol
# 2*avg - sell
testr = []
for (n,x) in test
  buy = x[1]
  sell = x[2]
  avg = x[3]
  vol = x[4]
  A = [buy sell; 1 1]
  B = [vol * avg; vol]
  print(A, "\n")
  #print(rank(A), "\n")
  X = A \ B
end
test[1]["LowPrice"].values[1]


CREST.storeMarketData("testdb.sqlite", resp)
