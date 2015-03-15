module Orderbook
  module BookAnalysis
    def size
      puts "Bids: #{@bids.count}"
      puts "Asks: #{@asks.count}"
    end

    def volume
      puts "Bid volume: #{@bids.map {|x| x.fetch(1).to_f}.inject(:+)}"
      puts "Ask volume: #{@asks.map {|x| x.fetch(1).to_f}.inject(:+)}"
    end

    def average
      array = @bids.map do |price, amount, id|
        price.to_f
      end
      avg_bid = array.inject(:+) / array.count
      puts "Avg. Bid: #{avg_bid}"

      array = @asks.map do |price, amount, id|
        price.to_f
      end
      avg_ask = array.inject(:+) / array.count
      puts "Avg. Asks: #{avg_ask}"
    end

    def best
      puts "Best Bid: #{(@bids.sort_by {|x| x.fetch(0).to_f}).last}"
      puts "Best Ask: #{@asks.sort_by {|x| x.fetch(0).to_f}.first}"
    end

  end
end
