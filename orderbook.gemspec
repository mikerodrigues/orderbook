# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'orderbook/version'

Gem::Specification.new do |spec|
  spec.name          = 'orderbook'
  spec.version       = Orderbook::VERSION
  spec.authors       = ['Michael Rodrigues']
  spec.email         = ['mikebrodrigues@gmail.com']
  spec.summary       = 'Maintains a real-time Coinbase Advanced Trade Level 2 order book.'
  spec.description   = 'Consumes the public Coinbase Advanced Trade WebSocket feed and maintains a precise, reconnecting Level 2 order book.'
  spec.homepage      = 'https://github.com/mikerodrigues/orderbook'
  spec.license       = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 4.0', '< 5')

  spec.files         = Dir['LICENSE.txt', 'README.md', 'lib/**/*.rb']
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['source_code_uri'] = spec.homepage

  spec.add_dependency 'bigdecimal', '>= 4.0', '< 5'
  spec.add_dependency 'json', '>= 2.18', '< 4'
  spec.add_dependency 'websocket', '~> 1.2'
  spec.add_development_dependency 'bundler', '>= 2.7', '< 5'
  spec.add_development_dependency 'minitest', '>= 6.0', '< 7'
  spec.add_development_dependency 'rake', '~> 13.3'
end
