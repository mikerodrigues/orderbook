require 'coinbase/exchange'
require 'orderbook/book_methods'
require 'orderbook/book_analysis'
require 'orderbook/real_time_book'
require 'orderbook/version'

# This class represents the current state of the CoinBase Exchange orderbook.
#
class Orderbook
  include BookMethods
  include BookAnalysis

  PING_INTERVAL = 15 # seconds in between pinging the connection.

  # Array of bids
  #
  attr_reader :bids

  # Array of asks
  #
  attr_reader :asks

  # Sequence number from the initial level 3 snapshot
  #
  attr_reader :first_sequence

  # Sequence number of most recently received message
  #
  attr_reader :last_sequence

  # Coinbase::Exchange::Websocket object
  #
  attr_reader :websocket

  # Coinbase::Exchange::AsyncClient object
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
  attr_accessor :callback

  # Creates a new live copy of the orderbook.
  #
  # If +live+ is set to false, the orderbook will not start automatically.
  #
  # If a +block+ is given it is passed each message as it is received.
  #
  def initialize(live = true, &block)
    @bids = [{price: nil, size: nil, order_id: nil}]
    @asks = [{price: nil, size: nil, order_id: nil}]
    @first_sequence = 0
    @last_sequence = 0
    @websocket = Coinbase::Exchange::Websocket.new(keepalive: true)
    @client = Coinbase::Exchange::AsyncClient.new
    @callback = block if block_given?
    live && live!
  end

  # Used to start the thread that listens to updates on the websocket and
  # applies them to the current orderbook to create a live book.
  #
  def live!
    setup_websocket
    start_thread
  end

  private

  def setup_websocket
    @websocket.message do |message|
      apply(message)
      @callback && @callback.call(message)
    end
  end

  def fetch_current_orderbook
    @client.orderbook(level: 3) do |resp|
      @bids = resp['bids'].map do |price, size, order_id|
        {
          price: BigDecimal.new(price),
          size: BigDecimal.new(size),
          order_id: order_id
        }
      end
      @asks = resp['asks'].map do |price, size, order_id|
        {
          price: BigDecimal.new(price),
          size: BigDecimal.new(size),
          order_id: order_id
        }
      end
      @first_sequence = resp['sequence']
    end
  end

  def ping
    EM.add_periodic_timer(PING_INTERVAL) do
      @websocket.ping do
        @last_pong = Time.now
      end
    end
  end

  def handle_errors
    EM.error_handler do |e|
      print "Websocket Error: #{e.message} - #{e.backtrace.join("\n")}"
      @websocket.stop!
    end
  end

  def start_thread
    @thread = Thread.new do
      EM.run do
        fetch_current_orderbook
        @websocket.start!
        ping
        handle_errors
      end
    end
  end
end
