module Gemstar
  module Utils
    def generate_version_range(from_str, to_str)
      from = Gem::Version.new(from_str.gsub(/-[\w\-]+$/, ''))
      to = Gem::Version.new(to_str.gsub(/-[\w\-]+$/, ''))
      result = Set.new

      # Generate known version steps up to 2000 iterations max (safety limit)
      queue = [from]
      2000.times do
        v = queue.pop
        break if v.nil? || v >= to

        patch = Gem::Version.new("#{v.segments[0]}.#{v.segments[1]}.#{v.segments[2] + 1}")
        minor = Gem::Version.new("#{v.segments[0]}.#{v.segments[1] + 1}.0")
        major = Gem::Version.new("#{v.segments[0] + 1}.0.0")

        [patch, minor, major].each do |next_v|
          next if next_v > to || result.include?(next_v)
          result << next_v
          queue << next_v
        end
      end

      result.select { |v| v > from && v <= to }.sort.map(&:to_s)
    end
  end
end
