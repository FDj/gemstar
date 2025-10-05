module Gemstar
  class LockFile
    def initialize(path: nil, content: nil)
      @path = path
      @specs = content ? parse_content(content) : parse_lockfile(path)
    end

    attr_reader :specs

    private

    def parse_lockfile(path)
      parse_content(File.read(path))
    end

    def parse_content(content)
      specs = {}
      in_specs = false
      content.each_line do |line|
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
