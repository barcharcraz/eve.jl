# sde deals with the static data export,
# ideally it will download and parse the SDE

module SDE
using SQLite
using Requests
bitstype 32 Region

const sdemd5Addr = "https://www.fuzzwork.co.uk/dump/sqlite-latest.sqlite.bz2.md5"
const sdeAddr = "https://www.fuzzwork.co.uk/dump/sqlite-latest.sqlite.bz2"


global db = SQLite.DB("sqlite-latest.sqlite")
#increase database read speed at the cost of
#data integrety. We don't care since we never write
#so even without good transaction garentees we're fine
query(db, "PRAGMA synchronous = OFF")
query(db, "PRAGMA journal_mode = OFF")


function itemID(itemName :: AbstractString)
  result = SQLite.query(db, "SELECT typeID FROM invTypes WHERE typeName=?", [itemName])
  get(result.data[1][1])
end
function itemName(itemID :: Int)
  result = SQLite.query(db, "SELECT typeName FROM invTypes WHERE typeID=?", [itemID])
  get(result.data[1][1])
end
function solarSystemID(sysName :: AbstractString)
  result = query(db, "SELECT solarSystemID FROM mapSolarSystems WHERE solarSystemName=?", [sysName])
  get(result.data[1][1])
end

function regionID(regionName :: AbstractString)
  result = query(db, "SELECT regionID FROM mapRegions WHERE regionName=?", [regionName])
  get(result.data[1][1])
end

function regionName(regionID :: Int)
  result = query(db, "SELECT regionName FROM mapRegions WHERE regionID=?", [regionID])
  get(result.data[1][1])
end
"""
Get the market group ID of the group named `marketGroupName`.
Note that group names are not nessassarly unique, for example many group names
exist under both blueprints and somewhere else. This function will
simply return the first groupID (ordered by groupID). This should be
the "real" group and not the blueprint
"""
function marketGroupID(marketGroupName :: AbstractString)
  db = SQLite.DB("sqlite-latest.sqlite")
  result = query(db,
    "select marketGroupID from invMarketGroups where marketGroupName=? order by marketGroupID limit 1",
    [marketGroupName])
  get(result.data[1][1])
end

function getItemsFromGroup(groupID :: Int)
  db = SQLite.DB("sqlite-latest.sqlite")
  q = "WITH RECURSIVE child_groups(marketGroupID) AS "*
      "( Values(?) union select invMarketGroups.marketGroupID from "*
      "invMarketGroups, child_groups where invMarketGroups.parentGroupID=child_groups.marketGroupID) "*
      "select typeid from child_groups join invTypes on invTypes.marketGroupID=child_groups.marketGroupID "*
      "order by typeid"
  result = query(db, q, [groupID])
  result.data[1].values
end

"""
just gets a list of all the market items in the game
"""
function getAllMarketItems()
  db = SQLite.DB("sqlite-latest.sqlite")
  q = "WITH ids as (SELECT marketGroupID from invMarketGroups where hasTypes=1) "*
      "SELECT typeID from invTypes INNER JOIN ids ON invTypes.marketGroupID=ids.marketGroupID"
  result = query(db, q)
  result.data[1].values
end

"""
gets all the itemsIDs on the market in EVE, but leaves out DUST514 related items
because lol they won't sell.
"""
function getAllEveItems()
  itms = getAllMarketItems()
  dust = getItemsFromGroup(marketGroupID("Infantry Gear"))
  setdiff(itms, dust)
end

function Base.string(c :: Region)
  regionName(c)
end

export itemID, solarSystemID, regionID
export itemName
export marketGroupID, getItemsFromGroup
export getAllEveItems, getAllMarketItems
export Region
end
