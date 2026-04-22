require "json"

module Gemstar
  class PackageLockFile
    def initialize(path: nil, content: nil)
      @path = path
      parsed = parse_content(content || File.read(path))
      @specs = parsed[:specs]
      @spec_sources = parsed[:spec_sources]
    end

    attr_reader :specs
    attr_reader :spec_sources

    def source_for(name)
      spec_sources[name]
    end

    private

    def parse_content(content)
      parsed = JSON.parse(content)
      specs = {}
      spec_sources = {}

      if parsed["packages"].is_a?(Hash)
        parse_packages_map(parsed["packages"], specs, spec_sources)
      elsif parsed["dependencies"].is_a?(Hash)
        parse_dependencies_hash(parsed["dependencies"], specs, spec_sources)
      end

      {
        specs: specs,
        spec_sources: spec_sources
      }
    end

    def parse_packages_map(packages, specs, spec_sources)
      packages.each do |path, package|
        next if path.to_s.empty?

        name = package["name"] || package_name_from_path(path)
        version = package["version"]
        next if name.to_s.empty? || version.to_s.empty?

        specs[name] = version
        spec_sources[name] = {
          type: :npm,
          remote: package["resolved"],
          integrity: package["integrity"],
          registry_url: "https://www.npmjs.com/package/#{name}"
        }.compact
      end
    end

    def parse_dependencies_hash(dependencies, specs, spec_sources)
      dependencies.each do |name, package|
        version = package["version"]
        next if name.to_s.empty? || version.to_s.empty?

        specs[name] = version
        spec_sources[name] = {
          type: :npm,
          remote: package["resolved"],
          integrity: package["integrity"],
          registry_url: "https://www.npmjs.com/package/#{name}"
        }.compact

        child_dependencies = package["dependencies"]
        parse_dependencies_hash(child_dependencies, specs, spec_sources) if child_dependencies.is_a?(Hash)
      end
    end

    def package_name_from_path(path)
      value = path.to_s
      return nil if value.empty?

      segments = value.split("/").reject(&:empty?)
      package_segments = []
      index = 0
      while index < segments.length
        if segments[index] == "node_modules"
          index += 1
          next
        end

        if segments[index].start_with?("@") && segments[index + 1]
          package_segments = [segments[index], segments[index + 1]]
          index += 2
        else
          package_segments = [segments[index]]
          index += 1
        end
      end

      return nil if package_segments.empty?

      package_segments.join("/")
    end
  end
end
