module PriceTools
using eve.CREST
using eve.SDE
using eve.MarketDatas

export ItemSummery, summerizeItem

immutable ItemSummery
  itemID :: Int64
  source :: DataSource
  timestamp :: DateTime
  minsell :: Float64
  maxbuy :: Float64
  margin :: Float64
  markup :: Float64
end

function summerizeItem(data :: MarketData)
  sells = sort(data.sells, cols = (:Price), rev = false)
  buys = sort(data.buys, cols = (:Price), rev = true)
  maxbuy = buys[:Price][1]
  minsell = sells[:Price][1]
  margin = (minsell - maxbuy) / minsell
  markup = (minsell - maxbuy) / maxbuy
  ItemSummery(data.itemID,
              data.source,
              data.timeFetched,
              minsell,
              maxbuy,
              margin,
              markup)
end

end
