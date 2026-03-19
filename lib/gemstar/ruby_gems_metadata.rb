require "open-uri"
require "uri"
require "json"

module Gemstar
  class RubyGemsMetadata
    def initialize(gem_name)
      @gem_name = gem_name
    end

    attr_reader :gem_name

    def meta(cache_only: false)
      return @meta if !cache_only && defined?(@meta)

      json = if cache_only
        Cache.peek("rubygems-#{gem_name}")
      else
        url = "https://rubygems.org/api/v1/gems/#{URI.encode_www_form_component(gem_name)}.json"
        Cache.fetch("rubygems-#{gem_name}") do
          URI.open(url).read
        end
      end

      parsed = begin
        JSON.parse(json) if json
      rescue
        nil
      end

      @meta = parsed unless cache_only
      parsed
    end

    def repo_uri(cache_only: false)
      resolved_meta = meta(cache_only: cache_only)
      return nil unless resolved_meta

      return @repo_uri if !cache_only && defined?(@repo_uri)

      repo = begin
               uri = resolved_meta["source_code_uri"]

               if uri.nil?
                 uri = resolved_meta["homepage_uri"]
                 if uri.include?("github.com")
                   uri = uri[%r{http[s?]://github\.com/[^/]+/[^/]+}]
                 end
               end

               uri ||= ""

               uri = uri.sub("http://", "https://")

               uri = uri.gsub(/\.git$/, "")

               if uri.include?("github.io")
                 uri = uri.sub(%r{\Ahttps?://([\w-]+)\.github\.io/([^/]+)}) do
                   "https://github.com/#{$1}/#{$2}"
                 end
               end

               uri
             end

      @repo_uri = repo unless cache_only
      repo
    end

  end
end
