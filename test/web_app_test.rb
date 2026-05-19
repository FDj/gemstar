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

  def test_changelog_content_strips_version_heading_with_trailing_hashes
    app = Gemstar::Web::App.allocate

    content = app.send(
      :changelog_content,
      ["Version 4.0.2 ############\n\nMerged changes in 3.2.4 and 3.3.3."],
      heading_version: "4.0.2"
    )

    refute_includes content[:html], "############"
    refute_includes content[:html], "Version 4.0.2"
    assert_includes content[:html], "Merged changes in 3.2.4 and 3.3.3."
    assert_equal "4.0.2", content[:title]
  end

  def test_detail_refresh_requested_accepts_truthy_flag
    app = Gemstar::Web::App.allocate

    assert app.send(:detail_refresh_requested?, { "refresh" => "1" })
    assert app.send(:detail_refresh_requested?, { "refresh" => "true" })
    refute app.send(:detail_refresh_requested?, {})
  end

  def test_detail_use_github_cli_requested_accepts_truthy_flag
    app = Gemstar::Web::App.allocate

    assert app.send(:detail_use_github_cli_requested?, { "use_gh" => "1" })
    assert app.send(:detail_use_github_cli_requested?, { "use_gh" => "yes" })
    refute app.send(:detail_use_github_cli_requested?, {})
  end

  def test_github_cli_release_button_only_renders_for_github_repo
    app = Gemstar::Web::App.allocate

    assert_includes app.send(:render_github_cli_release_button, "1.2.3", "https://github.com/basecamp/lexxy"), "Use GitHub CLI"
    assert_empty app.send(:render_github_cli_release_button, "1.2.3", "https://example.com/basecamp/lexxy")
  end
end
