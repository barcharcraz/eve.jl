# deals with CCP's crest API
module CREST
using Requests
using DataFrames
using SQLite
using Currencies
using ProgressMeter
using TimeSeries

using eve.SDE
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

type MarketData
  itemID :: Int64
  timeFetched :: DateTime
  sells :: DataFrame
  buys :: DataFrame
end

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
# Log import

function logPath()
  joinpath(homedir(), "Documents", "EVE", "logs", "Marketlogs")
end
function latestLog(typePrefix = "Corporation")
  fullPrefix = typePrefix * " Orders"
  reg = Regex("$fullPrefix-(.+)\\.txt")
  local files :: Array{Tuple{ASCIIString, DateTime}} = []
  df = Dates.DateFormat("yyyy.mm.dd HHMM")
  for file in readdir(logPath())
    m = match(reg, file)
    if m != nothing
      push!(files, (joinpath(logPath(), file), DateTime(m.captures[1], df)))
    end
  end
  sort!(files, by=x->x[2], rev=true)
  if isempty(files)
    return Nullable{Tuple{ASCIIString,DateTime}}()
  else
    return Nullable(files[1])
  end
end


# MARKET DATA SAVING
export storeMarketData
const schema = ["""
CREATE TABLE metadata (
id INTEGER PRIMARY KEY ASC,
itemID INTEGER,
timeFetched TEXT
);""",
"""CREATE TABLE sells (
id INTEGER PRIMARY KEY ASC,
mID INTEGER,
OrderID INTEGER,
Price INTEGER,
Location INTEGER,
Quantity INTEGER,
MinQuantity INTEGER,
Duration INTEGER,
Issued TEXT
);""",
"""CREATE TABLE buys (
id INTEGER PRIMARY KEY ASC,
mID INTEGER,
OrderID INTEGER,
Price INTEGER,
Location INTEGER,
Quantity INTEGER,
MinQuantity INTEGER,
Duration INTEGER,
Issued TEXT
);
""",
"""
CREATE TABLE history_data (
  id INTEGER PRIMARY KEY ASC,
  ItemID INTEGER,
  Date TEXT,
  LowPrice Real,
  HighPrice Real,
  AvgPrice Real,
  Volume INTEGER,
  OrderCount INTEGER,
  CONSTRAINT one_record UNIQUE (date, itemID)
);
"""]

# Code to save and load market data #
function initializeDB(filename :: ASCIIString)
  db = SQLite.DB(filename)
  for e in schema
    query(db, e)
  end
  db
end

function storeHistoryData(db, itemID :: Int, data :: TimeArray)
  q = "INSERT OR REPLACE INTO history_data " *
      "(ItemID, Date, LowPrice, HighPrice, AvgPrice, Volume, OrderCount) " *
      "VALUES (?, ?, ?, ?, ?, ?, ?)"
  s = SQLite.Stmt(db, q)
  for row = 1:length(data)
    SQLite.bind!(s, 1, itemID)
    SQLite.bind!(s, 2, string(data[row].timestamp[1]))
    SQLite.bind!(s, 3, data[row]["LowPrice"].values[1])
    SQLite.bind!(s, 4, data[row]["HighPrice"].values[1])
    SQLite.bind!(s, 5, data[row]["AvgPrice"].values[1])
    SQLite.bind!(s, 6, round(data[row]["Volume"].values[1]))
    SQLite.bind!(s, 7, round(data[row]["OrderCount"].values[1]))
    SQLite.execute!(s)
  end
end

function storeHistoryData(db :: SQLite.DB, data :: Dict{Int64, TimeArray})
  query(db, "BEGIN TRANSACTION")
  for (idx, i) in data
    storeHistoryData(db, idx, i)
  end
  query(db, "END TRANSACTION")
end

function storePriceData(db, table, mID, data :: DataFrame)
  q = "INSERT INTO $table "*
      "(mID, OrderID, Price, Location, Quantity, MinQuantity, Duration, Issued)"*
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
  s = SQLite.Stmt(db, q)
  for row = 1:length(data[1])
    SQLite.bind!(s, 1, mID)
    SQLite.bind!(s, 2, data[:OrderID][row])
    SQLite.bind!(s, 3, data[:Price][row])
    SQLite.bind!(s, 4, data[:Location][row])
    SQLite.bind!(s, 5, data[:Quantity][row])
    SQLite.bind!(s, 6, data[:MinQuantity][row])
    SQLite.bind!(s, 7, Int(data[:Duration][row]))
    SQLite.bind!(s, 8, string(data[:Issued][row]))
    SQLite.execute!(s)
  end
end

function storeMarketData(db :: SQLite.DB, data :: MarketData)
  query(db, "INSERT INTO metadata (itemID, timeFetched) VALUES (?, ?)",
        [data.itemID, string(data.timeFetched)])
  r = query(db, "SELECT last_insert_rowid()")
  mID :: Int = get(r.data[1][1])
  storePriceData(db, "sells", mID, data.sells)
  storePriceData(db,"buys", mID, data.buys)
end
function storeMarketData(db :: SQLite.DB, data)
  SQLite.query(db, "BEGIN TRANSACTION")
  for (idx,i :: MarketData) in data
    storeMarketData(db, i)
  end
  SQLite.query(db, "END TRANSACTION")
end
function storeMarketData(dbname :: ASCIIString, data)
  local db
  if isfile(dbname)
    db = SQLite.DB(dbname)
  else
    db = initializeDB(dbname)
  end
  storeMarketData(db, data)
end




function loadMarketHistory(db, itemID :: Int)
  df = DataFrame(query(db, "SELECT * FROM history_data WHERE ItemID = ?", [itemID]))
  convertMarketHistory(df)
end

function loadMarketHistory(db, itemID :: Int, since :: DateTime)
  local timestamps :: Vector{DateTime}
  df = DataFrame(query(db, "SELECT * FROM history_data WHERE ItemID = ? AND Date > datetime(?)", [itemID, string(since)]))
  convertMarketHistory(df)
end

function loadMarketData(db :: SQLite.DB)
end

end
