require 'coinbase/exchange'
require 'orderbook/real_time_book'
require 'orderbook/book_methods'
require 'orderbook/book_analysis'
require 'orderbook/version'

class Orderbook
  include BookMethods
  include BookAnalysis

  # Array of bids
  #
  attr_reader :bids

  # Array of asks
  #
  attr_reader :asks

  # Sequence number of snapshot
  #
  attr_reader :sequence

  # CBX::Feed object
  #
  attr_reader :feed

  def initialize
    @sequence = 0
    @bids = []
    @asks = []
    @cb = Coinbase::Exchange::AsyncClient.new
    @feed = Coinbase::Exchange::Websocket.new(keepalive: true)

    @feed.message do |message|
      apply(message)
      summarize
    end

    EM.run do
      @cb.orderbook(level: 3) do |resp|
        @bids = resp['bids']
        @asks = resp['asks']
        @sequence = resp['sequence']
      end

      @feed.start!
      EM.add_periodic_timer(15) {
        @feed.ping do
          p "websocket is alive"
        end
      }
      EM.error_handler { |e|
        print "Websocket Error: #{e.message} - #{e.backtrace.join("\n")}"
      }

      @cb.orderbook(level: 3) do |resp|
        @bids = resp['bids']
        @asks = resp['asks']
        @sequence = resp['sequence']
      end
    end
  end
end

