require_relative "command"

module Gemstar
  module Commands
    class Cache < Command
      def flush
        removed_entries = Gemstar::Cache.flush!
        puts "Flushed #{removed_entries} cache entr#{removed_entries == 1 ? 'y' : 'ies'} from #{Gemstar::Cache::CACHE_DIR}"
      end
    end
  end
end
