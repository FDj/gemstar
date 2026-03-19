require "cgi"
require "uri"
require "kramdown"
require "roda"

begin
  require "kramdown-parser-gfm"
rescue LoadError
end

module Gemstar
  module Web
    class App < Roda
      class << self
        def build(projects:, config_home:, cache_warmer: nil)
          Class.new(self) do
            opts[:projects] = projects
            opts[:config_home] = config_home
            opts[:cache_warmer] = cache_warmer
          end.freeze.app
        end
      end

      route do |r|
        @projects = self.class.opts.fetch(:projects)
        @config_home = self.class.opts.fetch(:config_home)
        @cache_warmer = self.class.opts[:cache_warmer]
        @metadata_cache = {}

        r.root do
          load_state(r.params)
          prioritize_selected_gem

          render_page(page_title) do
            render_shell
          end
        end

        r.get "detail" do
          load_state(r.params)
          prioritize_selected_gem
          render_detail
        end

        r.on "projects", String do |project_id|
          response.redirect "/?project=#{project_id}"
        end
      end

      private

      def page_title
        return "Gemstar" unless @selected_project

        "#{@selected_project.name}: Gemstar"
      end

      def load_state(params)
        @selected_project_index = selected_project_index(params["project"])
        @selected_project = @projects[@selected_project_index]
        @revision_options = @selected_project ? @selected_project.revision_options : []
        @selected_from_revision_id = selected_from_revision_id(params["from"])
        @selected_to_revision_id = selected_to_revision_id(params["to"])
        @gem_states = @selected_project ? @selected_project.gem_states(from_revision_id: @selected_from_revision_id, to_revision_id: @selected_to_revision_id) : []
        @selected_gem = selected_gem_state(params["gem"])
      end

      def prioritize_selected_gem
        @cache_warmer&.prioritize(@selected_gem[:name]) if @selected_gem
      end

      def selected_project_index(raw_index)
        return nil if @projects.empty?
        return 0 if raw_index.nil? || raw_index.empty?

        index = Integer(raw_index, 10)
        return 0 if index.negative? || @projects[index].nil?

        index
      rescue ArgumentError
        0
      end

      def selected_from_revision_id(raw_revision_id)
        return "worktree" unless @selected_project

        valid_ids = @revision_options.map { |option| option[:id] }
        default_id = @selected_project.default_from_revision_id
        candidate = raw_revision_id.nil? || raw_revision_id.empty? ? default_id : raw_revision_id

        valid_ids.include?(candidate) ? candidate : default_id
      end

      def selected_to_revision_id(raw_revision_id)
        return "worktree" unless @selected_project

        valid_ids = @revision_options.map { |option| option[:id] }
        candidate = raw_revision_id.nil? || raw_revision_id.empty? ? "worktree" : raw_revision_id

        valid_ids.include?(candidate) ? candidate : "worktree"
      end

      def selected_gem_state(raw_gem_name)
        return nil if @gem_states.empty?

        @gem_states.find { |gem| gem[:name] == raw_gem_name } ||
          @gem_states.find { |gem| gem[:status] != :unchanged } ||
          @gem_states.first
      end

      def render_shell
        return render_empty_workspace if @projects.empty?

        <<~HTML
          <div class="app-shell">
            #{render_topbar}
            #{render_workspace}
          </div>
          #{render_behavior_script}
        HTML
      end

      def render_empty_workspace
        <<~HTML
          <div class="app-shell">
            <header class="topbar">
              <div class="brand-lockup">
                <div class="brand-mark">G</div>
                <div>
                  <p class="brand-kicker">Gemstar</p>
                  <h1>Gemfile.lock explorer</h1>
                </div>
              </div>
            </header>
            <section class="empty-state">
              <h2>No projects loaded</h2>
              <p>Gemstar loads the current directory by default. Use <code>--project</code> to add other project paths.</p>
              <p>Config home: <code>#{h(@config_home)}</code></p>
            </section>
          </div>
        HTML
      end

      def render_topbar
        <<~HTML
          <header class="topbar">
            <div class="brand-lockup">
              <div class="brand-mark">G</div>
              <h1>Gemfile.lock explorer</h1>
            </div>
            <div class="picker-row">
              <label class="picker picker-project">
                <span class="picker-prefix">📁</span>
                <select data-project-select>
                  #{project_options_html}
                  <option value="" disabled>────────</option>
                  <option value="__add__">Add...</option>
                </select>
              </label>
              <label class="picker">
                <span class="picker-prefix">From:</span>
                <select data-from-select #{'disabled="disabled"' unless @selected_project}>
                  #{from_revision_options_html}
                </select>
              </label>
              <label class="picker">
                <span class="picker-prefix">To:</span>
                <select data-to-select #{'disabled="disabled"' unless @selected_project}>
                  #{to_revision_options_html}
                </select>
              </label>
            </div>
          </header>
        HTML
      end

      def project_options_html
        @projects.each_with_index.map do |project, index|
          selected = index == @selected_project_index ? ' selected="selected"' : ""
          <<~HTML
            <option value="#{index}"#{selected}>#{h(project.name)} · #{h(project.directory)}</option>
          HTML
        end.join
      end

      def from_revision_options_html
        return '<option value="worktree">Worktree</option>' unless @selected_project

        @revision_options.map do |option|
          selected = option[:id] == @selected_from_revision_id ? ' selected="selected"' : ""
          <<~HTML
            <option value="#{h(option[:id])}"#{selected}>#{h(option[:label])} · #{h(option[:description])}</option>
          HTML
        end.join
      end

      def to_revision_options_html
        return '<option value="worktree">Worktree</option>' unless @selected_project

        @revision_options.map do |option|
          selected = option[:id] == @selected_to_revision_id ? ' selected="selected"' : ""
          <<~HTML
            <option value="#{h(option[:id])}"#{selected}>#{h(option[:label])} · #{h(option[:description])}</option>
          HTML
        end.join
      end

      def render_workspace
        <<~HTML
          <main class="workspace">
            #{render_toolbar}
            <div class="workspace-body">
              #{render_sidebar}
              #{render_detail}
            </div>
          </main>
        HTML
      end

      def render_toolbar
        <<~HTML
          <section class="toolbar">
            <div class="toolbar-actions">
              <button type="button" class="action" disabled="disabled">bundle install</button>
              <button type="button" class="action action-primary" disabled="disabled">bundle update</button>
            </div>
            <div class="toolbar-meta">
              <strong>#{@gem_states.count}</strong> gems
              <span>·</span>
              <strong>#{@gem_states.count { |gem| gem[:status] != :unchanged }}</strong> changes from #{h(selected_from_revision_label)} to #{h(selected_to_revision_label)}
              <span>·</span>
              keyboard: arrows
            </div>
          </section>
        HTML
      end

      def selected_from_revision_label
        @revision_options.find { |option| option[:id] == @selected_from_revision_id }&.dig(:label) || "worktree"
      end

      def selected_to_revision_label
        @revision_options.find { |option| option[:id] == @selected_to_revision_id }&.dig(:label) || "worktree"
      end

      def render_sidebar
        <<~HTML
          <aside class="sidebar" data-sidebar-panel tabindex="0">
            <div class="sidebar-header">
              <h2>#{h(@selected_project.name)}</h2>
              <div class="list-filters" data-list-filters>
                <button type="button" class="list-filter-button is-active" data-filter-button="updated">Updated</button>
                <button type="button" class="list-filter-button" data-filter-button="all">All</button>
              </div>
            </div>
            #{render_gem_list}
            <button type="button" class="add-gem" disabled="disabled">Add gem</button>
          </aside>
        HTML
      end

      def render_gem_list
        return <<~HTML if @gem_states.empty?
          <section class="empty-panel">
            <p>No gems found in the current lockfile.</p>
          </section>
        HTML

        items = @gem_states.map do |gem|
          selected = gem[:name] == @selected_gem[:name] ? " is-selected" : ""
          updated = gem[:status] != :unchanged
          <<~HTML
            <a
              class="gem-row#{selected}"
              href="#{project_query(project: @selected_project_index, from: @selected_from_revision_id, to: @selected_to_revision_id, gem: gem[:name])}"
              data-gem-link="true"
              data-gem-name="#{h(gem[:name])}"
              data-gem-updated="#{updated}"
              data-detail-url="#{h(detail_query(project: @selected_project_index, from: @selected_from_revision_id, to: @selected_to_revision_id, gem: gem[:name]))}"
            >
              <span class="gem-name-row">
                <span class="gem-name">#{h(gem[:name])}</span>
                #{updated ? '<span class="gem-updated-dot" aria-label="Updated"></span>' : ""}
              </span>
              <span class="gem-version">#{h(gem[:version_label])}</span>
            </a>
          HTML
        end.join

        <<~HTML
          <nav class="gem-list">
            #{items}
          </nav>
        HTML
      end

      def render_detail
        return <<~HTML unless @selected_gem
          <section class="detail" data-detail-panel>
            <div class="empty-panel">
              <h2>No gem selected</h2>
              <p>Choose a gem from the list to inspect its current version and changelog revisions.</p>
            </div>
          </section>
        HTML

        metadata = metadata_for(@selected_gem[:name])
        detail_pending = detail_pending?(@selected_gem[:name], metadata)

        <<~HTML
          <section class="detail" data-detail-panel data-detail-pending="#{detail_pending}" data-detail-url="#{h(detail_query(project: @selected_project_index, from: @selected_from_revision_id, to: @selected_to_revision_id, gem: @selected_gem[:name]))}">
            #{render_detail_hero(metadata)}
            #{render_detail_links(metadata)}
            #{render_detail_loading_notice if detail_pending}
            #{render_detail_revision_panel}
          </section>
        HTML
      end

      def render_detail_hero(metadata)
        summary = if @selected_gem[:old_version] == @selected_gem[:new_version]
          @selected_gem[:new_version].to_s
        else
          @selected_gem[:version_label]
        end

        description = metadata&.dig("info")

        <<~HTML
          <section class="detail-hero">
            <div>
              <h2>#{h(@selected_gem[:name])}</h2>
              <p class="version-summary">#{h(summary)}</p>
            </div>
          </section>
          <section class="detail-copy">
            <p>#{description ? h(description) : "Metadata will appear here when RubyGems information is available."}</p>
          </section>
        HTML
      end

      def render_detail_links(metadata)
        repo_url = metadata ? Gemstar::RubyGemsMetadata.new(@selected_gem[:name]).repo_uri(cache_only: true) : nil
        homepage_url = metadata&.dig("homepage_uri")
        rubygems_url = "https://rubygems.org/gems/#{URI.encode_www_form_component(@selected_gem[:name])}"

        buttons = []
        buttons << external_button("RubyGems", rubygems_url)
        buttons << external_button("GitHub", repo_url) if repo_url && !repo_url.empty?
        buttons << external_button("Homepage", homepage_url) if homepage_url && !homepage_url.empty?

        <<~HTML
          <section class="link-strip">
            #{buttons.join}
          </section>
        HTML
      end

      def render_detail_revision_panel
        groups = grouped_change_sections(@selected_gem)

        <<~HTML
          <section class="revision-panel">
            <div class="panel-heading">
              <div>
                <h3>Revisions for #{@selected_gem[:name]}</h3>
              </div>
              <div class="panel-heading-meta">#{h(selected_from_revision_label)} -> #{h(selected_to_revision_label)}</div>
            </div>
            #{render_revision_group("Latest", groups[:latest], empty_message: "No newer changelog entries found yet.")}
            #{render_revision_group("New in this revision", groups[:current], empty_message: "No changelog entries matched this revision range.")}
            #{render_revision_group("Previous updates", groups[:previous], empty_message: "No older changelog entries found.")}
          </section>
        HTML
      end

      def render_detail_loading_notice
        <<~HTML
          <section class="empty-panel">
            <p>Loading gem metadata and changelog in the background...</p>
          </section>
        HTML
      end

      def render_revision_group(title, sections, empty_message:)
        cards = if sections.empty?
          <<~HTML
            <div class="empty-panel">
              <p>#{h(empty_message)}</p>
            </div>
          HTML
        else
          sections.map { |section| render_revision_card(section) }.join
        end

        <<~HTML
          <section class="revision-group">
            <header class="revision-group-header">
              <h4>#{h(title)}</h4>
            </header>
            #{cards}
          </section>
        HTML
      end

      def render_revision_card(section)
        <<~HTML
          <article class="revision-card revision-#{section[:kind]}">
            <header class="revision-card-header">
              <div>
                <h5>#{h(section[:version])}</h5>
              </div>
            </header>
            <div class="revision-markup">
              #{section[:html]}
            </div>
          </article>
        HTML
      end

      def grouped_change_sections(gem_state)
        sections = change_sections(gem_state)

        {
          latest: sections.select { |section| section[:kind] == :future },
          current: sections.select { |section| section[:kind] == :current },
          previous: sections.select { |section| section[:kind] == :previous }
        }
      end

      def change_sections(gem_state)
        return [] if gem_state[:new_version].nil? && gem_state[:old_version].nil?

        metadata = Gemstar::RubyGemsMetadata.new(gem_state[:name])
        sections = Gemstar::ChangeLog.new(metadata).sections(cache_only: true)
        return [] if sections.nil? || sections.empty?

        current_version = gem_state[:new_version] || gem_state[:old_version]
        previous_version = gem_state[:old_version]

        rendered_sections = sections.keys.filter_map do |version|
          kind = section_kind(version, previous_version, current_version, gem_state[:status])
          next unless kind

          {
            version: version,
            kind: kind,
            html: changelog_markup(sections[version])
          }
        end

        rendered_sections.sort_by { |section| section_sort_key(section) }
      rescue StandardError
        []
      end

      def section_kind(version, previous_version, current_version, status)
        return :future if compare_versions(version, current_version) == 1

        lower_bound = previous_version || current_version
        if compare_versions(version, lower_bound) == 1 && compare_versions(version, current_version) <= 0
          return :current
        end

        if [:downgrade, :removed].include?(status)
          upper_bound = previous_version || current_version
          lower_bound = current_version || "0.0.0"

          return :current if compare_versions(version, lower_bound) == 1 &&
            compare_versions(version, upper_bound) <= 0
        end

        return :current if previous_version.nil? && compare_versions(version, current_version) <= 0 && compare_versions(version, current_version) >= 0

        :previous if compare_versions(version, lower_bound) <= 0
      end

      def section_sort_key(section)
        kind_rank = { future: 0, current: 1, previous: 2 }.fetch(section[:kind], 9)
        [kind_rank, -sortable_version_number(section[:version])]
      end

      def sortable_version_number(version)
        Gem::Version.new(version.to_s.gsub(/-[\w\-]+$/, "")).segments.take(6).each_with_index.sum do |segment, index|
          segment.to_i * (10**(10 - index * 2))
        end
      rescue ArgumentError
        0
      end

      def changelog_markup(lines)
        text = Array(lines).flatten.join
        return "<p>No changelog text available.</p>" if text.strip.empty?

        options = { hard_wrap: false }
        options[:input] = "GFM" if defined?(Kramdown::Parser::GFM)
        html = Kramdown::Document.new(text, options).to_html
        with_external_links(html)
      rescue Kramdown::Error
        "<pre>#{h(text)}</pre>"
      end

      def compare_versions(left, right)
        Gem::Version.new(left.to_s.gsub(/-[\w\-]+$/, "")) <=> Gem::Version.new(right.to_s.gsub(/-[\w\-]+$/, ""))
      rescue ArgumentError
        left.to_s <=> right.to_s
      end

      def metadata_for(gem_name)
        @metadata_cache[gem_name] ||= Gemstar::RubyGemsMetadata.new(gem_name).meta(cache_only: true)
      rescue StandardError
        nil
      end

      def detail_pending?(gem_name, metadata)
        metadata.nil? && change_sections({ name: gem_name, old_version: @selected_gem[:old_version], new_version: @selected_gem[:new_version], status: @selected_gem[:status] }).empty?
      end

      def external_button(label, url)
        <<~HTML
          <a class="link-button" href="#{h(url)}" target="_blank" rel="noreferrer">#{h(label)}</a>
        HTML
      end

      def with_external_links(html)
        fragment = Nokogiri::HTML::DocumentFragment.parse(html)
        fragment.css("a[href]").each do |link|
          link["target"] = "_blank"
          link["rel"] = "noreferrer"
        end
        fragment.to_html
      rescue StandardError
        html
      end

      def detail_query(project:, from:, to:, gem:)
        "/detail?#{URI.encode_www_form(project: project, from: from, to: to, gem: gem)}"
      end

      def project_query(project:, from:, to:, gem:)
        params = {
          project: project,
          from: from,
          to: to,
          gem: gem
        }.compact

        "/?#{URI.encode_www_form(params)}"
      end

      def render_page(title)
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>#{h(title)}</title>
              <style>
                :root {
                  color-scheme: light;
                  --canvas: #f1ecdf;
                  --panel: #fff9ef;
                  --panel-strong: #f7efe0;
                  --ink: #1f1b17;
                  --muted: #6b6057;
                  --line: #ddcfbf;
                  --accent: #b44d25;
                  --accent-soft: rgba(180, 77, 37, 0.14);
                  --green: #2f8f5b;
                  --green-soft: rgba(47, 143, 91, 0.12);
                  --red: #a9473c;
                  --red-soft: rgba(169, 71, 60, 0.12);
                  --grey: #7c7c85;
                  --grey-soft: rgba(124, 124, 133, 0.1);
                  --shadow: 0 1.1rem 2.4rem rgba(66, 44, 28, 0.08);
                }

                * { box-sizing: border-box; }
                body {
                  margin: 0;
                  color: var(--ink);
                  font-family: "Iowan Old Style", "Palatino Linotype", serif;
                  background: #fff;
                }
                a {
                  color: inherit;
                  text-decoration: none;
                }
                button,
                select {
                  font: inherit;
                }
                code,
                pre {
                  font-family: "SFMono-Regular", "Cascadia Code", monospace;
                }
                .app-shell {
                  min-height: 100vh;
                  display: flex;
                  flex-direction: column;
                }
                .topbar {
                  display: flex;
                  align-items: center;
                  justify-content: space-between;
                  gap: 0.6rem;
                  padding: 0.4rem 0.65rem;
                  border-bottom: 1px solid #ece8df;
                  background: #fff;
                  position: sticky;
                  top: 0;
                  z-index: 2;
                  flex-wrap: nowrap;
                }
                .brand-lockup {
                  display: flex;
                  align-items: center;
                  gap: 0.65rem;
                  flex: 0 1 auto;
                  min-width: 0;
                }
                .brand-mark {
                  width: 1.55rem;
                  height: 1.55rem;
                  border-radius: 0.35rem;
                  display: grid;
                  place-items: center;
                  font-weight: 700;
                  font-size: 0.82rem;
                  color: white;
                  background: linear-gradient(145deg, #c05a2b, #8f3517);
                }
                .brand-kicker,
                .detail-kicker {
                  margin: 0;
                  color: var(--accent);
                  text-transform: uppercase;
                  letter-spacing: 0.1em;
                  font-size: 0.65rem;
                }
                .brand-lockup h1,
                .sidebar-header h2,
                .detail h2,
                .detail h3,
                .empty-state h2 {
                  margin: 0.05rem 0 0;
                  line-height: 1;
                }
                .brand-lockup h1 {
                  white-space: nowrap;
                  font-size: 0.96rem;
                }
                .picker-row {
                  display: flex;
                  gap: 0.45rem;
                  flex-wrap: nowrap;
                  align-items: center;
                  flex: 1 1 auto;
                  justify-content: flex-end;
                  min-width: 0;
                }
                .picker {
                  display: inline-flex;
                  align-items: center;
                  gap: 0.28rem;
                  color: var(--muted);
                  font-size: 0.78rem;
                  min-width: 0;
                }
                .picker-prefix {
                  white-space: nowrap;
                  color: var(--muted);
                }
                .picker select {
                  min-width: 10rem;
                  max-width: 17rem;
                  border: 1px solid var(--line);
                  border-radius: 0.35rem;
                  padding: 0.24rem 0.45rem;
                  background: #fff;
                  color: var(--ink);
                  box-shadow: none;
                  font-size: 0.8rem;
                }
                .workspace {
                  display: grid;
                  gap: 0.45rem;
                  padding: 0.45rem 0.55rem;
                }
                .toolbar,
                .sidebar,
                .detail,
                .empty-state {
                  background: #fff;
                  border: 1px solid #ece8df;
                  border-radius: 0.35rem;
                  box-shadow: none;
                }
                .toolbar {
                  display: flex;
                  justify-content: space-between;
                  gap: 0.45rem;
                  align-items: center;
                  padding: 0.35rem 0.5rem;
                  flex-wrap: wrap;
                }
                .toolbar-actions {
                  display: flex;
                  gap: 0.3rem;
                  flex-wrap: wrap;
                }
                .action,
                .add-gem,
                .link-button {
                  border: 1px solid var(--line);
                  border-radius: 0.3rem;
                  padding: 0.22rem 0.5rem;
                  background: #fff;
                  color: var(--ink);
                  font-size: 0.78rem;
                }
                .action-primary {
                  background: linear-gradient(145deg, #c55a28, #984119);
                  color: white;
                  border-color: rgba(152, 65, 25, 0.65);
                }
                .action[disabled],
                .add-gem[disabled] {
                  opacity: 0.55;
                  cursor: not-allowed;
                }
                .toolbar-meta {
                  color: var(--muted);
                  display: flex;
                  gap: 0.28rem;
                  flex-wrap: wrap;
                  align-items: center;
                  font-size: 0.76rem;
                }
                .workspace-body {
                  display: grid;
                  grid-template-columns: minmax(16rem, 22rem) minmax(0, 1fr);
                  gap: 0.45rem;
                  min-height: calc(100vh - 8rem);
                  height: calc(100vh - 8rem);
                }
                .sidebar {
                  padding: 0.45rem;
                  display: grid;
                  gap: 0.3rem;
                  align-content: start;
                  min-height: 0;
                  overflow: auto;
                }
                .sidebar-note,
                .version-summary,
                .detail-copy p {
                  margin: 0;
                  color: var(--muted);
                }
                .sidebar-header {
                  display: flex;
                  align-items: center;
                  justify-content: space-between;
                  gap: 0.5rem;
                }
                .list-filters {
                  display: flex;
                  gap: 0.28rem;
                  flex-wrap: wrap;
                }
                .list-filter-button {
                  border: 1px solid var(--line);
                  border-radius: 999px;
                  padding: 0.18rem 0.5rem;
                  background: #fff;
                  color: var(--muted);
                  font-size: 0.74rem;
                }
                .list-filter-button.is-active {
                  border-color: rgba(47, 143, 91, 0.4);
                  background: var(--green-soft);
                  color: var(--green);
                }
                .gem-list {
                  display: grid;
                  gap: 0;
                }
                .gem-row {
                  display: grid;
                  gap: 0.08rem;
                  padding: 0.38rem 0.2rem;
                  border-radius: 0;
                  border: 0;
                  border-bottom: 1px solid #f0ede6;
                  background: transparent;
                  transition: background 120ms ease, color 120ms ease;
                }
                .gem-row:hover,
                .gem-row.is-selected {
                  background: #faf8f3;
                }
                .gem-name {
                  font-weight: 700;
                  font-size: 0.9rem;
                }
                .gem-name-row {
                  display: flex;
                  align-items: center;
                  justify-content: space-between;
                  gap: 0.5rem;
                }
                .gem-updated-dot {
                  width: 0.45rem;
                  height: 0.45rem;
                  border-radius: 999px;
                  background: var(--green);
                  flex: 0 0 auto;
                }
                .gem-version {
                  color: var(--muted);
                  font-size: 0.76rem;
                }
                .detail {
                  padding: 0.5rem;
                  display: grid;
                  gap: 0.45rem;
                  align-content: start;
                  min-height: 0;
                  overflow: auto;
                }
                .detail-hero,
                .panel-heading {
                  display: flex;
                  justify-content: space-between;
                  gap: 0.65rem;
                  align-items: start;
                  flex-wrap: wrap;
                }
                .panel-heading-meta {
                  color: var(--muted);
                  font-size: 0.76rem;
                }
                .detail-copy,
                .revision-panel,
                .empty-panel {
                  border: 1px solid #f0ede6;
                  border-radius: 0.25rem;
                  background: #fff;
                  padding: 0.5rem;
                }
                .link-strip {
                  display: flex;
                  gap: 0.3rem;
                  flex-wrap: wrap;
                }
                .revision-panel {
                  display: grid;
                  gap: 0.4rem;
                }
                .revision-group {
                  display: grid;
                  gap: 0.3rem;
                }
                .revision-group-header h4 {
                  margin: 0;
                  font-size: 0.92rem;
                }
                .revision-card {
                  border-radius: 0.2rem;
                  padding: 0.5rem;
                  border: 1px solid #f0ede6;
                  background: #fff;
                }
                .revision-future {
                  border-style: dashed;
                  border-color: rgba(124, 124, 133, 0.55);
                  background: linear-gradient(180deg, rgba(124, 124, 133, 0.07), rgba(255,255,255,0.45));
                }
                .revision-current {
                  border-color: rgba(180, 77, 37, 0.25);
                }
                .revision-card-header {
                  display: flex;
                  align-items: start;
                  justify-content: space-between;
                  gap: 0.4rem;
                  margin-bottom: 0.3rem;
                }
                .revision-card h5 {
                  margin: 0;
                  font-size: 1rem;
                }
                .revision-markup > :first-child {
                  margin-top: 0;
                }
                .revision-markup > :last-child {
                  margin-bottom: 0;
                }
                .empty-state,
                .empty-panel {
                  padding: 0.6rem;
                }
                @media (max-width: 980px) {
                  .topbar {
                    align-items: start;
                    flex-direction: column;
                    flex-wrap: wrap;
                  }
                  .brand-lockup h1 {
                    white-space: normal;
                  }
                  .picker-row {
                    width: 100%;
                    justify-content: stretch;
                    flex-wrap: wrap;
                  }
                  .picker {
                    width: 100%;
                    justify-content: space-between;
                  }
                  .picker select {
                    min-width: 0;
                    width: 100%;
                    max-width: none;
                  }
                  .workspace-body {
                    grid-template-columns: 1fr;
                    min-height: 0;
                    height: auto;
                  }
                  .sidebar,
                  .detail {
                    overflow: visible;
                  }
                }
              </style>
            </head>
            <body>
              #{yield}
            </body>
          </html>
        HTML
      end

      def render_behavior_script
        <<~HTML
          <script>
            (() => {
              const projectSelect = document.querySelector("[data-project-select]");
              const fromSelect = document.querySelector("[data-from-select]");
              const toSelect = document.querySelector("[data-to-select]");
              const sidebarPanel = document.querySelector("[data-sidebar-panel]");
              const filterButtons = Array.from(document.querySelectorAll("[data-filter-button]"));
              let detailPanel = document.querySelector("[data-detail-panel]");
              const gemLinks = Array.from(document.querySelectorAll("[data-gem-link]"));
              let detailPollTimer = null;
              let currentFilter = "updated";

              const visibleGemLinks = () => gemLinks.filter((link) => !link.hidden);
              const currentSelectedIndex = () => visibleGemLinks().findIndex((link) => link.classList.contains("is-selected"));

              const applyGemFilter = (filter) => {
                currentFilter = filter;

                filterButtons.forEach((button) => {
                  button.classList.toggle("is-active", button.dataset.filterButton === filter);
                });

                gemLinks.forEach((link) => {
                  const updated = link.dataset.gemUpdated === "true";
                  link.hidden = filter === "updated" && !updated;
                });
              };

              const syncSidebarSelection = (gemName = null, keepVisible = false) => {
                const effectiveGemName = gemName || new URL(window.location.href).searchParams.get("gem");
                if (!effectiveGemName) return;

                let selectedLink = null;
                gemLinks.forEach((link) => {
                  const matches = link.dataset.gemName === effectiveGemName;
                  link.classList.toggle("is-selected", matches);
                  if (matches) {
                    selectedLink = link;
                  }
                });

                if (keepVisible && sidebarPanel && selectedLink) {
                  selectedLink.scrollIntoView({ block: "nearest" });
                }
              };

              if ("scrollRestoration" in history) {
                history.scrollRestoration = "manual";
              }

              const replaceDetail = (html) => {
                if (!detailPanel) return;
                detailPanel.outerHTML = html;
                detailPanel = document.querySelector("[data-detail-panel]");
                if (detailPanel) detailPanel.scrollTop = 0;
                scheduleDetailPoll();
              };

              const stopDetailPoll = () => {
                if (detailPollTimer) {
                  clearTimeout(detailPollTimer);
                  detailPollTimer = null;
                }
              };

              const fetchDetail = (url, pushHistory = true) => {
                fetch(url, { headers: { "X-Requested-With": "gemstar-detail" } })
                  .then((response) => response.text())
                  .then((html) => {
                    replaceDetail(html);
                    if (pushHistory) {
                      const pageUrl = new URL(window.location.href);
                      const detailUrl = new URL(url, window.location.origin);
                      pageUrl.search = detailUrl.search;
                      window.history.pushState({}, "", pageUrl);
                    }
                    const detailUrl = new URL(url, window.location.origin);
                    syncSidebarSelection(detailUrl.searchParams.get("gem"));
                  });
              };

              const activateGemLink = (link, pushHistory = true, keepVisible = false) => {
                if (!link) return;

                syncSidebarSelection(link.dataset.gemName, keepVisible);
                fetchDetail(link.dataset.detailUrl || link.href, pushHistory);

                if (sidebarPanel) {
                  sidebarPanel.focus({ preventScroll: true });
                }
              };

              const scheduleDetailPoll = () => {
                stopDetailPoll();
                if (!detailPanel || detailPanel.dataset.detailPending !== "true") return;
                detailPollTimer = setTimeout(() => {
                  fetchDetail(detailPanel.dataset.detailUrl, false);
                }, 1000);
              };

              if (detailPanel) {
                detailPanel.scrollTop = 0;
                scheduleDetailPoll();
              }

              syncSidebarSelection(null, true);
              applyGemFilter(currentFilter);

              gemLinks.forEach((link) => {
                link.addEventListener("click", (event) => {
                  event.preventDefault();
                  activateGemLink(link);
                });
              });

              filterButtons.forEach((button) => {
                button.addEventListener("click", () => {
                  applyGemFilter(button.dataset.filterButton);
                  syncSidebarSelection(null, true);
                });
              });

              const navigate = (params) => {
                const url = new URL(window.location.href);
                Object.entries(params).forEach(([key, value]) => {
                  if (value === null || value === undefined || value === "") {
                    url.searchParams.delete(key);
                  } else {
                    url.searchParams.set(key, value);
                  }
                });
                window.location.href = url.toString();
              };

              if (projectSelect) {
                projectSelect.addEventListener("change", (event) => {
                  if (event.target.value === "__add__") {
                    window.alert("Add project UI is next. For now, restart gemstar server with another --project path.");
                    event.target.value = "#{@selected_project_index || 0}";
                    return;
                  }
                  navigate({ project: event.target.value, from: null, to: "worktree", gem: null });
                });
              }

              if (fromSelect) {
                fromSelect.addEventListener("change", (event) => {
                  navigate({ from: event.target.value, gem: null });
                });
              }

              if (toSelect) {
                toSelect.addEventListener("change", (event) => {
                  navigate({ to: event.target.value, gem: null });
                });
              }

              document.addEventListener("keydown", (event) => {
                const tagName = document.activeElement && document.activeElement.tagName;
                if (tagName === "INPUT" || tagName === "TEXTAREA" || tagName === "SELECT") return;
                const links = visibleGemLinks();
                if (!links.length) return;

                const selectedGem = currentSelectedIndex();
                const currentIndex = selectedGem >= 0 ? selectedGem : 0;
                let nextIndex = null;

                if (event.key === "ArrowDown") nextIndex = Math.min(currentIndex + 1, links.length - 1);
                if (event.key === "ArrowUp") nextIndex = Math.max(currentIndex - 1, 0);

                if (nextIndex !== null && nextIndex !== currentIndex) {
                  event.preventDefault();
                  activateGemLink(links[nextIndex], true, true);
                }
              });

              window.addEventListener("popstate", () => {
                window.location.reload();
              });
            })();
          </script>
        HTML
      end

      def h(value)
        CGI.escapeHTML(value.to_s)
      end
    end
  end
end
