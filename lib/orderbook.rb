require 'coinbase/exchange'
require 'orderbook/book_methods'
require 'orderbook/book_analysis'
require 'orderbook/real_time_book'
require 'orderbook/version'
require 'eventmachine'

# This class represents the current state of the CoinBase Exchange orderbook.
#
class Orderbook
  include BookMethods
  include BookAnalysis

  # seconds in between pinging the connection.
  #
  PING_INTERVAL = 15

  # Array of bids
  #
  attr_reader :bids

  # Array of asks
  #
  attr_reader :asks

  # Sequence number from the initial level 3 snapshot
  #
  attr_reader :snapshot_sequence

  # Sequence number of most recently received message
  #
  attr_reader :last_sequence

  # Coinbase::Exchange::Websocket object
  #
  attr_reader :websocket

  # Coinbase::Exchange::Client object
  #
  attr_reader :client

  # Thread running the EM loop for the websocket
  #
  attr_reader :em_thread

  # Thread running the processing loop
  #
  attr_reader :processing_thread

  # DateTime of last successful pong
  #
  attr_reader :last_pong

  # Message queue for incoming messages.
  #
  attr_reader :queue

  # Creates a new live copy of the orderbook.
  #
  # If +start+ is set to false, the orderbook will not start automatically.
  #
  # If a +block+ is given it is passed each message as it is received.
  #
  def initialize(start = true, &block)
    @bids = []
    @asks = []
    @snapshot_sequence = 0
    @last_sequence = 0
    @queue = Queue.new
    @websocket = Coinbase::Exchange::Websocket.new(keepalive: true)
    @client = Coinbase::Exchange::Client.new
    @on_message = block if block_given?
    start && start!
  end

  # Used to start the thread that listens to updates on the websocket and
  # applies them to the current orderbook to create a live book.
  #
  def start!
    start_em_thread

    # Wait to make sure the snapshot sequence ID is higher than the sequence of
    # the first message in the queue.
    #
    sleep 0.3
    apply_orderbook_snapshot
    start_processing_thread
  end

  # Stops the processing thread, EM thread, and the websocket.
  #
  def stop!
    @processing_thread.kill
    @em_thread.kill
    @websocket.stop!
  end

  # Start and stop the Orderbook. Used to reset Orderbook state with a fresh
  # snapshot.
  #
  def reset!
    stop!
    start!
  end

  def on_message(&block)
    @on_message = block
  end

  private

  # Converts an order array from the API into a hash.
  #
  def order_to_hash(price, size, order_id)
    { price:    BigDecimal.new(price),
      size:     BigDecimal.new(size),
      order_id: order_id
    }
  end

  # Fetch orderbook snapshot from API and convert order arrays to hashes.
  #
  def apply_orderbook_snapshot
    @client.orderbook(level: 3) do |resp|
      @bids = resp['bids'].map { |b| order_to_hash(*b) }
      @asks = resp['asks'].map { |a| order_to_hash(*a) }
      @snapshot_sequence = resp['sequence']
      @last_sequence = resp['sequence']
    end
  end

  def setup_websocket_callback
    @websocket.message do |message|
      @queue.push(message)
    end
  end

  def setup_ping_timer
    EM.add_periodic_timer(PING_INTERVAL) do
      @websocket.ping do
        @last_pong = Time.now
      end
    end
  end

  def setup_error_handler
    EM.error_handler do |e|
      print "Websocket Error: #{e.message} - #{e.backtrace.join("\n")}"
    end
  end

  def start_em_thread
    @em_thread = Thread.new do
      setup_websocket_callback
      EM.run do
        @websocket.start!
        setup_ping_timer
        setup_error_handler
      end
    end
  end

  def start_processing_thread
    @processing_thread = Thread.new do
      loop do
        message = @queue.shift
        apply(message)
        @on_message.call(message) unless @on_message.nil?
      end
    end
  end
end
