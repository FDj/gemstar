# frozen_string_literal: true

require "minitest/autorun"
require "stringio"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "gemstar/cache_warmer"

class CacheWarmerTest < Minitest::Test
  def test_warm_cache_for_package_fetches_detail_contexts_without_metadata_adapter
    calls = []
    warmer = Gemstar::CacheWarmer.new(
      io: StringIO.new,
      detail_cache_fetcher: ->(package_state, context) { calls << [package_state, context] }
    )
    package_state = {
      name: "local-package",
      package_scope: "js",
      source: { package_name: "" },
      detail_cache_contexts: [
        { project: 0, from: "abc123", to: "worktree", filter: "updated", scope: "all" },
        { project: 0, from: "abc123", to: "worktree", filter: "all", scope: "js" }
      ]
    }

    warmer.send(:warm_cache_for_package, package_state)

    assert_equal 2, calls.length
    assert_equal package_state, calls.first.first
    assert_equal "updated", calls.first.last[:filter]
    assert_equal "js", calls.last.last[:scope]
  end
end
