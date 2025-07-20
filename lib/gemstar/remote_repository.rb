# frozen_string_literal: true

module Gemstar
  class RemoteRepository

    def find_main_branch(base)
      # Attempt loading .gitignore (assumed to be present in all repos) from either
      # main or master branch:
      %w[main master].each do |branch|
        cache_fetch("gitignore-#{branch}") do
          content = URI.open("#{base}/#{branch}/.gitignore", read_timeout: 8)&.read rescue nil
          return [branch] unless content.nil?
        end
      end

      # No .gitignore found, have to search for changelogs in both branches:
      %w[main master]
    end


  end
end
