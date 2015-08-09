require 'coinbase/exchange'
require 'orderbook/book_methods'
require 'orderbook/book_analysis'
require 'orderbook/real_time_book'
require 'orderbook/version'
require 'eventmachine'
require 'em-priority-queue'

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

  # Thread running the EM loop for the websocket
  #
  attr_reader :websocket_thread

  # Thread running the EM loop for processing the queue
  #
  attr_reader :process_thread

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
    @bids = [{ price: nil, size: nil, order_id: nil }]
    @asks = [{ price: nil, size: nil, order_id: nil }]
    @first_sequence = 0
    @last_sequence = 0
    @queue = EM::PriorityQueue.new {|x,y| x < y } 
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
    start_threads
  end

  private

  def setup_websocket
    @websocket.message do |message|
      @queue.push(message, message.fetch('sequence'))
    end
  end

  def order_to_hash(price, size, order_id)
    { price:    BigDecimal.new(price),
      size:     BigDecimal.new(size),
      order_id: order_id
    }
  end

  def apply_orderbook_snapshot
    @client.orderbook(level: 3) do |resp|
      @bids = resp['bids'].map { |b| order_to_hash(*b) }
      @asks = resp['asks'].map { |a| order_to_hash(*a) }
      @first_sequence = resp['sequence']
      @last_sequence = resp['sequence']
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
    end
  end

  def start_threads
    @websocket_thread = Thread.new do
      EM.run do
        @websocket.start!
        ping
        handle_errors
        apply_orderbook_snapshot
      end
    end

    @process_thread = Thread.new do
      EM.run do
        loop do
          if @last_sequence == 0
            @queue.pop do |message|
              apply(message)
              @callback.call(message) unless @callback.nil?
            end
          end
        end
      end
    end
  end
end
