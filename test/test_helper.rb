# frozen_string_literal: true

begin
  require "debug" unless ENV["CI"]
rescue LoadError
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
ENV["RAILS_ENV"] = "test"

require "combustion"
require "gemstar"

begin
  # See https://github.com/pat/combustion
  Combustion.initialize! do
    config.logger = Logger.new(nil)
    config.log_level = :fatal
  end
rescue => e
  # Fail fast if application couldn't be loaded
  $stdout.puts "Failed to load the app: #{e.message}\n#{e.backtrace.take(5).join("\n")}"
  exit(1)
end

Dir["#{__dir__}/support/**/*.rb"].sort.each { |f| require f }

require "minitest/autorun"

