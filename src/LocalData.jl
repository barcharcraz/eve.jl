#This module handles importing local data from the eve client
# as well as parsing logs

module LocalData
using eve.SDE
using eve.MarketDatas
using DataFrames
# Log import
export latestLog
export latestOrderLog
export latestMarketLog
export importOrders
export importMarketLog

function logPath()
  joinpath(homedir(), "Documents", "EVE", "logs", "Marketlogs")
end
function latestOrderLog(typePrefix = "Corporation")
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
immutable MarketLog
  path :: ASCIIString
  timestamp :: DateTime
  region :: ASCIIString
  item :: ASCIIString
end
function latestMarketLog(item = "", region = "")
  exclude = Regex("Corporation Orders|My Orders")
  groups = Regex("(.+)-(.+)-(.+)\\.txt" )
  local files :: Array{MarketLog} = []
  df = Dates.DateFormat("yyyy.mm.dd HHMMSS")
  for file in readdir(logPath())
    m = match(exclude, file)
    info = match(groups, file)
    if m == nothing && contains(info.captures[1], region) && contains(info.captures[2], item)
      push!(files, MarketLog(joinpath(logPath(), file), DateTime(info.captures[3], df), info.captures[1], info.captures[2]))
    end
  end
  sort!(files, by=x->x.timestamp, rev=true)
  if isempty(files)
    return Nullable{MarketLog}()
  else
    return Nullable(files[1])
  end
end
function importOrders(typePrefix = "Corporation")
  orders = latestOrderLog()
  if isnull(orders)
    return DataFrame()
  end
  path = get(latestOrderLog())[1]

  readtable(path, truestrings=["True"], falsestrings=["False"])[1:23]
end
function importMarketLog(item = "", region = "")
  o = get(latestMarketLog(item, region))
  res = readtable(o.path, truestrings=["True"], falsestrings=["False"])[1:14]
  names!(res, [:Price,
               :Quantity,
               :TypeID,
               :Range,
               :OrderID,
               :QuantityEntered,
               :MinQuantity,
               :bid,
               :Issued,
               :Duration,
               :StationID,
               :RegionID,
               :solarSystemID,
               :Jumps])
  (sells, buys) = groupby(res, :bid)
  MarketData(itemID(o.item),
             Logs,
             o.timestamp,
             sells,
             buys)
end
end
