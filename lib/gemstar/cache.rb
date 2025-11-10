require "fileutils"
require "digest"

module Gemstar
  class Cache
    MAX_CACHE_AGE = 60 * 60 * 24 * 7 # 1 week
    CACHE_DIR = ".gem_changelog_cache"

    @@initialized = false

    def self.init
      return if @@initialized

      FileUtils.mkdir_p(CACHE_DIR)
      @@initialized = true
    end

    def self.fetch(key, &block)
      init

      path = File.join(CACHE_DIR, Digest::SHA256.hexdigest(key))

      if File.exist?(path)
        age = Time.now - File.mtime(path)
        if age <= MAX_CACHE_AGE
          content = File.read(path)
          return nil if content == "__404__"
          return content
        end
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

  end

  def edit_gitignore
    gitignore_path = ".gitignore"
    ignore_entries = %w[.gem_changelog_cache/ gem_update_changelog.html]

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
