
import eve

itemID("Raven")
eve.CREST.getLatestSellOrders(regionID("The Forge"), 638)
t = eve.CREST.getMarketHistory(eve.regionID("The Forge"), 638)
v = eve.CREST.addAverageOrderVols(t)
g = cat(1, v...)
size(v)
g[1, 4]
v[2][2,1]
typeof(v)
