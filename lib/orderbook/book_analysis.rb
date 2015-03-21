module Orderbook
  module BookAnalysis
    def bid_count
      @bids.count
    end

    def ask_count
      @asks.count
    end

    def bid_volume
      @bids.map {|x| x.fetch(1).to_f}.inject(:+)}
    end

    def ask_volume
      @asks.map {|x| x.fetch(1).to_f}.inject(:+)}
    end

    def average_bid
      array = @bids.map do |price, amount, id|
        price.to_f
      end
      avg_bid = array.inject(:+) / array.count
      avg_bid.to_s
    end

    def average_ask
      array = @asks.map do |price, amount, id|
        price.to_f
      end
      avg_ask = array.inject(:+) / array.count
      avg_ask.to_s
    end

    def best_bid
      @bids.sort_by {|x| x.fetch(0).to_f}.last[0,2]}
    end

    def best_ask
      @asks.sort_by {|x| x.fetch(0).to_f}.first[0,2]}
    end

    def spread
      best_sell - best_ask
    end
  end
end
