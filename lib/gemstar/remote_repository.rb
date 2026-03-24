# frozen_string_literal: true

module Gemstar
  class RemoteRepository
    def initialize(repository_uri)
      @repository_uri = repository_uri
    end

    def find_main_branch(cache_only: false, force_refresh: false)
      # Attempt loading .gitignore (assumed to be present in all repos) from either
      # main or master branch:
      %w[main master].each do |branch|
        cache_key = "gitignore-#{@repository_uri}-#{branch}"

        if cache_only
          content = Cache.peek(cache_key)
          return [branch] unless content.nil?

          next
        end

        Cache.fetch(cache_key, force: force_refresh) do
          content = begin
                      URI.open("#{@repository_uri}/#{branch}/.gitignore", read_timeout: 8)&.read
                    rescue
                      nil
                    end
          return [branch] unless content.nil?
        end
      end

      # No .gitignore found, have to search for changelogs in both branches:
      %w[main master]
    end

  end
end
