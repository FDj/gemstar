module Gemstar
  module Commands
    class Command
      def initialize(options)
        @options = options
      end

      def run
        pp @options
      end
    end
  end
end
