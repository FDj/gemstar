require_relative "config"
require "fileutils"
require "digest"

module Gemstar
  class Cache
    MAX_CACHE_AGE = 60 * 60 * 24 # 1 day
    CACHE_DIR = File.join(Gemstar::Config.home_directory, "cache")

    @@initialized = false

    def self.init
      return if @@initialized

      FileUtils.mkdir_p(CACHE_DIR)
      @@initialized = true
    end

    def self.fetch(key, &block)
      init

      path = path_for(key)

      if fresh?(path)
        content = File.read(path)
        return nil if content == "__404__"
        return content
      end

      begin
        data = block.call
        File.write(path, data || "__404__")
        data
      rescue
        File.write(path, "__404__")
        nil
      end
    end

    def self.peek(key)
      init

      path = path_for(key)
      return nil unless fresh?(path)

      content = File.read(path)
      return nil if content == "__404__"

      content
    end

    def self.path_for(key)
      File.join(CACHE_DIR, Digest::SHA256.hexdigest(key))
    end

    def self.fresh?(path)
      return false unless File.exist?(path)

      (Time.now - File.mtime(path)) <= MAX_CACHE_AGE
    end

    def self.flush!
      init

      flush_directory(CACHE_DIR)
    end

    def self.flush_directory(directory)
      return 0 unless Dir.exist?(directory)

      entries = Dir.children(directory)
      entries.each do |entry|
        FileUtils.rm_rf(File.join(directory, entry))
      end

      entries.count
    end

  end

  def edit_gitignore
    gitignore_path = ".gitignore"
    ignore_entries = %w[gem_update_changelog.html]

    existing_lines = File.exist?(gitignore_path) ? File.read(gitignore_path).lines.map(&:chomp) : []

    new_lines = ignore_entries.reject { |entry| existing_lines.include?(entry) }

    unless new_lines.empty?
      File.open(gitignore_path, "a") do |f|
        f.puts "\n# Cache/output from gem changelog tool" if (existing_lines & ignore_entries).empty?
        new_lines.each { |entry| f.puts entry }
      end
    end
  end

end
