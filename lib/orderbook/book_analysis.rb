class Orderbook
  module BookAnalysis
    def bid_count
      @bids.count
    end

    def ask_count
      @asks.count
    end

    def bid_volume
      @bids.map {|x| BigDecimal.new(x.fetch(1))}.inject(:+)
    end

    def ask_volume
      @asks.map {|x| BigDecimal.new(x.fetch(1))}.inject(:+)
    end

    def average_bid
      array = @bids.map do |price, amount, id|
        BigDecimal.new price
      end
      avg_bid = array.inject(:+) / array.count
      avg_bid
    end

    def average_ask
      array = @asks.map do |price, amount, id|
        BigDecimal.new price
      end
      avg_ask = array.inject(:+) / array.count
      avg_ask
    end

    def best_bid
      BigDecimal.new @bids.sort_by {|x| BigDecimal.new(x.fetch(0))}.last.first
    end

    def best_ask
      BigDecimal.new @asks.sort_by {|x| BigDecimal.new(x.fetch(0))}.first.first
    end

    def spread
      best_ask - best_bid
    end

    def summarize
      print "# of asks: #{ask_count}\n# of bids: #{bid_count}\nAsk volume: #{ask_volume.to_s('F')}\nBid volume: #{bid_volume.to_s('F')}\n"
      $stdout.flush
#      puts "Avg. ask: #{average_ask}"
#      puts "Avg. bid: #{average_bid}"
#      puts "Best ask: #{best_bid}"
#      puts "Best bid: #{best_ask}"
#      puts "Spread: #{spread}"
    end
  end
end
