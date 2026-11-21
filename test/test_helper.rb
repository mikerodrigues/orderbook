# frozen_string_literal: true

require 'minitest/autorun'
require 'orderbook'

module MessageFixtures
  def l2_message(sequence:, type:, updates:, product_id: 'BTC-USD')
    {
      'channel' => 'l2_data',
      'timestamp' => '2026-11-21T10:00:00Z',
      'sequence_num' => sequence,
      'events' => [
        {
          'type' => type,
          'product_id' => product_id,
          'updates' => updates
        }
      ]
    }
  end

  def level(side:, price:, size:)
    {
      'side' => side,
      'event_time' => '2026-11-21T10:00:00Z',
      'price_level' => price,
      'new_quantity' => size
    }
  end
end
