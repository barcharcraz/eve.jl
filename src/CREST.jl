# deals with CCP's crest API
module CREST
using Requests
using DataFrames
using Currencies
using ProgressMeter
using TimeSeries

using eve.SDE
using eve.MarketDatas
@usingcustomcurrency isk "Interstellar Kredit" 2
export getLatestSellOrders
export getLatestBuyOrders
export getLatestOrders
export MarketData
global bucket = 400
global last_update = 0.0
global connections = 20
global connectionChanged = Condition()

function addTokens()
  global bucket
  global last_update
  t = time()
  e = t - last_update
  tok = e * 150.0
  bucket += tok
  bucket = min(bucket, 400)
  last_update = t
end

macro ratelimit(f)
  quote
    global bucket
    global connections
    addTokens()
    while bucket < 1.0 || connections < 1
      if bucket < 1.0
        sleep(rand((1/150):1.0))
      elseif connections < 1
        wait(connectionChanged)
      end
      addTokens()
    end
    bucket -= 1.0
    connections -= 1.0
    r = $(esc(f))
    connections += 1.0
    notify(connectionChanged, all=false)
    r
  end
end

const publicEndpoint = "https://public-crest.eveonline.com/"
const authEndpoint = "https://crest-tq.eveonline.com/"



let
  global endpoints
  crestresp = ""
  function endpoints()
    if crestresp != ""
      return crestresp
    end
    r = @ratelimit get(publicEndpoint)
    crestresp = Requests.json(r)
    crestresp
  end
end
function refreshEndpoints()
  r = @ratelimit get(publicEndpoint)
  crestresp = Requests.json(r)
end
function regionsEndpoint()
  endpoints()["regions"]["href"]
end
function regionEndpoint(regionID :: Number)
  regionsEndpoint() * "$regionID/"
end
function regionEndpoint(regionName :: AbstractString)
  regionEndpoint(regionID(regionName))
end
function typeEndpoint(itemID)
  endpoints()["itemTypes"]["href"] * "$itemID/"
end
function marketBuyEndpoint(region :: Number)
  publicEndpoint * "market/$region/orders/buy/"
end
function marketSellEndpoint(region :: Number)
  publicEndpoint * "market/$region/orders/sell/"
end
function marketOrdersEndpoint(region :: Number)
  publicEndpoint * "market/$region/orders/"
end
function marketHistoryEndpoint(region :: Number, itemID :: Number)
  publicEndpoint * "market/$region/types/$itemID/history/"
end

function processMarketData(jsonData)
  count = jsonData["totalCount"]
  #result = DataFrame([typeof(isk), Int, Int, Int, Dates.Day, DateTime],
  #                   [:Price, :Location, :Quantity, :MinQuantity, :Duration, :Issued], count)
  result = DataFrame()
  df = Dates.DateFormat("yyyy-mm-ddTHH:MM:SS")
  result[:Price] = map(x -> x["price"], jsonData["items"])
  result[:Location] = map(x -> x["location"]["id"], jsonData["items"])
  result[:Quantity] = map(x -> x["volume"], jsonData["items"])
  result[:MinQuantity] = map( x -> x["minVolume"], jsonData["items"])
  result[:Duration] = map(x -> Dates.Day(x["duration"]), jsonData["items"])
  result[:Issued] = map(x -> DateTime(x["issued"], df), jsonData["items"])
  result[:OrderID] = map(x -> x["id"], jsonData["items"])
  result[:Bid] = map(x -> x["buy"], jsonData["items"])
  result
end
function convertMarketHistory(df :: DataFrame)
  timestamps = map(DateTime, df[:Date])
  nrows, ncols = size(df)
  print(nrows)
  local values = Array(Float64, nrows, 7)
  values[:, 1] = df[:LowPrice]
  values[:, 2] = df[:HighPrice]
  values[:, 3] = df[:AvgPrice]
  values[:, 4] = df[:Volume]
  values[:, 5] = df[:OrderCount]
  values[:, 6] = df[:BuyVolume]
  values[:, 7] = df[:SellVolume]
  TimeArray(timestamps.data, values,
    ["LowPrice", "HighPrice", "AvgPrice", "Volume", "OrderCount", "BuyVolume", "SellVolume"])
end
function addAverageOrderVols(df :: DataFrame)
  function computevols(buy, sell, avg, vol)
    avg == buy && return [vol 0]
    avg == sell && return [0, vol]
    A = [buy sell; 1 1]
    B = [vol * avg; vol]
    X = A  \ B
    return [X[1] X[2]]
  end
  vols = map(computevols, df[:LowPrice].data,
                          df[:HighPrice].data,
                          df[:AvgPrice].data,
                          df[:Volume].data)
  vols = vcat(vols...)
  df[:BuyVolume] = vols[:, 1]
  df[:SellVolume] = vols[:, 2]
end
function processMarketHistoryData(jsonData)
  df = Dates.DateFormat("yyyy-mm-ddTHH:MM:SS")
  result = DataFrame()
  result[:Date] = map(x -> DateTime(x["date"], df), jsonData["items"])
  #timestamps = map(x -> DateTime(x["date"], df), jsonData["items"])
  result[:LowPrice] = map(x -> x["lowPrice"], jsonData["items"])
  result[:HighPrice] = map(x -> x["highPrice"], jsonData["items"])
  result[:AvgPrice] = map(x -> x["avgPrice"], jsonData["items"])
  result[:Volume] = map(x -> x["volume"], jsonData["items"])
  result[:OrderCount] = map(x -> x["orderCount"], jsonData["items"])
  addAverageOrderVols(result)
  #print(values)
  convertMarketHistory(result)
end
function getLatestSellOrders(regionID, itemID)
  uri = marketSellEndpoint(regionID)
  typ = typeEndpoint(itemID)
  resp = @ratelimit get(uri, query = Dict("type" => typ))
  if resp.status != 200
    print(resp.status)
  end
  result = processMarketData(Requests.json(resp))
  sort!(result, cols=[:Price], rev=false)
  result
end
function getLatestBuyOrders(regionID, itemID)
  uri = marketBuyEndpoint(regionID)
  typ = typeEndpoint(itemID)
  resp = @ratelimit get(uri, query = Dict("type" => typ))
  if resp.status != 200
    print(resp.status)
  end
  result = processMarketData(Requests.json(resp))
  sort!(result, cols=[:Price], rev=true)
  result
end
function getLatestOrders(regionID, item :: Int)
  result = MarketData(item, now(Dates.UTC), DataFrame(), DataFrame())
  uri = 
  resp = @ratelimit get()
  result.sells = getLatestSellOrders(regionID, item)
  result.buys = getLatestBuyOrders(regionID, item)
  result
end
function getLatestOrders{T<:Int}(regionID, items :: Array{T})
  result = Dict{Int64, MarketData}()
  p = Progress(length(items), 1, "Fetching Orders... ", 50)
  @sync for i in items
    @async begin
      result[i] = getLatestOrders(regionID, i)
      next!(p)
    end
  end
  result
end
function getMarketHistory(regionID, itemID)
  uri = marketHistoryEndpoint(regionID, itemID)
  resp = @ratelimit get(uri)
  if resp.status != 200
    print(resp.status)
  end
  processMarketHistoryData(Requests.json(resp))
end
function getMarketHistory{T<:Int}(regionID, items :: Array{T})
  result = Dict{Int64, TimeArray}()
  p = Progress(length(items), 1, "Fetching History... ", 50)
  @sync for i in items
    @async begin
      result[i] = getMarketHistory(regionID, i)
      next!(p)
    end
  end
  result
end





end
