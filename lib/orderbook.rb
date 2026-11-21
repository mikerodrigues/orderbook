# frozen_string_literal: true

require 'bigdecimal'
require 'json'
require 'openssl'
require 'orderbook/book_analysis'
require 'orderbook/book_methods'
require 'orderbook/version'
require 'orderbook/websocket_client'
require 'time'
require 'uri'

# Maintains an in-memory Level 2 order book from Coinbase Advanced Trade.
class Orderbook
  include BookMethods
  include BookAnalysis

  DEFAULT_PRODUCT_ID = 'BTC-USD'
  DEFAULT_WEBSOCKET_URL = 'wss://advanced-trade-ws.coinbase.com'
  OPEN_TIMEOUT = 10
  STARTUP_TIMEOUT = 20
  STALE_TIMEOUT = 15
  RECONNECT_DELAY = 1
  THREAD_JOIN_TIMEOUT = 2
  MAX_MESSAGE_BYTES = 10 * 1024 * 1024
  MAX_QUEUED_MESSAGES = 10_000
  STOP_MESSAGE = Object.new.freeze
  PRODUCT_ID_PATTERN = /\A[A-Z0-9][A-Z0-9._-]{0,63}-[A-Z0-9][A-Z0-9._-]{0,63}\z/

  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ConnectionError < Error; end
  class ProtocolError < Error; end
  class SequenceGapError < ProtocolError; end

  attr_reader :product_id, :snapshot_sequence, :last_sequence, :last_pong
  attr_reader :websocket, :em_thread, :processing_thread, :queue
  attr_reader :websocket_url, :last_error

  # Set start: false to configure the object without opening a connection.
  # The public market-data feed does not require Coinbase API credentials.
  def initialize(
    product_id: DEFAULT_PRODUCT_ID,
    start: true,
    websocket_url: DEFAULT_WEBSOCKET_URL,
    reconnect: true,
    startup_timeout: STARTUP_TIMEOUT,
    stale_timeout: STALE_TIMEOUT,
    &block
  )
    @product_id = validate_product_id(product_id)
    @websocket_url = validate_websocket_url(websocket_url)
    @reconnect = reconnect
    @startup_timeout = positive_number(startup_timeout, :startup_timeout)
    @stale_timeout = positive_number(stale_timeout, :stale_timeout)
    @on_message = block
    @state_mutex = Mutex.new
    @ready_condition = ConditionVariable.new
    @lifecycle_mutex = Mutex.new
    reset_runtime_state
    start! if start
  end

  # Opens the feed and blocks until Coinbase sends a Level 2 snapshot.
  def start!
    @lifecycle_mutex.synchronize do
      return self if running?

      reset_runtime_state
      @processing_thread = Thread.new { process_messages }
      @processing_thread.name = 'orderbook-message-processor'
      @em_thread = Thread.new { manage_connection }
      @em_thread.name = 'orderbook-connection-manager'
    end

    wait_until_ready!
    self
  rescue StandardError
    stop!
    raise
  end

  # Closes the connection and stops all background threads.
  def stop!
    @lifecycle_mutex.synchronize do
      @state_mutex.synchronize do
        @stopping = true
        @ready_condition.broadcast
      end
      close_websocket
      push_stop_message
    end

    stop_thread(@processing_thread)
    stop_thread(@em_thread)
    @processing_thread = nil
    @em_thread = nil
    @websocket = nil
    self
  end

  def reset!
    stop!
    start!
  end

  def on_message(&block)
    @on_message = block
    self
  end

  def ready?
    @state_mutex.synchronize { @ready }
  end

  def running?
    [@processing_thread, @em_thread].compact.any?(&:alive?)
  end

  # Returns a stable copy sorted best price first.
  def bids
    @state_mutex.synchronize do
      @bids_by_price.values.sort_by { |level| -level.fetch(:price) }.map(&:dup)
    end
  end

  # Returns a stable copy sorted best price first.
  def asks
    @state_mutex.synchronize do
      @asks_by_price.values.sort_by { |level| level.fetch(:price) }.map(&:dup)
    end
  end

  private

  def reset_runtime_state
    @stopping = false
    @ready = false
    @last_error = nil
    @last_pong = nil
    @snapshot_sequence = nil
    @last_sequence = nil
    @generation = 0
    @reconnect_generation = nil
    @last_received_at = nil
    @opened_at = nil
    @bids_by_price = {}
    @asks_by_price = {}
    @queue = SizedQueue.new(MAX_QUEUED_MESSAGES)
  end

  def manage_connection
    loop do
      break if stopping?

      generation = begin_connection_attempt
      begin
        connect(generation)
        monitor_connection(generation)
      rescue StandardError => e
        record_error(ConnectionError.new("Coinbase WebSocket connection failed: #{e.message}"))
      ensure
        close_websocket
      end

      break if stopping? || !@reconnect

      interruptible_sleep(RECONNECT_DELAY)
    end
  end

  def begin_connection_attempt
    @state_mutex.synchronize do
      @generation += 1
      @ready = false
      @snapshot_sequence = nil
      @last_sequence = nil
      @bids_by_price.clear
      @asks_by_price.clear
      @opened_at = nil
      @last_received_at = monotonic_time
      @reconnect_generation = nil
      @generation
    end
  end

  def connect(generation)
    orderbook = self
    @websocket = WebSocketClient.connect(
      @websocket_url,
      headers: { 'User-Agent' => "orderbook/#{VERSION}" },
      max_message_bytes: MAX_MESSAGE_BYTES,
      open_timeout: OPEN_TIMEOUT,
      on_open: ->(socket) { orderbook.send(:websocket_opened, socket, generation) },
      on_message: ->(event) { orderbook.send(:websocket_message, event, generation) },
      on_error: ->(error) { orderbook.send(:websocket_failed, error, generation) },
      on_close: ->(event) { orderbook.send(:websocket_closed, event, generation) }
    )
  end

  def websocket_opened(socket, generation)
    return unless current_generation?(generation)

    # Coinbase requires one subscription message per channel.
    socket.send(JSON.generate(type: 'subscribe', channel: 'level2', product_ids: [@product_id]))
    socket.send(JSON.generate(type: 'subscribe', channel: 'heartbeats'))
    @state_mutex.synchronize do
      @opened_at = monotonic_time
      @last_received_at = @opened_at
    end
  rescue StandardError => e
    websocket_failed(e, generation)
  end

  def websocket_message(event, generation)
    return unless current_generation?(generation)

    data = event.data.to_s
    if data.bytesize > MAX_MESSAGE_BYTES
      return request_reconnect(
        ProtocolError.new("Coinbase message exceeded #{MAX_MESSAGE_BYTES} bytes"),
        generation
      )
    end

    @state_mutex.synchronize { @last_received_at = monotonic_time }
    @queue.push([generation, data])
  end

  def websocket_failed(error, generation)
    request_reconnect(ConnectionError.new("Coinbase WebSocket error: #{error}"), generation)
  end

  def websocket_closed(event, generation)
    request_reconnect(ConnectionError.new("Coinbase WebSocket closed: #{event.inspect}"), generation)
  end

  def monitor_connection(generation)
    started_at = monotonic_time
    loop do
      break if stopping? || reconnect_requested?(generation)
      unless websocket_thread_alive?
        request_reconnect(ConnectionError.new('WebSocket reader stopped'), generation)
        break
      end

      opened_at, last_received_at = @state_mutex.synchronize { [@opened_at, @last_received_at] }
      if opened_at.nil? && monotonic_time - started_at > OPEN_TIMEOUT
        request_reconnect(ConnectionError.new('Timed out opening Coinbase WebSocket'), generation)
        break
      end
      if opened_at && monotonic_time - last_received_at > @stale_timeout
        request_reconnect(ConnectionError.new('Coinbase WebSocket became stale'), generation)
        break
      end

      interruptible_sleep(0.1)
    end
  end

  def process_messages
    loop do
      item = @queue.pop
      break if item.equal?(STOP_MESSAGE)

      generation, data = item
      next unless current_generation?(generation)

      process_message(JSON.parse(data), generation)
    rescue JSON::ParserError => e
      request_reconnect(ProtocolError.new("Invalid JSON from Coinbase: #{e.message}"), generation)
    rescue ProtocolError => e
      request_reconnect(e, generation)
    rescue StandardError => e
      # User callbacks are isolated so they cannot silently kill the feed.
      record_error(e)
    end
  end

  def process_message(message, generation)
    raise ProtocolError, 'Coinbase message must be a JSON object' unless message.is_a?(Hash)

    case message['channel']
    when 'l2_data'
      return unless apply(message)
    when 'heartbeats'
      return unless advance_sequence(message)

      apply_heartbeat(message)
    when 'subscriptions'
      return unless advance_sequence(message)
    else
      return unless advance_sequence(message, required: false)

      if message['type'] == 'error' || message['channel'] == 'error'
        raise ProtocolError, "Coinbase rejected the subscription: #{message['message'] || message.inspect}"
      end
    end

    @on_message&.call(message)
  rescue SequenceGapError
    raise
  rescue KeyError, TypeError, ArgumentError => e
    raise ProtocolError, "Invalid Coinbase message: #{e.message}"
  end

  def apply_heartbeat(message)
    event = Array(message['events']).first
    value = event.is_a?(Hash) ? event['current_time'] : nil
    parsed_time = Time.iso8601(value) if value
    @state_mutex.synchronize { @last_pong = parsed_time || Time.now }
  rescue ArgumentError
    @state_mutex.synchronize { @last_pong = Time.now }
  end

  def advance_sequence(message, required: true)
    raw_sequence = message['sequence_num']
    raise ProtocolError, 'Coinbase message is missing sequence_num' if required && raw_sequence.nil?
    return true if raw_sequence.nil?

    sequence = Integer(raw_sequence)
    @state_mutex.synchronize do
      return false if @last_sequence && sequence <= @last_sequence
      if @last_sequence && sequence != @last_sequence + 1
        raise SequenceGapError, "Coinbase sequence gap: expected #{@last_sequence + 1}, got #{sequence}"
      end

      @last_sequence = sequence
    end
    true
  end

  def wait_until_ready!
    deadline = monotonic_time + @startup_timeout
    @state_mutex.synchronize do
      until @ready
        remaining = deadline - monotonic_time
        break if remaining <= 0 || @stopping

        @ready_condition.wait(@state_mutex, remaining)
      end

      return if @ready

      detail = @last_error ? ": #{@last_error.message}" : ''
      raise ConnectionError, "Timed out waiting for the Coinbase order-book snapshot#{detail}"
    end
  end

  def mark_ready
    @ready = true
    @ready_condition.broadcast
  end

  def request_reconnect(error, generation)
    @state_mutex.synchronize do
      return unless @generation == generation && !@stopping

      @last_error = error
      @reconnect_generation = generation
      @ready = false
      @ready_condition.broadcast
    end
  end

  def record_error(error)
    @state_mutex.synchronize do
      @last_error = error
      @ready_condition.broadcast
    end
  end

  def reconnect_requested?(generation)
    @state_mutex.synchronize { @reconnect_generation == generation }
  end

  def current_generation?(generation)
    @state_mutex.synchronize { @generation == generation && !@stopping }
  end

  def stopping?
    @state_mutex.synchronize { @stopping }
  end

  def websocket_thread_alive?
    @websocket&.thread&.alive?
  end

  def close_websocket
    socket = @websocket
    @websocket = nil
    socket&.close unless socket&.closed?
  rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
    nil
  end

  def push_stop_message
    @queue.push(STOP_MESSAGE, true)
  rescue ThreadError
    @processing_thread&.kill
  end

  def stop_thread(thread)
    return unless thread && thread != Thread.current

    thread.join(THREAD_JOIN_TIMEOUT)
    thread.kill if thread.alive?
  end

  def interruptible_sleep(seconds)
    deadline = monotonic_time + seconds
    sleep([deadline - monotonic_time, 0.05].min) until stopping? || monotonic_time >= deadline
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def validate_product_id(value)
    product_id = value.to_s
    return product_id.freeze if PRODUCT_ID_PATTERN.match?(product_id)

    raise ConfigurationError, "invalid Coinbase product_id: #{value.inspect}"
  end

  def validate_websocket_url(value)
    uri = URI.parse(value.to_s)
    unless uri.is_a?(URI::WSS) && uri.host && !uri.userinfo && !uri.fragment
      raise ConfigurationError, 'websocket_url must be a wss:// URL without credentials or a fragment'
    end

    uri.to_s.freeze
  rescue URI::InvalidURIError
    raise ConfigurationError, 'websocket_url must be a valid wss:// URL'
  end

  def positive_number(value, name)
    number = Float(value)
    return number if number.positive? && number.finite?

    raise ConfigurationError, "#{name} must be a positive finite number"
  rescue ArgumentError, TypeError
    raise ConfigurationError, "#{name} must be a positive finite number"
  end
end
