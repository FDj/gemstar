module Gemstar
  class LockFile
    def initialize(path: nil, content: nil)
      @path = path
      parsed = content ? parse_content(content) : parse_lockfile(path)
      @specs = parsed[:specs]
      @dependency_graph = parsed[:dependency_graph]
      @direct_dependencies = parsed[:direct_dependencies]
    end

    attr_reader :specs
    attr_reader :dependency_graph
    attr_reader :direct_dependencies

    def origins_for(gem_name)
      return [{ type: :direct, path: [gem_name] }] if direct_dependencies.include?(gem_name)

      direct_dependencies.filter_map do |root_dependency|
        path = shortest_path_from(root_dependency, gem_name)
        next if path.nil?

        { type: :transitive, path: path }
      end
    end

    private

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
      direct_dependencies = []
      current_section = nil
      current_spec = nil

      content.each_line do |line|
        stripped = line.strip

        if stripped.match?(/\A[A-Z][A-Z0-9 ]*\z/)
          current_section = nil
          current_spec = nil
        end

        if stripped == "GEM"
          current_section = :gem
          current_spec = nil
          next
        end

        if stripped == "DEPENDENCIES"
          current_section = :dependencies
          current_spec = nil
          next
        end

        if stripped.empty?
          current_spec = nil if current_section == :dependencies
          next
        end

        case current_section
        when :gem
          if line =~ /^\s{4}(\S+) \((.+)\)/
            name, version = Regexp.last_match(1), Regexp.last_match(2)
            specs[name] = version
            current_spec = name
          elsif current_spec && line =~ /^\s{6}([^\s(]+)/
            dependency_graph[current_spec] << Regexp.last_match(1)
          end
        when :dependencies
          if line =~ /^\s{2}([^\s!(]+)/
            direct_dependencies << Regexp.last_match(1)
          end
        end
      end

      {
        specs: specs,
        dependency_graph: dependency_graph.transform_values(&:uniq),
        direct_dependencies: direct_dependencies.uniq
      }
    end
  end
end
