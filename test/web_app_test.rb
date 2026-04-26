# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "gemstar/web/app"

class WebAppTest < Minitest::Test
  def test_changelog_content_strips_setext_separator_after_version_heading
    app = Gemstar::Web::App.allocate

    content = app.send(
      :changelog_content,
      ["3.246.0\n--------\n\n* Feature - Updated configuration values for `defaults_mode`."],
      heading_version: "3.246.0"
    )

    refute_includes content[:html], "<hr"
    assert_includes content[:html], "Updated configuration values"
    assert_equal "3.246.0", content[:title]
  end
end
