require 'rspec'
require 'webmock/rspec'
require 'json'
require 'tempfile'
require 'fileutils'

RSpec.configure do |config|
  config.before(:each) do
    WebMock.reset!
  end
end