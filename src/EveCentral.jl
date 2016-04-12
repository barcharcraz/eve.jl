# module deals with querying eve-central's market data
#include("SDEUtils.jl")
module EveCentral
include("SDE.jl")
using .SDE
using DataFrames
using Requests
const baseURI = "http://api.eve-central.com/api"

function marketstat(itemNames :: Array{ASCIIString,1}, systemName :: AbstractString)
  const uri = "http://api.eve-central.com/api/marketstat/json"
  types = map(itemID, itemNames)
  types = map(string, types)

  q = Dict()
  q["typeid"] = join(types, ",")
  q["usesystem"] = string(solarSystemID(systemName))
  get(uri, query = q)
end
function marketstat(itemName :: AbstractString, systemName :: AbstractString)
  marketstat([itemName], systemName)
end
#historical data functions
function historicalData(item :: AbstractString, system :: AbstractString)
  item_id = itemID(item)
  system_id = solarSystemID(system)
  uri = "http://api.eve-central.com/api/history/for/type/$item_id/system/$system_id/bid/1"
  uri
end

function calcMargin(mktStat)
  1.0 - (mktStat["buy"]["max"] / mktStat["sell"]["min"])
end
function calcMargin(source, dest)
  1.0 - (source["buy"]["max"] / dest["sell"]["min"])
end
function calcVolumeMoved(mktStat)
  min(mktStat["buy"]["volume"], mktStat["sell"]["volume"])
end
function calcAvgProfit(mktStat, expectedVol :: AbstractFloat = 0.05)
  vol = calcVolumeMoved(mktStat)
  vol = expectedVol * vol
  buy = mktStat["buy"]["max"]
  sell = mktStat["sell"]["min"]
  profit = sell - buy
  profit * vol
end

export marketstat, calcMargin, calcAvgProfit, calcVolumeMoved

end
