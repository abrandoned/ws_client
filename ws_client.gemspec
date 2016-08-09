# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ws_client/version'

Gem::Specification.new do |spec|
  spec.name          = "ws_client"
  spec.version       = WsClient::VERSION
  spec.authors       = ["Brandon Dewitt", "Sho Hashimoto"]
  spec.email         = ["brandonsdewitt+rubygems@gmail.com"]

  spec.summary       = %q{ A Simple websocket client in ruby ... largely from websocket-client-simple
                           with changes merged to use send_data over send and includes send_data_and_wait }
  spec.description   = %q{ Simple websocket client in ruby }
  spec.homepage      = "https://github.com/abrandoned/ws_client"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.12"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "pry"

  spec.add_dependency "websocket"
  spec.add_dependency "event_emitter"
end
