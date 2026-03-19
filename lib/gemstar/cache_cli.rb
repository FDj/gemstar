require "thor"

module Gemstar
  class CacheCLI < Thor
    package_name "gemstar cache"

    desc "flush", "Clear all gemstar cache entries"
    def flush
      Gemstar::Commands::Cache.new({}).flush
    end
  end
end
