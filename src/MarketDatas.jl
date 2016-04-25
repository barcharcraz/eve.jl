module MarketDatas
using DataFrames
using TimeSeries
using SQLite

export MarketData, storeMarketData
export DataSource
@enum DataSource Logs CREST EveCentral
type MarketData
  itemID :: Int64
  source :: DataSource
  timeFetched :: DateTime
  sells :: DataFrame
  buys :: DataFrame
end


# MARKET DATA SAVING
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
