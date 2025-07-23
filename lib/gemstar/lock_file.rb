module Gemstar
  class LockFile
    def initialize(path)
      @path = path
      @specs = parse_lockfile(path)
    end

    attr_reader :specs

    private

    def parse_lockfile(path)
      specs = {}
      in_specs = false
      File.foreach(path) do |line|
        in_specs = true if line.strip == "GEM"
        next unless in_specs
        if line =~ /^\s{4}(\S+) \((.+)\)/
          name, version = $1, $2
          specs[name] = version
        end
      end
      specs
    end

  end
end
