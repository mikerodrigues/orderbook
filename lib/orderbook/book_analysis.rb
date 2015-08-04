class Orderbook
  # Simple collection of commands to get info about the orderbook. Add our own
  # methods for calculating whatever it is you feel like calculating.
  #
  module BookAnalysis
    def bid_count
      @bids.count
    end

    def ask_count
      @asks.count
    end

    def count
      { bid: bid_count, ask: ask_count }
    end

    def bid_volume
      @bids.map { |x| x.fetch(:size) }.inject(:+)
    end

    def ask_volume
      @asks.map { |x| x.fetch(:size) }.inject(:+)
    end

    def volume
      { bid: bid_volume, ask: ask_volume }
    end

    def average_bid
      bids = @bids.map { |x| x.fetch(:price) }
      bids.inject(:+) / bids.count
    end

    def average_ask
      asks = @asks.map { |x| x.fetch(:price) }
      asks.inject(:+) / asks.count
    end

    def average
      { bid: average_bid, ask: average_ask }
    end

    def best_bid
      @bids.sort_by { |x| x.fetch(:price) }.last
    end

    def best_ask
      @asks.sort_by { |x| x.fetch(:price) }.first
    end

    def best
      { bid: best_bid, ask: best_ask }
    end

    def spread
      best_ask.fetch(:price) - best_bid.fetch(:price)
    end

    def summarize
      print "# of asks: #{ask_count}\n# of bids: #{bid_count}\nAsk volume: #{ask_volume.to_s('F')}\nBid volume: #{bid_volume.to_s('F')}\n"
      $stdout.flush
    end
  end
end
