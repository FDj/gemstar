module Gemstar
  class UvLockFile
    attr_reader :specs
    attr_reader :spec_sources

    def initialize(path: nil, content: nil)
      parsed = parse_content(content || File.read(path))
      @specs = parsed[:specs]
      @spec_sources = parsed[:spec_sources]
    end

    def source_for(name)
      spec_sources[name]
    end

    private

    def parse_content(content)
      specs = {}
      spec_sources = {}

      package_blocks(content).each do |block|
        name = scalar_value(block, "name")
        version = scalar_value(block, "version")
        source = source_for_block(block, name, version)
        next if name.to_s.empty? || version.to_s.empty?
        next if source[:type] == :virtual

        specs[name] = version
        spec_sources[name] = source
      end

      {
        specs: specs,
        spec_sources: spec_sources
      }
    end

    def package_blocks(content)
      content.to_s.split(/^\[\[package\]\]\s*$/).drop(1)
    end

    def scalar_value(block, key)
      block[/^#{Regexp.escape(key)}\s*=\s*"([^"]*)"/, 1]
    end

    def source_for_block(block, name, version)
      source = inline_table(block[/^source\s*=\s*\{([^}]*)\}/, 1])
      package_url = "https://pypi.org/project/#{name}/"
      registry_url = source["registry"]

      if source.key?("virtual")
        return {
          type: :virtual,
          path: source["virtual"]
        }.compact
      end

      if source.key?("git")
        return {
          type: :git,
          remote: source["git"],
          revision: source["rev"] || source["commit"],
          branch: source["branch"],
          tag: source["tag"],
          package_name: name,
          package_version: version,
          registry_url: package_url
        }.compact
      end

      if source.key?("path") || source.key?("editable") || source.key?("directory")
        return {
          type: :path,
          path: source["path"] || source["editable"] || source["directory"],
          package_name: name,
          package_version: version,
          registry_url: package_url
        }.compact
      end

      {
        type: :pypi,
        remote: registry_url,
        distribution_url: distribution_url(block),
        package_name: name,
        package_version: version,
        registry_url: package_url
      }.compact
    end

    def distribution_url(block)
      sdist = inline_table(block[/^sdist\s*=\s*\{([^}]*)\}/, 1])
      return sdist["url"] unless sdist["url"].to_s.empty?

      wheel = inline_table(block[/^\s*\{\s*url\s*=\s*"([^"]+)"/, 0])
      wheel["url"]
    end

    def inline_table(content)
      content.to_s.scan(/([\w-]+)\s*=\s*("[^"]*"|true|false|[^,\s}]+)/).each_with_object({}) do |(key, raw_value), values|
        values[key] = parse_inline_value(raw_value)
      end
    end

    def parse_inline_value(raw_value)
      value = raw_value.to_s.strip
      return true if value == "true"
      return false if value == "false"

      value.sub(/\A"/, "").sub(/"\z/, "")
    end
  end
end
