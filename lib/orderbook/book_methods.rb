require 'bigdecimal'

class Orderbook
  module BookMethods

    def apply(msg)
      unless msg.fetch('sequence') <= @sequence
        __send__(msg.fetch('type'), msg)
      end
    end

    private

    def open(msg)
      order = [ msg.fetch("price"), msg.fetch("remaining_size"), msg.fetch("order_id") ]
      case msg.fetch("side")
      when "buy"
        @bids << order
      when "sell"
        @asks << order
      end
    end

    def match(msg)
      match_size = BigDecimal.new(msg.fetch("size"))
      case msg.fetch("side")
      when "sell"
        @asks.map do |ask|
          if ask.include? msg.fetch("maker_order_id")
            old_size = BigDecimal.new(ask.fetch(1))
            new_size = old_size - match_size
            ask[1] = new_size.to_s
          end
        end
        @bids.map do |bid|
          if bid.include? msg.fetch("taker_order_id")
            old_size = BigDecimal.net(bid.fetch(1))
            new_size = old_size - match_size
            bid[1] = new_size.to_s
          end
        end
      when "buy"
        @bids.map do |bid|
          if bid.include? msg.fetch("maker_order_id")
            old_size = BigDecimal.new(bid.fetch(1))
            new_size = old_size - match_size
            bid[1] = new_size.to_s
          end
        end
        @asks.map do |ask|
          if ask.include? msg.fetch("taker_order_id")
            old_size = BigDecimal.new(ask.fetch(1))
            new_size = old_size - match_size
            ask[1] = new_size.to_s
          end
        end
      end
    end

    def done(msg)
      case msg.fetch("side")
      when "sell"
        @asks.reject! {|a| a.include? msg.fetch("order_id")}
      when "buy"
        @bids.reject! {|a| a.include? msg.fetch("order_id")}
      end
    end

    def change(msg)
      case msg.fetch("side")
      when "sell"
        @asks.map do |a|
          if a.include? msg.fetch("order_id")
            a[1] = msg.fetch("new_size")
          end
        end
      when "buy"
        @bids.map do |b|
          if b.include? msg.fetch("order_id")
            b[1] = msg.fetch("new_size")
          end
        end
      end
    end

    def received(msg)
    end

  end
end
