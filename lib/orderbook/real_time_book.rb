require 'orderbook/book_methods'
require 'orderbook/book_analysis'

module Orderbook
  class RealTimeBook
    attr_reader :bids
    attr_reader :asks
    attr_reader :sequence

    include BookMethods
    include BookAnalysis
    def initialize()
      @cb = ::CoinbaseExchange.new
      @queue = Queue.new
      on_msg = lambda {|msg| @queue << msg}
      on_close = lambda {|close| puts close}
      on_err = lambda {|err| puts err}
      @feed = ::CoinbaseExchange::Feed.new(on_msg, on_close, on_err)
      @snapshot = @cb.orderbook(3, 'BTC-USD')
      @sequence = @snapshot.fetch('sequence').to_f
      @bids = @snapshot.fetch('bids')
      @asks = @snapshot.fetch('asks')
      @update_thread = Thread.new do
        loop do
          msg = @queue.shift
          unless msg.fetch("sequence").to_f <= @sequence
            apply(msg)
            @callback && @callback.call(msg)
          end
        end
      end
    end

    def set_callback(&block)
      @callback = block
    end
  end
end
