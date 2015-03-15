# Orderbook

A gem for creating a realtime order book for the Coinbase Exchange.

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

* To create a RealTimeBook:
```
rtb = Orderbook::RealTimeBook.new

rtb.bids # Returns an array of bids.

rtb.asks # Returns an array of asks.

# Setup a callback that runs after the message is applied to the book. Each
message received on the WebSocket is passed to this block. Running this method
again will redefine the callback.

rtb.set_callback do |msg|
  puts msg.fetch('type')
end
```

## Contributing

1. Fork it ( https://github.com/[my-github-username]/orderbook/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
