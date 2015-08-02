require 'bigdecimal' 
class Orderbook
  # This class provides methods to apply updates to the state of the orderbook
  # as they come in as individual messages.
  #
  module BookMethods
    BIGDECIMAL_KEYS = ['size', 'old_size', 'new_size', 'remaining_size', 'price', 'funds', 'old_funds', 'new_funds']

    # Applies a message to an Orderbook object by making relevant changes to
    # @bids, @asks, and @last_sequence.
    #
    def apply(msg)
      unless msg.fetch('sequence') <= @first_sequence
        @last_sequence = msg.fetch('sequence')
        BIGDECIMAL_KEYS.each do |key|
          if msg.fetch(key, false)
            msg[key] = BigDecimal.new(msg.fetch(key))
          end
        end
        __send__(msg.fetch('type'), msg)
      end
    end

    private

    def open(msg)
      order = { price: msg.fetch('price'), size: msg.fetch('remaining_size'), order_id: msg.fetch('order_id') }
      case msg.fetch('side')
      when 'buy'
        @bids << order
      when 'sell'
        @asks << order
      end
    end

    def match(msg)
      case msg.fetch('side')
      when 'sell'
        @asks.map do |ask|
          if ask.fetch(:order_id) == msg.fetch('maker_order_id')
            ask[:size] = ask[:size] - msg.fetch('size')
          end
        end
        @bids.map do |bid|
          if bid.fetch(:order_id) == msg.fetch('taker_order_id')
            bid[:size] = bid[:size] - msg.fetch('size')
          end
        end
      when 'buy'
        @bids.map do |bid|
          if bid.fetch(:order_id) == msg.fetch('maker_order_id')
            bid[:size] = bid[:size] - msg.fetch('size')
          end
        end
        @asks.map do |ask|
          if ask.fetch(:order_id) == msg.fetch('taker_order_id')
            ask[:size] = ask[:size] - msg.fetch('size')
          end
        end
      end
    end

    def done(msg)
      case msg.fetch('side')
      when 'sell'
        @asks.reject! {|a| a.fetch(:order_id) == msg['order_id']}
      when 'buy'
        @bids.reject! {|b| b.fetch(:order_id) == msg['order_id']}
      end
    end

    def change(msg)
      case msg.fetch('side')
      when 'sell'
        @asks.map do |a|
          if a.fetch(:order_id) == msg.fetch('order_id')
            a[:size] = msg.fetch('new_size')
          end
        end
      when 'buy'
        @bids.map do |b|
          if b.fetch(:order_id) == msg.fetch('order_id')
            b[:size] = msg.fetch('new_size')
          end
        end
      end
    end

    def received(msg)
      # The book doesn't change for this message type.
    end

  end
end
