module Gemstar
  class LockFile
    def initialize(path: nil, content: nil)
      @path = path
      parsed = content ? parse_content(content) : parse_lockfile(path)
      @specs = parsed[:specs]
      @dependency_graph = parsed[:dependency_graph]
      @dependency_requirements = parsed[:dependency_requirements]
      @direct_dependencies = parsed[:direct_dependencies]
      @direct_dependency_requirements = parsed[:direct_dependency_requirements]
      @spec_sources = parsed[:spec_sources]
    end

    attr_reader :specs
    attr_reader :dependency_graph
    attr_reader :dependency_requirements
    attr_reader :direct_dependencies
    attr_reader :direct_dependency_requirements
    attr_reader :spec_sources

    def origins_for(gem_name)
      if direct_dependencies.include?(gem_name)
        return [{
          type: :direct,
          path: [gem_name],
          requirement: direct_dependency_requirements[gem_name]
        }]
      end

      direct_dependencies.filter_map do |root_dependency|
        path = shortest_path_from(root_dependency, gem_name)
        next if path.nil?

        parent_name = path[-2]
        {
          type: :transitive,
          path: path,
          requirement: dependency_requirements.dig(parent_name, gem_name)
        }
      end
    end

    def source_for(gem_name)
      spec_sources[gem_name]
    end

    def platform_for(gem_name)
      version = specs[gem_name].to_s
      parts = version.split("-")
      return nil if parts.length < 2

      1.upto(parts.length - 1) do |index|
        candidate_version = parts[0...index].join("-")
        candidate_platform = parts[index..].join("-")
        next unless plausible_platform_suffix?(candidate_platform)

        begin
          Gem::Version.new(candidate_version)
          return candidate_platform
        rescue ArgumentError
          next
        end
      end

      nil
    end

    private

    def plausible_platform_suffix?(suffix)
      suffix.match?(/darwin|linux|mingw|mswin|musl|java|x86|arm|universal/i)
    end

    def shortest_path_from(root_dependency, target_gem)
      queue = [[root_dependency, [root_dependency]]]
      visited = {}

      until queue.empty?
        current_name, path = queue.shift
        next if visited[current_name]

        visited[current_name] = true

        Array(dependency_graph[current_name]).each do |dependency_name|
          next_path = path + [dependency_name]
          return next_path if dependency_name == target_gem

          queue << [dependency_name, next_path]
        end
      end

      nil
    end

    def parse_lockfile(path)
      parse_content(File.read(path))
    end

    def parse_content(content)
      specs = {}
      dependency_graph = Hash.new { |hash, key| hash[key] = [] }
      dependency_requirements = Hash.new { |hash, key| hash[key] = {} }
      direct_dependencies = []
      direct_dependency_requirements = {}
      spec_sources = {}
      current_section = nil
      current_spec = nil
      current_source = nil

      content.each_line do |line|
        stripped = line.strip

        if stripped.match?(/\A[A-Z][A-Z0-9 ]*\z/)
          current_section = nil
          current_spec = nil
        end

        if stripped == "GEM"
          current_section = :gem
          current_spec = nil
          current_source = { type: :rubygems }
          next
        end

        if stripped == "PATH"
          current_section = :path
          current_spec = nil
          current_source = { type: :path }
          next
        end

        if stripped == "GIT"
          current_section = :git
          current_spec = nil
          current_source = { type: :git }
          next
        end

        if stripped == "DEPENDENCIES"
          current_section = :dependencies
          current_spec = nil
          current_source = nil
          next
        end

        if stripped.empty?
          current_spec = nil if current_section == :dependencies
          next
        end

        case current_section
        when :gem, :path, :git
          if line =~ /^\s{2}remote:\s+(.+)$/
            current_source = (current_source || {}).merge(remote: Regexp.last_match(1))
          elsif line =~ /^\s{2}(revision|branch|tag|ref|glob|submodules):\s+(.+)$/
            current_source = (current_source || {}).merge(Regexp.last_match(1).to_sym => Regexp.last_match(2))
          elsif line =~ /^\s{2}path:\s+(.+)$/
            current_source = (current_source || {}).merge(path: Regexp.last_match(1))
          elsif line =~ /^\s{4}(\S+) \((.+)\)/
            name, version = Regexp.last_match(1), Regexp.last_match(2)
            specs[name] = version
            spec_sources[name] = (current_source || {}).dup
            current_spec = name
          elsif current_spec && line =~ /^\s{6}([^\s(]+)(?: \(([^)]+)\))?/
            dependency_name = Regexp.last_match(1)
            requirement = Regexp.last_match(2)
            dependency_graph[current_spec] << dependency_name
            dependency_requirements[current_spec][dependency_name] = requirement if requirement && !requirement.empty?
          end
        when :dependencies
          if line =~ /^\s{2}([^\s!(]+)(?: \(([^)]+)\))?/
            dependency_name = Regexp.last_match(1)
            requirement = Regexp.last_match(2)
            direct_dependencies << dependency_name
            direct_dependency_requirements[dependency_name] = requirement if requirement && !requirement.empty?
          end
        end
      end

      {
        specs: specs,
        dependency_graph: dependency_graph.transform_values(&:uniq),
        dependency_requirements: dependency_requirements,
        direct_dependencies: direct_dependencies.uniq,
        direct_dependency_requirements: direct_dependency_requirements,
        spec_sources: spec_sources
      }
    end
  end
end
