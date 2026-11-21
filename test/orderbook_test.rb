# frozen_string_literal: true

require 'test_helper'

class OrderbookTest < Minitest::Test
  include MessageFixtures

  def setup
    @book = Orderbook.new(start: false)
    @book.apply(
      l2_message(
        sequence: 0,
        type: 'snapshot',
        updates: [
          level(side: 'bid', price: '100.10', size: '2.5'),
          level(side: 'bid', price: '99.90', size: '3'),
          level(side: 'offer', price: '100.30', size: '1.25'),
          level(side: 'offer', price: '100.50', size: '4')
        ]
      )
    )
  end

  def test_snapshot_builds_a_sorted_bigdecimal_book
    assert @book.ready?
    assert_equal 0, @book.snapshot_sequence
    assert_equal 0, @book.last_sequence
    assert_equal BigDecimal('100.10'), @book.best_bid.fetch(:price)
    assert_equal BigDecimal('100.30'), @book.best_ask.fetch(:price)
    assert_equal BigDecimal('0.20'), @book.spread
    assert_equal({ bid: 2, ask: 2 }, @book.count)
  end

  def test_update_replaces_quantity_and_zero_removes_a_level
    @book.apply(
      l2_message(
        sequence: 1,
        type: 'update',
        updates: [
          level(side: 'bid', price: '100.10', size: '7.75'),
          level(side: 'offer', price: '100.30', size: '0')
        ]
      )
    )

    assert_equal BigDecimal('7.75'), @book.best_bid.fetch(:size)
    assert_equal BigDecimal('100.50'), @book.best_ask.fetch(:price)
    assert_equal 1, @book.last_sequence
  end

  def test_duplicate_message_is_ignored
    duplicate = l2_message(
      sequence: 0,
      type: 'update',
      updates: [level(side: 'bid', price: '100.10', size: '999')]
    )

    refute @book.apply(duplicate)
    assert_equal BigDecimal('2.5'), @book.best_bid.fetch(:size)
  end

  def test_sequence_gap_is_rejected
    error = assert_raises(Orderbook::SequenceGapError) do
      @book.apply(
        l2_message(
          sequence: 2,
          type: 'update',
          updates: [level(side: 'bid', price: '100.10', size: '3')]
        )
      )
    end

    assert_match 'expected 1, got 2', error.message
  end

  def test_messages_for_another_product_do_not_change_the_book
    @book.apply(
      l2_message(
        sequence: 1,
        type: 'update',
        product_id: 'ETH-USD',
        updates: [level(side: 'bid', price: '5000', size: '99')]
      )
    )

    assert_equal BigDecimal('100.10'), @book.best_bid.fetch(:price)
    assert_equal 1, @book.last_sequence
  end

  def test_non_book_messages_participate_in_the_connection_sequence
    @book.send(
      :process_message,
      { 'channel' => 'subscriptions', 'sequence_num' => 1, 'events' => [] },
      0
    )

    assert @book.apply(
      l2_message(
        sequence: 2,
        type: 'update',
        updates: [level(side: 'bid', price: '100.10', size: '4')]
      )
    )
    assert_equal 2, @book.last_sequence
    assert_equal BigDecimal('4'), @book.best_bid.fetch(:size)
  end

  def test_invalid_numeric_and_side_fields_are_rejected
    assert_raises(Orderbook::ProtocolError) do
      @book.apply(
        l2_message(
          sequence: 1,
          type: 'update',
          updates: [level(side: 'bid', price: 'NaN', size: '1')]
        )
      )
    end

    assert_raises(Orderbook::ProtocolError) do
      @book.apply(
        l2_message(
          sequence: 1,
          type: 'update',
          updates: [level(side: 'buy', price: '101', size: '1')]
        )
      )
    end
  end

  def test_empty_analysis_has_safe_results
    empty = Orderbook.new(start: false)

    assert_equal BigDecimal('0'), empty.bid_volume
    assert_equal BigDecimal('0'), empty.ask_volume
    assert_nil empty.average_bid
    assert_nil empty.spread
  end

  def test_returned_levels_cannot_mutate_internal_state
    bid = @book.bids.first
    bid[:size] = BigDecimal('123')

    assert_equal BigDecimal('2.5'), @book.best_bid.fetch(:size)
  end

  def test_rejects_insecure_or_credentialed_urls
    assert_raises(Orderbook::ConfigurationError) do
      Orderbook.new(start: false, websocket_url: 'ws://advanced-trade-ws.coinbase.com')
    end
    assert_raises(Orderbook::ConfigurationError) do
      Orderbook.new(start: false, websocket_url: 'wss://user:secret@example.com')
    end
  end

  def test_rejects_invalid_configuration
    assert_raises(Orderbook::ConfigurationError) do
      Orderbook.new(start: false, product_id: "BTC-USD\r\nInjected: yes")
    end
    assert_raises(Orderbook::ConfigurationError) do
      Orderbook.new(start: false, stale_timeout: 0)
    end
  end

  def test_heartbeat_uses_coinbase_time
    heartbeat = {
      'channel' => 'heartbeats',
      'sequence_num' => 2,
      'events' => [{ 'current_time' => '2026-11-21T10:11:12.123456Z', 'heartbeat_counter' => 9 }]
    }

    @book.send(:apply_heartbeat, heartbeat)

    assert_equal Time.iso8601('2026-11-21T10:11:12.123456Z'), @book.last_pong
  end

  def test_stop_is_safe_before_start_and_is_idempotent
    book = Orderbook.new(start: false)

    assert_same book, book.stop!
    assert_same book, book.stop!
    refute book.running?
  end
end
