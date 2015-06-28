# Orderbook

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

* Create a live Orderbook with a callback to fire on each message:
```ruby
ob = Orderbook.new do |message|
  puts message.fetch 'type'
end
```

* Create or reset the callback:
```ruby
ob.set_callback do |message|
  puts message.fetch 'callback'
```

* The old class name is still supported and is equivalent to an Orderbook:
```ruby
rtb = Orderbook::RealTimeBook.new
```

* List current bids
```ruby
ob.bids # Returns an array of bids.
```

* List current asks
```ruby
ob.asks # Returns an array of asks.
```


## Contributing

1. Fork it ( https://github.com/mikerodrigues/orderbook/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
