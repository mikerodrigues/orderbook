# Orderbook

A Ruby 4 client that maintains a real-time Level 2 order book from Coinbase
Advanced Trade's public WebSocket feed.

Version 5 migrates from the discontinued Coinbase Pro/Exchange `full` feed to
the current Advanced Trade `level2` feed:

- WebSocket: `wss://advanced-trade-ws.coinbase.com`
- Subscription channel: `level2`
- Keepalive channel: `heartbeats`
- Authentication: none for public market data

See Coinbase's official [Advanced Trade WebSocket
overview](https://docs.cdp.coinbase.com/coinbase-app/advanced-trade-apis/websocket/websocket-overview)
and [`level2` channel
reference](https://docs.cdp.coinbase.com/api-reference/advanced-trade-api/websocket/level2).

Coinbase now publishes aggregated price levels rather than individual orders on
this feed. Each entry in `bids` and `asks` therefore has `:price` and `:size`,
but no `:order_id`. Prices and sizes are `BigDecimal` values.

The client waits for Coinbase's WebSocket snapshot before returning from
`Orderbook.new`, applies absolute quantity updates, detects sequence gaps and
stale connections, and reconnects with a fresh snapshot when necessary.

## Requirements

- Ruby 4.x (tested with Ruby 4.0.10)

## Installation

Add the gem to your Gemfile:

```ruby
gem 'orderbook'
```

Then run:

```sh
bundle install
```

## Usage

```ruby
require 'orderbook'

book = Orderbook.new(product_id: 'BTC-USD')

book.best_bid
# => { price: #<BigDecimal ...>, size: #<BigDecimal ...> }

book.best_ask
book.spread
book.count
book.volume
book.snapshot_sequence
book.last_sequence
book.last_pong

book.stop!
```

Use a block to receive each decoded Coinbase message after the internal book
has been updated:

```ruby
book = Orderbook.new do |message|
  next unless message['channel'] == 'l2_data'

  puts "bid=#{book.best_bid.inspect} ask=#{book.best_ask.inspect}"
end
```

Create the object without connecting, then start it later:

```ruby
book = Orderbook.new(start: false)
book.start!
book.ready? # => true after the initial snapshot
book.reset! # reconnect and obtain a new snapshot
book.stop!
```

Automatic reconnects are enabled by default. Disable them when a supervisor
owns reconnection:

```ruby
book = Orderbook.new(reconnect: false)
```

## Version 4 migration notes

- This is a Level 2 price book; `:order_id` is no longer available.
- Coinbase's WebSocket snapshot replaces the old REST Level 3 snapshot, so the
  `client` and `rest_url` accessors were removed.
- Legacy Exchange API key, secret, and passphrase arguments were removed. The
  public Advanced Trade channels do not require credentials.
- `snapshot_sequence` and `last_sequence` now refer to Advanced Trade
  `sequence_num` values.
- `last_pong` is the timestamp from the latest Coinbase heartbeat.

## Security

Only `wss://` endpoints are accepted. TLS chain and hostname verification are
both enforced. Incoming messages and the processing queue are bounded, numeric
fields are parsed without floating-point conversion, and unexpected protocol
messages cannot invoke Ruby methods dynamically.

## Development

```sh
bundle install
bundle exec rake test
bundle exec rake build
```
