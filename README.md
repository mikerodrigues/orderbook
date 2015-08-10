# Orderbook 3.0.0
<a href="https://codeclimate.com/github/mikerodrigues/orderbook"><img src="https://codeclimate.com/github/mikerodrigues/orderbook/badges/gpa.svg" /></a>

Version 3.0.0 has a slightly different interface and properly queues messages
for an accurate Orderbook.

A gem for creating a realtime order book for the Coinbase Exchange.

Version 1.0.0 and greater now use the official Coinbase Exchange Ruby Gem's
EventMachine-driven client. It should be more reliable than the previous socket
code.

Also, the gem now uses BigDecimal in place of Float when dealing with sizes and
prices.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'orderbook'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install orderbook

## Usage

```ruby
require 'orderbook'
```

* Create a live updating Orderbook:
```ruby
ob = Orderbook.new
```

* Create an Orderbook object but don't fetch an orderbook or start live
  updating.
```ruby
ob = Orderbook.new(false)

# When you want it to go live:

ob.start!
```

* Create a live Orderbook with a callback to fire on each message:
```ruby
ob = Orderbook.new do |message|
  puts message.fetch 'type'
end
```

* Create or reset the message callback:
```ruby
ob.on_message do |message|
  puts message.fetch 'sequence'
end
```

* List current bids:
```ruby
ob.bids
```

* List current asks:
```ruby
ob.asks
```

* Show sequence number for initial level 3 snapshot:
```ruby
ob.snapshot_sequence
```

* Show sequence number for the last message received
```ruby
ob.last_sequence
```

* Show the last Time a pong was received after a ping (ensures the connection is
  still alive):
```ruby
ob.last_pong
```

## Contributing

1. Fork it ( https://github.com/mikerodrigues/orderbook/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
