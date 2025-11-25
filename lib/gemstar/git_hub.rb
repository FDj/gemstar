# frozen_string_literal: true

module Gemstar
  class GitHub
    def self.github_blob_to_raw(url, ref_is_tag: false)
      return nil unless url

      uri = URI(url)
      return url unless uri.host == "github.com"

      owner, repo, blob, *rest = uri.path.split("/")[1..]
      return url unless blob == "blob"

      ref  = rest.shift
      path = rest.join("/")

      ref_prefix = ref_is_tag ? "refs/tags/" : ""

      uri.scheme = "https"
      uri.host   = "raw.githubusercontent.com"
      uri.path   = "/#{owner}/#{repo}/#{ref_prefix}#{ref}/#{path}"
      uri.to_s
    end

  end
end
