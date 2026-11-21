# frozen_string_literal: true

class Orderbook
  module BookAnalysis
    def bid_count = bids.count
    def ask_count = asks.count

    def count
      { bid: bid_count, ask: ask_count }
    end

    def bid_volume = sum_sizes(bids)
    def ask_volume = sum_sizes(asks)

    def volume
      { bid: bid_volume, ask: ask_volume }
    end

    def average_bid = average_price(bids)
    def average_ask = average_price(asks)

    def average
      { bid: average_bid, ask: average_ask }
    end

    def best_bid = bids.first
    def best_ask = asks.first

    def best
      { bid: best_bid, ask: best_ask }
    end

    def spread
      return unless best_bid && best_ask

      best_ask.fetch(:price) - best_bid.fetch(:price)
    end

    def summarize(io: $stdout)
      io.puts "# of asks: #{ask_count}"
      io.puts "# of bids: #{bid_count}"
      io.puts "Ask volume: #{ask_volume.to_s('F')}"
      io.puts "Bid volume: #{bid_volume.to_s('F')}"
      io.flush
    end

    private

    def sum_sizes(levels)
      levels.sum(BigDecimal('0')) { |level| level.fetch(:size) }
    end

    def average_price(levels)
      return if levels.empty?

      levels.sum(BigDecimal('0')) { |level| level.fetch(:price) } / levels.count
    end
  end
end
