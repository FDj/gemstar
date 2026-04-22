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
          source: build_source_for(target)
        )
      end
    end

    def build_source_for(target)
      {
        type: :importmap,
        remote: target
      }.merge(cdn_package_metadata_for(target)).merge(repo_source_for(target))
    end

    def cdn_package_metadata_for(target)
      value = target.to_s
      return {} if value.empty?

      package_name, package_version =
        case value
        when %r{\Ahttps://esm\.sh/((?:@[^/]+/)?[^@/?]+)@([^/?]+)}
          [Regexp.last_match(1), Regexp.last_match(2)]
        when %r{\Ahttps://ga\.jspm\.io/npm:((?:@[^/]+/)?[^@/]+)@([^/]+)/}
          [Regexp.last_match(1), Regexp.last_match(2)]
        when %r{\Ahttps://cdn\.jsdelivr\.net/npm/((?:@[^/]+/)?[^@/]+)@([^/]+)/}
          [Regexp.last_match(1), Regexp.last_match(2)]
        when %r{\Ahttps://unpkg\.com/((?:@[^/]+/)?[^@/?]+)@([^/?]+)}
          [Regexp.last_match(1), Regexp.last_match(2)]
        else
          [nil, nil]
        end

      return {} unless package_name

      {
        package_name: package_name,
        package_version: package_version,
        registry_url: "https://www.npmjs.com/package/#{package_name}"
      }
    end

    def repo_source_for(target)
      repo_url = github_repo_url_for(target)
      repo_url ? { repo_url: repo_url } : {}
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
