# frozen_string_literal: true

require "uri"

module Gemstar
  class CargoLockFile
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
      packages = package_blocks(content).filter_map do |block|
        name = scalar_value(block, "name")
        version = scalar_value(block, "version")
        source = scalar_value(block, "source")
        next if name.to_s.empty? || version.to_s.empty?
        next if source.to_s.empty?

        {
          name: name,
          version: version,
          source: source_for_package(source, name, version)
        }
      end

      specs = {}
      spec_sources = {}
      packages.group_by { |package| package[:name] }.each_value do |named_packages|
        sorted_packages(named_packages).each_with_index do |package, index|
          key = package_key(package, index, named_packages.length)
          specs[key] = package[:version]
          spec_sources[key] = package[:source]
        end
      end

      {specs: specs, spec_sources: spec_sources}
    end

    def package_blocks(content)
      content.to_s.split(/^\[\[package\]\]\s*$/).drop(1)
    end

    def scalar_value(block, key)
      block[/^#{Regexp.escape(key)}\s*=\s*"((?:\\.|[^"])*)"/, 1]&.gsub('\\"', '"')
    end

    def source_for_package(raw_source, name, version)
      if raw_source.start_with?("git+")
        git_source(raw_source, name, version)
      else
        registry_source(raw_source, name, version)
      end
    end

    def git_source(raw_source, name, version)
      remote_with_query, revision = raw_source.delete_prefix("git+").split("#", 2)
      remote, query = remote_with_query.split("?", 2)
      params = URI.decode_www_form(query.to_s).to_h

      {
        type: :git,
        remote: remote,
        revision: revision,
        branch: params["branch"],
        tag: params["tag"],
        package_name: name,
        package_version: version
      }.compact
    rescue ArgumentError
      {
        type: :git,
        remote: raw_source.delete_prefix("git+").split(/[?#]/, 2).first,
        revision: raw_source.split("#", 2)[1],
        package_name: name,
        package_version: version
      }.compact
    end

    def registry_source(raw_source, name, version)
      registry = raw_source.sub(/\A(?:registry|sparse)\+/, "")
      crates_io = crates_io_registry?(registry)

      {
        type: :cargo,
        remote: registry,
        package_name: name,
        package_version: version,
        registry_url: crates_io ? "https://crates.io/crates/#{name}" : registry,
        crates_io: crates_io
      }
    end

    def crates_io_registry?(registry)
      registry.include?("crates.io-index") || registry.include?("index.crates.io")
    end

    def sorted_packages(packages)
      packages.sort do |left, right|
        comparison = compare_versions(right[:version], left[:version])
        comparison.zero? ? left[:source].to_s <=> right[:source].to_s : comparison
      end
    end

    def compare_versions(left, right)
      Gem::Version.new(left) <=> Gem::Version.new(right)
    rescue ArgumentError
      left.to_s <=> right.to_s
    end

    def package_key(package, index, package_count)
      return package[:name] if package_count == 1

      key = "#{package[:name]}@#{package[:version]}"
      if index.zero? || !@used_package_keys&.include?(key)
        remember_package_key(key)
      else
        remember_package_key("#{key}:#{index + 1}")
      end
    end

    def remember_package_key(key)
      @used_package_keys ||= []
      @used_package_keys << key
      key
    end
  end
end
