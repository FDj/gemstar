require "json"

module Gemstar
  class ImportmapFile
    Pin = Struct.new(:name, :target, :source, keyword_init: true)

    IMPORTMAP_PACKAGE_METADATA_PATH = File.expand_path("data/importmap_package_metadata.json", __dir__)

    def self.package_metadata
      @package_metadata ||= begin
        JSON.parse(File.read(IMPORTMAP_PACKAGE_METADATA_PATH)).transform_values do |attributes|
          attributes.each_with_object({}) do |(key, value), metadata|
            metadata[key.to_sym] = value
          end
        end
      rescue Errno::ENOENT, JSON::ParserError
        {}
      end
    end

    def initialize(path: nil, content: nil, vendor_reader: nil)
      @path = path
      @vendor_reader = vendor_reader
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
      unless inline_version.to_s.empty?
        key = exact_package_version?(inline_version) ? :package_version : :package_requirement
        metadata[key] = inline_version
      end
      metadata
    end

    def vendored_package_metadata_for(target)
      return {} unless local_javascript_target?(target)

      first_line = vendored_file_first_line(target)
      return {} if first_line.empty?

      if first_line =~ %r{\A//\s+((?:@[^/]+/)?[^@\s]+(?:/[^@\s]+)?)@([^\s]+)\s+downloaded from\s+(https?://\S+)}
        package_name = Regexp.last_match(1)
        package_version = Regexp.last_match(2)
        remote = Regexp.last_match(3)
        remote_metadata = cdn_package_metadata_for(remote)
        package_name = remote_metadata[:package_name] || package_name
        package_version = remote_metadata[:package_version] || package_version
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

    def vendored_file_first_line(target)
      if @vendor_reader
        content = @vendor_reader.call(target.to_s)
        return content.to_s.lines.first.to_s if content
      end

      return "" unless @path

      vendor_path = File.expand_path(File.join(File.dirname(@path), "..", "vendor", "javascript", target.to_s))
      return "" unless File.file?(vendor_path)

      File.open(vendor_path, &:readline).to_s
    rescue EOFError
      ""
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

      version_metadata = exact_package_version?(package_version) ? { package_version: package_version } : { package_requirement: package_version }

      version_metadata.merge(
        package_name: package_name,
        registry_url: "https://www.npmjs.com/package/#{package_name}"
      )
    end

    def repo_source_for(name, target)
      package_metadata = self.class.package_metadata[name]
      repo_url = github_repo_url_for(target) || package_metadata&.dig(:repo_url)
      metadata = {}
      metadata[:repo_url] = repo_url if repo_url
      metadata[:provider_gem] = package_metadata[:provider_gem] if package_metadata&.dig(:provider_gem)
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

    def exact_package_version?(version)
      version.to_s.match?(/\Av?\d+(?:\.\d+)*(?:[-.][A-Za-z0-9]+)*\z/)
    end

    def local_javascript_target?(target)
      value = target.to_s
      return false if value.empty?
      return false if value.match?(%r{\A[a-z]+://}i)

      value.end_with?(".js", ".mjs")
    end
  end
end
