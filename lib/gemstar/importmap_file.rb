module Gemstar
  class ImportmapFile
    Pin = Struct.new(:name, :target, :source, keyword_init: true)

    def initialize(path: nil, content: nil)
      @path = path
      @pins = parse_content(content || File.read(path))
    end

    attr_reader :pins

    def specs
      pins.transform_values(&:target)
    end

    def source_for(name)
      pins[name]&.source
    end

    private

    def parse_content(content)
      content.each_line.with_object({}) do |line, pins|
        next unless line =~ /^\s*pin\s+["']([^"']+)["'](.*)$/

        name = Regexp.last_match(1)
        rest = Regexp.last_match(2).to_s
        target = rest[/\bto:\s*["']([^"']+)["']/, 1] || name

        pins[name] = Pin.new(
          name: name,
          target: target,
          source: {
            type: :importmap,
            remote: target,
            repo_url: github_repo_url_for(target)
          }
        )
      end
    end

    def github_repo_url_for(target)
      value = target.to_s
      return nil if value.empty?

      case value
      when %r{\Ahttps://raw\.githubusercontent\.com/([^/]+/[^/]+)/}
        "https://github.com/#{Regexp.last_match(1)}"
      when %r{\Ahttps://github\.com/([^/]+/[^/]+)}
        "https://github.com/#{Regexp.last_match(1)}"
      else
        nil
      end
    end
  end
end
