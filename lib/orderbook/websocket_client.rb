# frozen_string_literal: true

require 'openssl'
require 'socket'
require 'timeout'
require 'uri'
require 'websocket'

class Orderbook
  # Small RFC 6455 client optimized for Coinbase's multi-megabyte snapshots.
  # The former dependency read encrypted input one byte at a time and omitted
  # hostname verification. This transport reads chunks and uses Ruby/OpenSSL's
  # secure defaults with explicit hostname verification.
  class WebSocketClient
    Message = Data.define(:data)
    READ_SIZE = 64 * 1024
    MAX_HANDSHAKE_BYTES = 64 * 1024

    attr_reader :thread

    def self.connect(url, **options)
      new(url, **options).tap(&:connect)
    end

    def initialize(
      url,
      headers: {},
      max_message_bytes:,
      open_timeout:,
      on_open:,
      on_message:,
      on_error:,
      on_close:
    )
      @uri = URI.parse(url)
      @headers = headers
      @max_message_bytes = max_message_bytes
      @open_timeout = open_timeout
      @on_open = on_open
      @on_message = on_message
      @on_error = on_error
      @on_close = on_close
      @write_mutex = Mutex.new
      @state_mutex = Mutex.new
      @closed = false
      @open = false
      @close_emitted = false
    end

    def connect
      WebSocket.should_raise = true
      Timeout.timeout(@open_timeout) do
        tcp_socket = Socket.tcp(@uri.host, @uri.port, connect_timeout: @open_timeout)
        @socket = secure_socket(tcp_socket)
        perform_handshake
      end

      @state_mutex.synchronize { @open = true }
      @thread = Thread.new { read_messages }
      @thread.name = 'orderbook-websocket-reader'
      @on_open.call(self)
      self
    rescue StandardError
      close_socket
      raise
    end

    def send(data, type: :text)
      frame = WebSocket::Frame::Outgoing::Client.new(
        data: data,
        type: type,
        version: 13
      )
      bytes = frame.to_s
      @write_mutex.synchronize do
        raise IOError, 'WebSocket is closed' if closed?

        @socket.write(bytes)
      end
      true
    end

    def close
      should_send_close = @state_mutex.synchronize { @open && !@closed }
      send('', type: :close) if should_send_close
    rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
      nil
    ensure
      mark_closed
      close_socket
    end

    def closed?
      @state_mutex.synchronize { @closed }
    end

    def open?
      @state_mutex.synchronize { @open && !@closed }
    end

    private

    def secure_socket(tcp_socket)
      context = OpenSSL::SSL::SSLContext.new
      context.set_params
      context.min_version = OpenSSL::SSL::TLS1_2_VERSION
      context.verify_mode = OpenSSL::SSL::VERIFY_PEER
      context.verify_hostname = true

      socket = OpenSSL::SSL::SSLSocket.new(tcp_socket, context)
      socket.hostname = @uri.host
      socket.sync_close = true
      socket.connect
      socket
    rescue StandardError
      tcp_socket.close
      raise
    end

    def perform_handshake
      handshake = WebSocket::Handshake::Client.new(url: @uri.to_s, headers: @headers)
      @socket.write(handshake.to_s)
      bytes_read = 0

      until handshake.finished?
        chunk = @socket.readpartial(READ_SIZE)
        bytes_read += chunk.bytesize
        raise ProtocolError, 'WebSocket handshake headers are too large' if bytes_read > MAX_HANDSHAKE_BYTES

        handshake << chunk
      end

      return if handshake.valid?

      raise ConnectionError, "invalid WebSocket handshake: #{handshake.error}"
    end

    def read_messages
      frame = WebSocket::Frame::Incoming::Client.new(version: 13)
      until closed?
        frame << @socket.readpartial(READ_SIZE)
        # A read may contain the end of one maximum-sized frame plus the start
        # of the next frame. Keep that single-chunk allowance bounded.
        if frame.to_s.bytesize > @max_message_bytes + READ_SIZE + 14
          raise ProtocolError, "WebSocket frame exceeded #{@max_message_bytes} bytes"
        end

        while (message = frame.next)
          handle_frame(message)
        end
      end
    rescue EOFError
      nil
    rescue IOError, SystemCallError, OpenSSL::SSL::SSLError => e
      @on_error.call(e) unless closed?
    rescue StandardError => e
      @on_error.call(e)
    ensure
      mark_closed
      close_socket
    end

    def handle_frame(frame)
      case frame.type
      when :text
        raise ProtocolError, "WebSocket message exceeded #{@max_message_bytes} bytes" if frame.data.bytesize > @max_message_bytes

        @on_message.call(Message.new(frame.data))
      when :ping
        send(frame.data, type: :pong)
      when :close
        close
      when :pong
        nil
      else
        raise ProtocolError, "unsupported WebSocket frame type: #{frame.type.inspect}"
      end
    end

    def mark_closed
      emit_close = @state_mutex.synchronize do
        @open = false
        @closed = true
        next false if @close_emitted

        @close_emitted = true
        true
      end
      @on_close.call(nil) if emit_close
    end

    def close_socket
      @socket&.close unless @socket&.closed?
    rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
      nil
    ensure
      @socket = nil
    end
  end
end
