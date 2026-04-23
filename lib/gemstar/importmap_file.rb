module Gemstar
  class ImportmapFile
    Pin = Struct.new(:name, :target, :source, keyword_init: true)

    PROVIDER_GEM_MAPPINGS = {
      "@hotwired/stimulus-loading" => {
        provider_gem: "stimulus-rails",
        repo_url: "https://github.com/hotwired/stimulus-rails"
      },
      "@hotwired/turbo-rails" => {
        provider_gem: "turbo-rails",
        repo_url: "https://github.com/hotwired/turbo-rails"
      }
    }.freeze

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
        inline_version = rest[/#\s*@([^\s]+)/, 1]

        pins[name] = Pin.new(
          name: name,
          target: target,
          source: build_source_for(name, target, inline_version: inline_version)
        )
      end
    end

    def build_source_for(name, target, inline_version: nil)
      {
        type: :importmap,
        remote: target
      }
        .merge(default_package_metadata_for(name, inline_version: inline_version))
        .merge(vendored_package_metadata_for(target))
        .merge(cdn_package_metadata_for(target))
        .merge(repo_source_for(name, target))
    end

    def default_package_metadata_for(name, inline_version: nil)
      return {} unless package_like_pin_name?(name)

      metadata = { package_name: name, registry_url: "https://www.npmjs.com/package/#{name}" }
      metadata[:package_version] = inline_version unless inline_version.to_s.empty?
      metadata
    end

    def vendored_package_metadata_for(target)
      return {} unless @path
      return {} unless local_javascript_target?(target)

      vendor_path = File.expand_path(File.join(File.dirname(@path), "..", "vendor", "javascript", target.to_s))
      return {} unless File.file?(vendor_path)

      first_line = File.open(vendor_path, &:readline).to_s
      return {} if first_line.empty?

      if first_line =~ %r{\A//\s+((?:@[^/]+/)?[^@\s]+(?:/[^@\s]+)?)@([^\s]+)\s+downloaded from\s+(https?://\S+)}
        package_name = Regexp.last_match(1)
        package_version = Regexp.last_match(2)
        remote = Regexp.last_match(3)
        {
          package_name: package_name,
          package_version: package_version,
          registry_url: "https://www.npmjs.com/package/#{package_name}",
          remote: remote
        }
      else
        {}
      end
    rescue EOFError
      {}
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

    def repo_source_for(name, target)
      provider = PROVIDER_GEM_MAPPINGS[name]
      repo_url = github_repo_url_for(target) || provider&.dig(:repo_url)
      metadata = {}
      metadata[:repo_url] = repo_url if repo_url
      metadata[:provider_gem] = provider[:provider_gem] if provider&.dig(:provider_gem)
      metadata
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

    def package_like_pin_name?(name)
      value = name.to_s
      return false if value.empty?
      return false if value.start_with?("controllers/")
      return false if value.include?("_controller")
      return false if value.start_with?("./", "../")

      value.start_with?("@") || value.match?(/\A[a-z0-9][a-z0-9._-]*(?:\/[a-z0-9][a-z0-9._-]*)*\z/i)
    end

    def local_javascript_target?(target)
      value = target.to_s
      return false if value.empty?
      return false if value.match?(%r{\A[a-z]+://}i)

      value.end_with?(".js", ".mjs")
    end
  end
end
