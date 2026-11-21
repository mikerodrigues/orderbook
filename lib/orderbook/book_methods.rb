# frozen_string_literal: true

class Orderbook
  # Applies Coinbase Advanced Trade Level 2 snapshots and absolute updates.
  module BookMethods
    def apply(message)
      return false unless message['channel'] == 'l2_data'

      sequence = Integer(message.fetch('sequence_num'))
      events = message.fetch('events')
      raise ProtocolError, 'events must be an array' unless events.is_a?(Array)

      @state_mutex.synchronize do
        return false if @last_sequence && sequence <= @last_sequence
        if @last_sequence && sequence != @last_sequence + 1
          raise SequenceGapError, "Coinbase sequence gap: expected #{@last_sequence + 1}, got #{sequence}"
        end

        snapshot_seen = false
        events.each do |event|
          next unless event.is_a?(Hash) && event['product_id'] == @product_id

          case event['type']
          when 'snapshot'
            @bids_by_price.clear
            @asks_by_price.clear
            snapshot_seen = true
          when 'update'
            raise ProtocolError, 'received an update before a snapshot' unless @ready || snapshot_seen
          else
            next
          end

          updates = event.fetch('updates')
          raise ProtocolError, 'updates must be an array' unless updates.is_a?(Array)

          updates.each { |update| apply_level(update) }
        end

        if snapshot_seen
          @snapshot_sequence = sequence
          mark_ready
        end
        @last_sequence = sequence
      end
      true
    end

    private

    def apply_level(update)
      raise ProtocolError, 'level update must be an object' unless update.is_a?(Hash)

      price = decimal(update.fetch('price_level'), :price_level)
      size = decimal(update.fetch('new_quantity'), :new_quantity)
      raise ProtocolError, 'price_level must be greater than zero' unless price.positive?
      raise ProtocolError, 'new_quantity must not be negative' if size.negative?

      levels = case update.fetch('side')
               when 'bid' then @bids_by_price
               when 'offer' then @asks_by_price
               else raise ProtocolError, "unknown order-book side: #{update['side'].inspect}"
               end

      if size.zero?
        levels.delete(price)
      else
        levels[price] = { price: price, size: size }.freeze
      end
    end

    def decimal(value, field)
      BigDecimal(value.to_s)
    rescue ArgumentError
      raise ProtocolError, "#{field} must be a decimal string"
    end
  end
end
