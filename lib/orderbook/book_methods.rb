require 'bigdecimal'
class Orderbook
  # This class provides methods to apply updates to the state of the orderbook
  # as they are received by the websocket.
  #
  module BookMethods
    BIGDECIMAL_KEYS = %w(size old_size new_size remaining_size price)

    # Applies a message to an Orderbook object by making relevant changes to
    # @bids, @asks, and @last_sequence.
    #
    def apply(msg)
      return if msg.fetch('sequence') != @last_sequence + 1
      #if msg.fetch('sequence') != @last_sequence + 1
      #  puts "Expected #{@last_sequence + 1}, got #{msg.fetch('sequence')}"
      #  @websocket.stop!
      #end
      @last_sequence = msg.fetch('sequence')
      BIGDECIMAL_KEYS.each do |key|
        msg[key] = BigDecimal.new(msg.fetch(key)) if msg.fetch(key, false)
      end

      __send__(msg.fetch('type'), msg)
    end

    private

    def open(msg)
      order = {
        price:    msg.fetch('price'),
        size:     msg.fetch('remaining_size'),
        order_id: msg.fetch('order_id')
      }

      @bids << order if msg.fetch('side') == 'buy'
      @asks << order if msg.fetch('side') == 'sell'
    end

    def match(msg)
      decrement_match = lambda do |o|
        if o.fetch(:order_id) == msg.fetch('maker_order_id')
          o[:size] = o.fetch(:size) - msg.fetch('size')
        end
      end

      @asks.map(&decrement_match) if msg.fetch('side') == 'sell'
      @bids.map(&decrement_match) if msg.fetch('side') == 'buy'
    end

    def done(msg)
      matching_order = ->(o) { o.fetch(:order_id) == msg.fetch('order_id') }

      @asks.reject!(&matching_order) if msg.fetch('side') == 'sell'
      @bids.reject!(&matching_order) if msg.fetch('side') == 'buy'
    end

    def change(msg)
      change_order = lambda do |o|
        if o.fetch(:order_id) == msg.fetch('order_id')
          o[:size] = msg.fetch('new_size')
        end
      end

      @asks.map(&change_order) if msg.fetch('side') == 'sell'
      @bids.map(&change_order) if msg.fetch('side') == 'buy'
    end

    def received(_)
      # The book doesn't change for this message type.
    end
  end
end
