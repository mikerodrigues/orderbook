require 'coinbase/exchange'
require 'orderbook/book_methods'
require 'orderbook/book_analysis'
require 'orderbook/real_time_book'
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

  # Coinbase::Exchange::Websocket object
  #
  attr_reader :websocket

  # Coinbase::Exchange::AsyncClient
  #
  attr_reader :client

  # Thread running the EM loop
  #
  attr_reader :thread

  # Last time a pong was received after a ping
  #
  attr_reader :last_pong

  # Callback to pass each received message to
  #
  attr_reader :callback

  def initialize(&block)
    @thread =   Thread.new do
      @bids = [[ nil, nil]]
      @asks = [[ nil, nil]]
      @sequence = 0
      @websocket = Coinbase::Exchange::Websocket.new(keepalive: true)
      @client = Coinbase::Exchange::AsyncClient.new

      if block_given?
        @callback = block
      end

      @websocket.message do |message|
        apply(message)
        @callback && @callback.call(message)
      end

      EM.run do
        @client.orderbook(level: 3) do |resp|
          @bids = resp['bids']
          @asks = resp['asks']
          @sequence = resp['sequence']
        end

        @websocket.start!
        EM.add_periodic_timer(15) {
          @websocket.ping do
            @last_pong = Time.now
          end
        }
        EM.error_handler { |e|
          print "Websocket Error: #{e.message} - #{e.backtrace.join("\n")}"
        }

      end
    end
  end

  def set_callback(&block)
    @callback = block
  end
end
