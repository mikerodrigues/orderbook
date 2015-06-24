require 'orderbook/book_methods'
require 'orderbook/book_analysis'

module Orderbook
  class RealTimeBook
    include BookMethods
    include BookAnalysis

    # Time to wait until considering skipped messages lost.
    #
    LOST_TIMEOUT = 5

    # Array of bids
    #
    attr_reader :bids

    # Array of asks
    #
    attr_reader :asks

    # Sequence number of snapshot
    #
    attr_reader :sequence

    # Most recently processed sequence
    #
    attr_reader :last_sequence

    # Hash of missing sequence numbers and their timeout threads.
    #
    attr_reader :missing

    # CBX::Feed object
    #
    attr_reader :feed

    # Queue of messages to be processed
    #
    attr_reader :queue

    def initialize(&block)
      if block_given?
        @callback = block
      end
      subscribe
      snapshot
      process_queue
    end

    def set_callback(&block)
      @callback = block
    end

    def refresh_snapshot
      @thread.kill
      snapshot
      process_queue
    end

    private

    def subscribe
      @queue = Queue.new
      @missing = {}
      on_msg = lambda {|msg| @queue << msg}
      on_close = lambda {|close| puts close}
      on_err = lambda {|err| puts err}
      @feed = ::CBX::Feed.new(on_msg, on_close, on_err)
    end

    def snapshot
      @cb || @cb = ::CBX.new
      @snapshot = @cb.book({level: 3}, 'BTC-USD')
      @sequence = @snapshot.fetch('sequence').to_i
      @bids = @snapshot.fetch('bids')
      @asks = @snapshot.fetch('asks')
    end

    def timeout(sequence)
      warn "Missing sequence #{sequence} timed out. Refreshingn snapshot."
      refresh_snapshot
    end

    def check_sequence(sequence, expected_sequence)
      if sequence != expected_sequence
        if @missing.keys.include? (expected_sequence)
          @missing.fetch(expected_sequence).kill
          @missing.delete(expected_sequence)
        else
          @missing[expected_sequence] = Thread.new do
            sleep LOST_TIMEOUT
            timeout expected_sequence
          end
        end
        @missing < expected_sequence
      end
    end

    def process_queue
      @thread && @thread.kill
      @thread = Thread.new do
        @last_sequence = 'start'
        loop do
          msg = @queue.shift
          sequence = msg.fetch('sequence').to_i
          next if sequence <= @sequence
          unless @last_sequence == 'start'
            expected_sequence = @last_sequence + 1
            check_sequence(sequence, expected_sequence)
          end
          apply(msg)
          @callback && @callback.call(msg)
          @last_sequence = sequence
        end
      end
    end
  end
end

