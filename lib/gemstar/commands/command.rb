module Gemstar
  module Commands
    class Command
      def initialize(options)
        @options = options
      end

      def run
        pp @options
      end

      def debug?
        @options[:debug]
      end
    end
  end
end
