module PriceTools
include("EveCentral.jl")
include("SDE.jl")
include("CREST.jl")
using .CREST
using .SDE
using .EveCentral
#import EveCentral: calcMargin, calcAvgProfit, marketstat, calcVolumeMoved
using Requests
using DataFrames
function summerizeItems(items, system :: AbstractString)
  data = Requests.json(marketstat(items, system))
  DataFrame(name = items, avgSell = map(x -> x["sell"]["avg"], data), margin = map(x -> calcMargin(x) * 100, data),
            sellvolume = map(x -> x["sell"]["volume"], data), buyvolume = map(x -> x["buy"]["volume"], data),
            profit = map(calcAvgProfit, data))
end

function regionTradeSummery(items, source :: AbstractString, dest :: AbstractString)
  srcData = Requests.json(marketstat(items, source))
  destData = Requests.json(marketstat(items, dest))
  DataFrame(name = items,
            srcBuy = map(x->x["buy"]["max"], srcData),
            destSell = map(x->x["sell"]["min"], destData),
            srcMargin = map(x->calcMargin(x) * 100, srcData),
            destMargin = map(x->calcMargin(x) * 100, destData),
            margin = map((x,y)->EveCentral.calcMargin(x,y) * 100, srcData, destData))
end
export summerizeItems, regionTradeSummery


function reportOutbidItems(orders, data :: Dict{Int, MarketData})
  
  toUpdate = DataFrame([Int, Int, Float64, Float64], [:typeID, :orderID, :price, :bestPrice], 0)
  for e in eachrow(orders)
    crestSells = data[e[:typeID][1]].sells
    crestSells = crestSells[crestSells[:Location] .== e[:stationID], :]
    if size(crestSells, 1) == 0
      continue
    end
    if crestSells[:OrderID][1] != e[:orderID]
      push!(toUpdate, [e[:typeID],
                       e[:orderID],
                       e[:price],
                       crestSells[:Price][1]])

    end
  end
  toUpdate
end
