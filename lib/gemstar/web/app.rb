require "cgi"
require "erb"
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
      MISSING_METADATA = Object.new

      class << self
        def build(projects:, config_home:, cache_warmer: nil)
          Class.new(self) do
            opts[:projects] = projects
            opts[:config_home] = config_home
            opts[:cache_warmer] = cache_warmer
            opts[:change_sections_cache] = {}
            opts[:detail_html_cache] = {}
            opts[:detail_request_cache] = {}
            opts[:metadata_cache] = {}
          end.freeze.app
        end
      end

      route do |r|
        @projects = self.class.opts.fetch(:projects)
        @config_home = self.class.opts.fetch(:config_home)
        @cache_warmer = self.class.opts[:cache_warmer]
        @metadata_cache = self.class.opts[:metadata_cache]
        apply_no_cache_headers!

        r.root do
          load_state(r.params)
          prioritize_selected_gem

          render_page(page_title) do
            render_shell
          end
        end

        r.get "detail" do
          request_cache_key = detail_request_cache_key(r.params)
          request_cache = self.class.opts[:detail_request_cache]
          if request_cache_key && request_cache.key?(request_cache_key)
            next request_cache[request_cache_key]
          end

          load_state(r.params)
          prioritize_selected_gem
          detail_html = render_detail
          request_cache[request_cache_key] = detail_html if request_cache_key
          detail_html
        end

        r.get "gemfile" do
          project_index = selected_project_index(r.params["project"])
          project = @projects[project_index]
          response.status = 404
          next "Gemfile not found" unless project && File.file?(project.gemfile_path)

          response["Content-Type"] = "text/plain; charset=utf-8"
          File.read(project.gemfile_path)
        end

        r.on "projects", String do |project_id|
          response.redirect "/?project=#{project_id}"
        end
      end

      private

      def apply_no_cache_headers!
        response["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
        response["Pragma"] = "no-cache"
        response["Expires"] = "0"
      end

      def detail_request_cache_key(params)
        project_index = selected_project_index(params["project"])
        project = @projects[project_index]
        return nil unless project

        lockfile_stamp = File.file?(project.lockfile_path) ? File.mtime(project.lockfile_path).to_i : 0
        importmap_stamp = File.file?(project.importmap_path) ? File.mtime(project.importmap_path).to_i : 0

        [
          project_index,
          params["from"],
          params["to"],
          params["filter"],
          params["scope"],
          params["gem"],
          lockfile_stamp,
          importmap_stamp
        ]
      end

      def page_title
        return "Gemstar" unless @selected_project

        "#{@selected_project.name}: Gemstar"
      end

      def load_state(params)
        @selected_project_index = selected_project_index(params["project"])
        @selected_project = @projects[@selected_project_index]
        @revision_options = @selected_project ? @selected_project.revision_options : []
        @selected_to_revision_id = selected_to_revision_id(params["to"])
        @selected_from_revision_id = selected_from_revision_id(params["from"])
        @selected_to_revision_id = selected_to_revision_id(@selected_to_revision_id)
        @gem_states = @selected_project ? @selected_project.gem_states(from_revision_id: @selected_from_revision_id, to_revision_id: @selected_to_revision_id) : []
        @requested_gem_name = params["gem"]
        @selected_package_scope = selected_package_scope(params["scope"], params["gem"])
        @selected_filter = selected_filter(params["filter"], params["gem"])
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

        valid_ids = valid_from_revision_ids
        default_id = default_from_revision_id_for(@selected_to_revision_id)
        candidate = raw_revision_id.nil? || raw_revision_id.empty? ? default_id : raw_revision_id

        valid_ids.include?(candidate) ? candidate : default_id
      end

      def selected_to_revision_id(raw_revision_id)
        return "worktree" unless @selected_project

        valid_ids = valid_to_revision_ids
        candidate = raw_revision_id.nil? || raw_revision_id.empty? ? "worktree" : raw_revision_id

        valid_ids.include?(candidate) ? candidate : valid_ids.first || "worktree"
      end

      def selected_filter(raw_filter, raw_gem_name)
        return "all" if @gem_states.empty?
        return raw_filter if %w[updated all].include?(raw_filter)

        selected_gem = @gem_states.find { |gem| gem[:name] == raw_gem_name }
        return "all" if selected_gem && selected_gem[:status] == :unchanged

        @gem_states.any? { |gem| gem[:status] != :unchanged } ? "updated" : "all"
      end

      def selected_package_scope(raw_scope, raw_gem_name)
        return "all" if @gem_states.empty?

        available_scopes = available_package_scopes
        default_scope = available_scopes == ["gems"] ? "gems" : "all"
        return raw_scope if raw_scope == "all" || available_scopes.include?(raw_scope)

        selected_gem = @gem_states.find { |gem| gem[:name] == raw_gem_name }
        return selected_gem[:package_scope] if selected_gem

        default_scope
      end

      def selected_gem_state(raw_gem_name)
        return nil if @gem_states.empty?

        exact_match = @gem_states.find { |gem| gem[:name] == raw_gem_name && gem_visible_in_selected_scope?(gem) }
        exact_match ||= @gem_states.find { |gem| gem[:name] == raw_gem_name }
        return exact_match if exact_match

        @gem_states.find { |gem| gem_visible_in_selected_filter?(gem) && gem[:status] != :unchanged } ||
          @gem_states.find { |gem| gem_visible_in_selected_filter?(gem) } ||
          @gem_states.find { |gem| gem[:status] != :unchanged } ||
          @gem_states.first
      end

      def gem_visible_in_selected_filter?(gem_state)
        return false unless gem_visible_in_selected_scope?(gem_state)
        return true if @selected_filter != "updated"

        gem_state[:status] != :unchanged
      end

      def gem_visible_in_selected_scope?(gem_state)
        @selected_package_scope == "all" || gem_state[:package_scope] == @selected_package_scope
      end

      def available_package_scopes
        @selected_project ? @selected_project.package_scope_options.map { |option| option[:id] } : []
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
                  <h1>Gemstar</h1>
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
              <h1>Gemstar</h1>
            </div>
            <div class="picker-row">
              <label class="picker picker-project">
                <span class="picker-prefix" data-text-label="true">Project:</span>
                <select data-project-select>
                  #{project_options_html}
                  <option value="" disabled>────────</option>
                  <option value="__add__">Add...</option>
                </select>
              </label>
              <label class="picker">
                <span class="picker-prefix" data-text-label="true">From:</span>
                <select data-from-select #{'disabled="disabled"' unless @selected_project}>
                  #{from_revision_options_html}
                </select>
              </label>
              <label class="picker">
                <span class="picker-prefix" data-text-label="true">To:</span>
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
          disabled = valid_from_revision_ids.include?(option[:id]) ? "" : ' disabled="disabled"'
          <<~HTML
            <option value="#{h(option[:id])}"#{selected}#{disabled}>#{h(option[:label])} · #{h(option[:description])}</option>
          HTML
        end.join
      end

      def to_revision_options_html
        return '<option value="worktree">Worktree</option>' unless @selected_project

        @revision_options.map do |option|
          selected = option[:id] == @selected_to_revision_id ? ' selected="selected"' : ""
          disabled = valid_to_revision_ids.include?(option[:id]) ? "" : ' disabled="disabled"'
          <<~HTML
            <option value="#{h(option[:id])}"#{selected}#{disabled}>#{h(option[:label])} · #{h(option[:description])}</option>
          HTML
        end.join
      end

      def revision_option_index(revision_id)
        @revision_options.index { |option| option[:id] == revision_id }
      end

      def valid_from_revision_ids
        return [] unless @selected_project

        to_index = revision_option_index(@selected_to_revision_id) || 0
        @revision_options.filter_map.with_index do |option, index|
          option[:id] if index > to_index
        end
      end

      def valid_to_revision_ids
        return [] unless @selected_project
        return @revision_options.map { |option| option[:id] } unless @selected_from_revision_id

        from_index = revision_option_index(@selected_from_revision_id)
        return @revision_options.map { |option| option[:id] } if from_index.nil?

        @revision_options.filter_map.with_index do |option, index|
          option[:id] if index < from_index
        end
      end

      def default_from_revision_id_for(to_revision_id)
        default_id = @selected_project.default_from_revision_id
        return default_id if valid_from_revision_ids.include?(default_id)

        valid_from_revision_ids.first || default_id
      end

      def render_workspace
        <<~HTML
          <main class="workspace">
            #{render_toolbar}
            <div class="workspace-body">
              #{render_sidebar}
              #{render_initial_detail}
            </div>
          </main>
        HTML
      end

      def render_toolbar
        <<~HTML
          <section class="toolbar">
            <div class="toolbar-meta">
              <strong>#{@gem_states.count}</strong> #{h(@selected_project&.package_collection_label&.downcase || "packages")}
              <span>·</span>
              <strong>#{@gem_states.count { |gem| gem[:status] != :unchanged }}</strong> changes from #{h(selected_from_revision_label)} to #{h(selected_to_revision_label)}
            </div>
            <div class="toolbar-actions">
              <button type="button" class="action" disabled="disabled">bundle install</button>
              <button type="button" class="action action-primary" disabled="disabled">bundle update</button>
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
              <div class="sidebar-header-row">
                <h2>#{h(@selected_project&.package_collection_label || "Packages")}</h2>
                <div class="list-filters" data-list-filters>
                  <button type="button" class="list-filter-button#{' is-active' if @selected_filter == "updated"}" data-filter-button="updated">Updated</button>
                  <button type="button" class="list-filter-button#{' is-active' if @selected_filter == "all"}" data-filter-button="all">All</button>
                </div>
              </div>
              #{render_package_scope_filters}
              <input
                type="search"
                class="gem-search"
                data-gem-search
                placeholder="Search"
                autocomplete="off"
                spellcheck="false"
              >
            </div>
            #{render_gem_list}
          </aside>
        HTML
      end

      def render_gem_list
        return <<~HTML if @gem_states.empty?
          <section class="empty-panel">
            <p>No #{h(@selected_project&.package_collection_label&.downcase || "packages")} found in the current lockfile.</p>
          </section>
        HTML

        items = @gem_states.map do |gem|
          selected = gem[:name] == @selected_gem[:name] ? " is-selected" : ""
          status_class = " status-#{gem[:status]}"
          updated = gem[:status] != :unchanged
          hidden = (!gem_visible_in_selected_scope?(gem) || (@selected_filter == "updated" && !updated && gem[:name] != @requested_gem_name)) ? ' hidden="hidden"' : ""
          <<~HTML
            <a
              class="gem-row#{selected}#{status_class}"
              href="#{project_query(project: @selected_project_index, from: @selected_from_revision_id, to: @selected_to_revision_id, filter: @selected_filter, scope: @selected_package_scope, gem: gem[:name])}"
              data-gem-link="true"
              data-gem-name="#{h(gem[:name])}"
              data-gem-updated="#{updated}"
              data-package-scope="#{h(gem[:package_scope])}"
              data-detail-url="#{h(detail_query(project: @selected_project_index, from: @selected_from_revision_id, to: @selected_to_revision_id, filter: @selected_filter, scope: @selected_package_scope, gem: gem[:name]))}"
              #{hidden}
            >
              <span class="gem-name-row">
                <span class="gem-name-lockup">
                  <span class="gem-name">#{h(gem[:name])}</span>
                  <span class="package-type-tag">#{h(gem[:package_type_label])}</span>
                </span>
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
          <section class="empty-panel gem-list-empty" data-gem-list-empty hidden="hidden">
            <p>No updated #{h(@selected_project&.package_collection_label&.downcase || "packages")} in this revision range.</p>
          </section>
        HTML
      end

      def render_detail
        return empty_detail_html unless @selected_gem

        cache_key = [
          @selected_project_index,
          @selected_from_revision_id,
          @selected_to_revision_id,
          @selected_filter,
          @selected_package_scope,
          @selected_gem[:name],
          @selected_gem[:old_version],
          @selected_gem[:new_version],
          @selected_gem[:status]
        ]
        detail_cache = self.class.opts[:detail_html_cache]
        return detail_cache[cache_key] if detail_cache.key?(cache_key)

        metadata = metadata_for(@selected_gem, refresh_if_missing: true)
        groups = grouped_change_sections(@selected_gem)
        detail_pending = detail_pending?(@selected_gem[:name], metadata, groups)

        detail_html = <<~HTML
          <section class="detail" data-detail-panel tabindex="0" data-detail-pending="#{detail_pending}" data-detail-url="#{h(detail_query(project: @selected_project_index, from: @selected_from_revision_id, to: @selected_to_revision_id, filter: @selected_filter, scope: @selected_package_scope, gem: @selected_gem[:name]))}">
            #{render_detail_hero(metadata)}
            #{render_detail_loading_notice if detail_pending}
            #{render_detail_revision_panel(groups)}
          </section>
        HTML

        detail_cache[cache_key] = detail_html unless detail_pending
        detail_html
      end

      def render_initial_detail
        return empty_detail_html(loading: true) unless @selected_gem

        detail_url = detail_query(
          project: @selected_project_index,
          from: @selected_from_revision_id,
          to: @selected_to_revision_id,
          filter: @selected_filter,
          scope: @selected_package_scope,
          gem: @selected_gem[:name]
        )

        <<~HTML
          <section class="detail" data-detail-panel tabindex="0" data-detail-pending="false" data-detail-deferred="true" data-detail-url="#{h(detail_url)}">
            <div class="detail-loading-shell" aria-hidden="true">
              <div class="detail-loading-spinner"></div>
            </div>
          </section>
        HTML
      end

      def empty_detail_html(loading: false)
        <<~HTML
          <section class="detail" data-detail-panel tabindex="0">
            <div class="empty-panel">
              <h2>#{loading ? "Loading details" : "No gem selected"}</h2>
              <p>#{loading ? "Preparing the selected gem details." : "Choose a gem from the list to inspect its current version and changelog revisions."}</p>
            </div>
          </section>
        HTML
      end

      def render_detail_hero(metadata)
        description = metadata&.dig("info")
        bundle_origins = Array(@selected_gem[:bundle_origins])
        requirement_names = selected_gem_requirements
        bundled_version = @selected_gem[:new_version]
        added_on = selected_gem_added_on
        title_url = metadata&.dig("homepage_uri")
        title_url = repo_url_for(@selected_gem, metadata: metadata) if title_url.to_s.empty?
        title_markup = if title_url.to_s.empty?
          h(@selected_gem[:name])
        else
          %(<a href="#{h(title_url)}" target="_blank" rel="noreferrer">#{h(@selected_gem[:name])}</a>)
        end

        <<~HTML
          <section class="detail-hero">
            <div class="detail-hero-copy">
              <div class="detail-title-row">
                <div class="detail-title-lockup">
                  <h2>#{title_markup}#{bundled_version ? %(<span class="detail-title-version"> #{h(bundled_version)}</span>) : ""}</h2>
                </div>
                #{render_detail_links(metadata)}
              </div>
              <div class="detail-subtitle">#{render_detail_subtitle(description)}</div>
              #{render_dependency_details(bundle_origins, requirement_names, added_on)}
            </div>
          </section>
        HTML
      end

      def render_detail_subtitle(description)
        text = description.to_s.strip
        return "<p>Metadata will appear here when package information is available.</p>" if text.empty?

        options = { hard_wrap: false }
        options[:input] = "GFM" if defined?(Kramdown::Parser::GFM)
        with_external_links(Kramdown::Document.new(text, options).to_html)
      rescue Kramdown::Error
        "<p>#{h(text)}</p>"
      end

      def render_added_on(added_on)
        return "" unless added_on

        revision_markup = if added_on[:revision_url]
          %(<a href="#{h(added_on[:revision_url])}" target="_blank" rel="noreferrer" data-gem-link-inline="true">#{h(added_on[:revision])}</a>)
        else
          h(added_on[:revision])
        end

        <<~HTML
          <div class="detail-origin">
            <p>Added to project <strong>#{h(added_on[:project_name])}</strong> on #{h(added_on[:date])} (#{revision_markup}).</p>
          </div>
        HTML
      end

      def dependency_origin_items(bundle_origins)
        origins = Array(bundle_origins).filter_map do |origin|
          path = Array(origin[:path]).compact
          display_path = path.dup
          display_path.pop if display_path.last == @selected_gem[:name]

          next if origin[:type] != :direct && display_path.empty?

          linked_path = linked_gem_chain(["Gemfile", *display_path])
          label = origin[:type] == :direct ? gemfile_link("Gemfile") : linked_path
          origin[:requirement] ? "#{label} (#{h(origin[:requirement])})" : label
        end.uniq
      end

      def render_detail_links(metadata)
        repo_url = repo_url_for(@selected_gem, metadata: metadata)
        homepage_url = metadata&.dig("homepage_uri")

        buttons = []
        if @selected_gem[:package_scope] == "gems"
          rubygems_url = "https://rubygems.org/gems/#{URI.encode_www_form_component(@selected_gem[:name])}"
          buttons << icon_button("RubyGems", rubygems_url, icon_type: :rubygems)
        elsif homepage_url && !homepage_url.empty? && (!repo_url || homepage_url != repo_url)
          buttons << icon_button("Source", homepage_url, icon_type: :home)
        end
        buttons << icon_button("GitHub", repo_url, icon_type: :github) if repo_url && !repo_url.empty?
        buttons << icon_button("Homepage", homepage_url, icon_type: :home) if homepage_url && !homepage_url.empty?

        <<~HTML
          <section class="link-strip">
            #{buttons.join}
          </section>
        HTML
      end

      def render_dependency_details(bundle_origins, requirement_names, added_on)
        required_by = dependency_origin_items(bundle_origins)
        requires = Array(requirement_names).compact.uniq.map { |name| internal_gem_link(name) }
        platforms = selected_gem_platform_items
        source_items = selected_gem_source_items
        added_markup = render_added_on(added_on)
        return "" if required_by.empty? && requires.empty? && platforms.empty? && source_items.empty? && added_markup.empty?

        <<~HTML
          <details class="detail-disclosure">
            <summary><span class="detail-disclosure-caret" aria-hidden="true"></span><h3>Details</h3></summary>
            <div class="detail-disclosure-panel">
              #{added_markup}
              #{render_dependency_popover_section("Platforms", platforms)}
              #{render_dependency_popover_section("Source", source_items)}
              #{render_dependency_popover_section("Required by", required_by)}
              #{render_dependency_popover_section("Requires", requires)}
            </div>
          </details>
        HTML
      end

      def render_dependency_popover_section(title, items)
        return "" if items.empty?

        list_items = items.map { |item| "<li>#{item}</li>" }.join
        <<~HTML
          <section class="detail-info-section">
            <strong>#{h(title)}</strong>
            <ul class="detail-origin-list">
              #{list_items}
            </ul>
          </section>
        HTML
      end

      def selected_gem_requirements
        return [] unless @selected_gem[:package_scope] == "gems"

        lockfile = if @selected_gem[:new_version]
          @selected_project&.lockfile_for_revision(@selected_to_revision_id)
        else
          @selected_project&.lockfile_for_revision(@selected_from_revision_id)
        end

        Array(lockfile&.dependency_graph&.fetch(@selected_gem[:name], nil))
      end

      def selected_gem_added_on
        revision_id = @selected_gem[:new_version] ? @selected_to_revision_id : @selected_from_revision_id
        @selected_project&.package_added_on(@selected_gem[:name], package_scope: @selected_gem[:package_scope], revision_id: revision_id)
      end

      def selected_gem_platform_items
        platform = @selected_gem[:platform]
        return [] if platform.to_s.empty?

        [h(platform)]
      end

      def selected_gem_source_items
        source = @selected_gem[:source] || {}
        source_type = source[:type]

        case source_type
        when :path
          location = source[:path] || source[:remote]
          return [] if location.to_s.empty?

          ["Path (#{h(location)})"]
        when :git
          remote = source[:remote]
          pieces = ["Git"]
          pieces << h(remote) unless remote.to_s.empty?
          pieces << "@#{h(source[:branch])}" if source[:branch]
          pieces << "##{h(source[:tag])}" if source[:tag]
          pieces << h(source[:revision].to_s[0, 8]) if source[:revision]
          [pieces.join(" ")]
        when :rubygems
          remote = source[:remote]
          [remote.to_s.empty? ? "RubyGems" : "RubyGems (#{h(remote)})"]
        when :importmap
          remote = source[:remote]
          [remote.to_s.empty? ? "Importmap" : "Importmap (#{h(remote)})"]
        else
          []
        end
      end

      def linked_gem_chain(names)
        Array(names).map.with_index do |name, index|
          if index.zero?
            gemfile_link(name)
          else
            internal_gem_link(name)
          end
        end.join(" → ")
      end

      def gemfile_link(label = "Gemfile")
        return h(label) unless @selected_project

        href = "/gemfile?#{URI.encode_www_form(project: @selected_project_index)}"
        %(<a href="#{h(href)}" target="_blank" rel="noreferrer" data-gem-link-inline="true">#{h(label)}</a>)
      end

      def internal_gem_link(name)
        href = project_query(
          project: @selected_project_index,
          from: @selected_from_revision_id,
          to: @selected_to_revision_id,
          filter: @selected_filter,
          scope: @selected_package_scope,
          gem: name
        )

        %(<a href="#{h(href)}" data-gem-link-inline="true">#{h(name)}</a>)
      end

      def render_detail_revision_panel(groups)
        <<~HTML
          <section class="revision-panel">
            #{render_revision_group("Latest", groups[:latest], empty_message: nil) if groups[:latest].any?}
            #{render_revision_group(current_section_title, groups[:current], empty_message: "No changelog entries in this revision range.")}
            #{render_revision_group("Earlier changes", groups[:previous], empty_message: nil) if groups[:previous].any?}
          </section>
        HTML
      end

      def render_detail_loading_notice
        <<~HTML
          <section class="empty-panel">
            <p>Loading package metadata and changelog in the background...</p>
          </section>
        HTML
      end

      def render_revision_group(title, sections, empty_message:)
        cards = if sections.empty?
          return "" unless empty_message

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
        title_links = revision_card_links(section)
        status_class = @selected_gem ? " status-#{@selected_gem[:status]}" : ""

        <<~HTML
          <article class="revision-card revision-#{section[:kind]}#{status_class}">
            <header class="revision-card-header">
              <div class="revision-card-titlebar">
                <h5>#{h(section[:title] || section[:version])}</h5>
                <div class="revision-card-actions">
                  #{title_links.join}
                </div>
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
        latest = sections.select { |section| section[:kind] == :future }
        current = sections.select { |section| section[:kind] == :current }
        previous = sections.select { |section| section[:kind] == :previous }

        if current.empty?
          fallback = fallback_current_section(gem_state, previous, latest)
          current = [fallback] if fallback
        end

        {
          latest: latest,
          current: current,
          previous: previous
        }
      end

      def change_sections(gem_state)
        cache_key = [gem_state[:name], gem_state[:old_version], gem_state[:new_version], gem_state[:status]]
        change_sections_cache = self.class.opts[:change_sections_cache]
        return change_sections_cache[cache_key] if change_sections_cache.key?(cache_key)

        return [] if gem_state[:new_version].nil? && gem_state[:old_version].nil?
        return change_sections_cache[cache_key] = [] unless gem_state[:package_scope] == "gems"

        metadata = Gemstar::RubyGemsMetadata.new(gem_state[:name])
        sections = resolved_sections(metadata, gem_state)
        return change_sections_cache[cache_key] = [] if sections.nil? || sections.empty?

        current_version = gem_state[:new_version] || gem_state[:old_version]
        previous_version = gem_state[:old_version]

        rendered_sections = sections.keys.filter_map do |version|
          kind = section_kind(version, previous_version, current_version, gem_state[:status])
          next unless kind
          content = changelog_content(sections[version], heading_version: version)

          {
            version: version,
            title: content[:title],
            kind: kind,
            previous_version: previous_section_version(sections.keys, version),
            html: content[:html]
          }
        end

        change_sections_cache[cache_key] = rendered_sections.sort_by { |section| section_sort_key(section) }
      rescue StandardError
        []
      end

      def resolved_sections(metadata, gem_state)
        changelog = Gemstar::ChangeLog.new(metadata)
        cached_sections = changelog.sections(cache_only: true) || {}
        return cached_sections unless selected_gem_requires_refresh?(gem_state, cached_sections)

        @metadata_cache.delete([gem_state[:package_scope], gem_state[:name]])
        metadata.meta(cache_only: false, force_refresh: true)
        metadata.repo_uri(cache_only: false, force_refresh: true)
        Gemstar::ChangeLog.new(metadata).sections(cache_only: false, force_refresh: true) || cached_sections
      end

      def selected_gem_requires_refresh?(gem_state, cached_sections)
        return false unless @selected_gem && gem_state[:name] == @selected_gem[:name]

        bundled_version = gem_state[:new_version] || gem_state[:old_version]
        return false if bundled_version.nil?
        metadata = metadata_for(gem_state) || {}
        has_upstream_release_source =
          !metadata["changelog_uri"].to_s.empty? ||
          !metadata["source_code_uri"].to_s.empty? ||
          !metadata["homepage_uri"].to_s.empty?
        return false unless has_upstream_release_source
        return true if cached_sections.nil? || cached_sections.empty?

        cached_versions = cached_sections.keys
        return true unless cached_versions.include?(bundled_version)

        compare_versions(bundled_version, newest_version(cached_versions)) == 1
      end

      def newest_version(versions)
        Array(versions).max { |left, right| compare_versions(left, right) }
      end

      def section_kind(version, previous_version, current_version, status)
        return :future if compare_versions(version, current_version) == 1
        return :current if status == :added && compare_versions(version, current_version) <= 0

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

      def changelog_content(lines, heading_version: nil)
        text = Array(lines).flatten.join
        return { title: heading_version.to_s, html: "<p>No changelog text available.</p>" } if text.strip.empty?

        if heading_version
          text = strip_leading_version_heading(text, heading_version)
        end

        options = { hard_wrap: false }
        options[:input] = "GFM" if defined?(Kramdown::Parser::GFM)
        html = Kramdown::Document.new(text, options).to_html
        extract_card_title(with_external_links(html), fallback_title: heading_version.to_s, version: heading_version.to_s)
      rescue Kramdown::Error
        { title: heading_version.to_s, html: "<pre>#{h(text)}</pre>" }
      end

      def extract_card_title(html, fallback_title:, version:)
        fragment = Nokogiri::HTML::DocumentFragment.parse(html)
        first_heading = fragment.at_css("h1, h2, h3, h4, h5, h6")
        title = fallback_title

        if first_heading
          heading_text = first_heading.text.to_s.strip
          if heading_text.include?(version.to_s)
            title = heading_text
            first_heading.remove
          end
        end

        { title: title, html: fragment.to_html }
      end

      def strip_leading_version_heading(text, heading_version)
        stripped = text.sub(/\A\s*#+\s*v?#{Regexp.escape(heading_version)}\s*\n+/i, "")
        return strip_leading_hash_separator(stripped) unless stripped == text

        lines = text.lines
        return text if lines.empty?

        first_line = lines.first.to_s
        heading_like =
          first_line.match?(/\A\s*v?#{Regexp.escape(heading_version)}\b/i) ||
          first_line.match?(/\A\s*[\[(]?v?#{Regexp.escape(heading_version)}\b/i)

        return text unless heading_like

        remaining = lines.drop(1)
        remaining.shift while remaining.first&.strip&.empty?
        strip_leading_hash_separator(remaining.join)
      end

      def strip_leading_hash_separator(text)
        text.sub(/\A\s*#{Regexp.escape("#")}{4,}\s*\n+/, "")
      end

      def compare_versions(left, right)
        Gem::Version.new(left.to_s.gsub(/-[\w\-]+$/, "")) <=> Gem::Version.new(right.to_s.gsub(/-[\w\-]+$/, ""))
      rescue ArgumentError
        left.to_s <=> right.to_s
      end

      def metadata_for(package_state_or_name, refresh_if_missing: false)
        package_state = package_state_or_name.is_a?(Hash) ? package_state_or_name : { name: package_state_or_name, package_scope: "gems" }
        gem_name = package_state[:name]
        cache_key = [package_state[:package_scope], gem_name]
        cached = @metadata_cache[cache_key]
        return nil if cached.equal?(MISSING_METADATA)
        return cached if cached

        if package_state[:package_scope] != "gems"
          metadata = local_package_metadata(package_state)
          @metadata_cache[cache_key] = metadata || MISSING_METADATA
          return metadata
        end

        metadata = Gemstar::RubyGemsMetadata.new(gem_name).meta(cache_only: true)
        if metadata.nil? && refresh_if_missing
          metadata = Gemstar::RubyGemsMetadata.new(gem_name).meta(cache_only: false, force_refresh: true)
        end

        @metadata_cache[cache_key] = metadata || MISSING_METADATA
        metadata
      rescue StandardError
        @metadata_cache[cache_key] = MISSING_METADATA
        nil
      end

      def local_package_metadata(package_state)
        source = package_state[:source] || {}
        remote = source[:remote].to_s
        repo_url = source[:repo_url].to_s

        {
          "info" => "JavaScript package pinned in config/importmap.rb",
          "homepage_uri" => absolute_url?(remote) ? remote : nil,
          "source_code_uri" => repo_url.empty? ? nil : repo_url
        }
      end

      def repo_url_for(package_state, metadata: nil)
        return nil unless package_state
        return package_state.dig(:source, :repo_url) if package_state[:package_scope] != "gems"

        Gemstar::RubyGemsMetadata.new(package_state[:name]).repo_uri(cache_only: true)
      end

      def absolute_url?(value)
        value.to_s.match?(%r{\Ahttps?://}i)
      end

      def detail_pending?(gem_name, metadata, groups)
        false
      end

      def icon_button(label, url, icon_type:)
        <<~HTML
          <a class="link-button icon-button" href="#{h(url)}" target="_blank" rel="noreferrer" aria-label="#{h(label)}" title="#{h(label)}">
            #{icon_svg(icon_type)}
          </a>
        HTML
      end

      def icon_svg(icon_type)
        case icon_type
        when :github
          '<svg viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" d="M8 0C3.58 0 0 3.67 0 8.2c0 3.63 2.29 6.7 5.47 7.78.4.08.55-.18.55-.4 0-.2-.01-.86-.01-1.56-2.01.38-2.53-.5-2.69-.96-.09-.24-.48-.97-.81-1.17-.27-.15-.66-.52-.01-.53.61-.01 1.04.58 1.18.82.7 1.2 1.82.86 2.27.66.07-.52.27-.86.49-1.06-1.78-.21-3.64-.92-3.64-4.07 0-.9.31-1.64.82-2.22-.08-.21-.36-1.06.08-2.21 0 0 .67-.22 2.2.85a7.36 7.36 0 0 1 4 0c1.53-1.07 2.2-.85 2.2-.85.44 1.15.16 2 .08 2.21.51.58.82 1.31.82 2.22 0 3.16-1.87 3.86-3.65 4.07.28.25.53.73.53 1.48 0 1.07-.01 1.94-.01 2.2 0 .22.15.49.55.4A8.24 8.24 0 0 0 16 8.2C16 3.67 12.42 0 8 0Z"/></svg>'
        when :home
          '<svg viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" d="M8 .8 1.2 6.3v8.9h4.3V10h5v5.2h4.3V6.3L8 .8Zm5.2 13.3h-1.8V8.9H4.6v5.2H2.8V6.8L8 2.6l5.2 4.2v7.3Z"/></svg>'
        when :rubygems
          '<svg viewBox="0 0 16 16" aria-hidden="true"><rect width="16" height="16" rx="2.6" fill="#fff"/><path fill="#111" d="m8 2.35 4.55 2.63v5.24L8 12.85l-4.55-2.63V4.98L8 2.35Zm0 1.3L4.58 5.62v3.96L8 11.55l3.42-1.97V5.62L8 3.65Zm0 1.07 2.5 1.44v2.88L8 10.48 5.5 9.04V6.16L8 4.72Z"/></svg>'
        when :info
          '<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6.5" fill="none" stroke="currentColor" stroke-width="1.4"/><circle cx="8" cy="4.5" r="0.9" fill="currentColor"/><path d="M8 7v4" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>'
        else
          '<svg viewBox="0 0 16 16" aria-hidden="true"><rect width="16" height="16" rx="2.6" fill="#fff"/><path fill="#111" d="m8 2.35 4.55 2.63v5.24L8 12.85l-4.55-2.63V4.98L8 2.35Zm0 1.3L4.58 5.62v3.96L8 11.55l3.42-1.97V5.62L8 3.65Zm0 1.07 2.5 1.44v2.88L8 10.48 5.5 9.04V6.16L8 4.72Z"/></svg>'
        end
      end

      def current_section_title
        if @selected_to_revision_id == "worktree"
          "Worktree changes since #{selected_from_revision_label}"
        else
          "Changes from #{selected_from_revision_label} to #{selected_to_revision_label}"
        end
      end

      def range_label(gem_state)
        old_version = gem_state[:old_version]
        new_version = gem_state[:new_version]
        return new_version.to_s if old_version == new_version
        return "new-#{new_version}" if old_version.nil? && new_version
        return "#{old_version}-removed" if old_version && new_version.nil?

        "#{old_version}-#{new_version}"
      end

      def previous_section_version(versions, current_version)
        ordered_versions = versions.sort_by { |version| -sortable_version_number(version) }
        current_index = ordered_versions.index(current_version)
        return nil if current_index.nil?

        ordered_versions[current_index + 1]
      end

      def revision_card_links(section)
        repo_url = repo_url_for(@selected_gem)
        return [] if repo_url.to_s.empty?

        links = []
        compare_url = github_compare_url(repo_url, section[:previous_version], section[:version])
        links << icon_button("Git diff", compare_url, icon_type: :github) if compare_url

        release_url = github_release_url(repo_url, section[:version])
        links << icon_button("Release", release_url, icon_type: :github) if release_url && compare_url.nil?
        links
      end

      def fallback_current_section(gem_state, previous_sections, latest_sections)
        version = gem_state[:new_version] || gem_state[:old_version]
        return nil if version.nil?
        return nil if previous_sections.any? { |section| section[:version] == version }
        return nil if latest_sections.any? { |section| section[:version] == version }

        metadata = metadata_for(gem_state) || {}
        repo_url = repo_url_for(gem_state, metadata: metadata)
        fallback_url =
          if !repo_url.to_s.empty?
            repo_url
          elsif metadata["project_uri"]
            metadata["project_uri"]
          elsif metadata["source_code_uri"]
            metadata["source_code_uri"]
          elsif metadata["homepage_uri"]
            metadata["homepage_uri"]
          else
            metadata["documentation_uri"]
          end
        fallback_label = if repo_url.to_s.empty?
          if gem_state[:package_scope] == "gems"
            metadata["project_uri"] ? "the RubyGems page" : "the gem documentation"
          else
            fallback_url == metadata["documentation_uri"] ? "the package documentation" : "the package source"
          end
        else
          gem_state[:package_scope] == "gems" ? "the gem repository" : "the package repository"
        end
        fallback_link = if fallback_url.to_s.empty?
          fallback_label
        else
          %(<a href="#{h(fallback_url)}" target="_blank" rel="noreferrer">#{h(fallback_label)}</a>)
        end

        {
          version: version,
          title: version,
          kind: :current,
          previous_version: fallback_previous_version_for(gem_state, previous_sections),
          html: "<p>No release information available. Check #{fallback_link} for more information.</p>"
        }
      end

      def fallback_previous_version_for(gem_state, previous_sections)
        return gem_state[:old_version] if gem_state[:new_version]
        return previous_sections.first[:version] if previous_sections.any?

        nil
      end

      def github_compare_url(repo_url, previous_version, current_version)
        return nil unless repo_url.include?("github.com")
        return nil if previous_version.nil? || current_version.nil?

        "#{repo_url}/compare/#{github_tag_name(previous_version)}...#{github_tag_name(current_version)}"
      end

      def github_release_url(repo_url, version)
        return nil unless repo_url.include?("github.com")
        return nil if version.nil?

        "#{repo_url}/releases/tag/#{github_tag_name(version)}"
      end

      def github_tag_name(version)
        version.to_s.start_with?("v") ? version.to_s : "v#{version}"
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

      def detail_query(project:, from:, to:, filter:, scope:, gem:)
        "/detail?#{URI.encode_www_form(project: project, from: from, to: to, filter: filter, scope: scope, gem: gem)}"
      end

      def project_query(project:, from:, to:, filter:, scope:, gem:)
        params = {
          project: project,
          from: from,
          to: to,
          filter: filter,
          scope: scope,
          gem: gem
        }.compact

        "/?#{URI.encode_www_form(params)}"
      end

      def render_page(title)
        render_template(
          "page.html.erb",
          title: h(title),
          favicon_data_uri: favicon_data_uri,
          styles_css: template_source("app.css"),
          body_html: yield
        )
      end

      def favicon_data_uri
        svg = <<~SVG
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
            <rect width="64" height="64" rx="14" fill="#b44d25"/>
            <text x="32" y="44" text-anchor="middle" font-family="Avenir Next, Helvetica Neue, Segoe UI, sans-serif" font-size="34" font-weight="700" fill="#ffffff">G</text>
          </svg>
        SVG

        "data:image/svg+xml,#{URI.encode_www_form_component(svg)}"
      end

      def render_behavior_script
        script = render_template(
          "app.js.erb",
          empty_detail_html_json: empty_detail_html.dump,
          selected_filter_json: @selected_filter.dump,
          selected_package_scope_json: @selected_package_scope.dump,
          selected_project_index: @selected_project_index || 0
        )

        <<~HTML
          <script>
#{script}
          </script>
        HTML
      end

      def template_source(name)
        File.read(template_path(name))
      end

      def render_template(name, locals = {})
        ERB.new(template_source(name), trim_mode: "-").result_with_hash(locals)
      end

      def template_path(name)
        File.expand_path(File.join("templates", name), __dir__)
      end

      def h(value)
        CGI.escapeHTML(value.to_s)
      end

      def render_package_scope_filters
        options = @selected_project&.package_scope_options || []
        return "" if options.size <= 1

        buttons = []
        buttons << %(<button type="button" class="list-filter-button#{' is-active' if @selected_package_scope == "all"}" data-ecosystem-button="all">All</button>)

        buttons.concat(options.map do |option|
          %(<button type="button" class="list-filter-button#{' is-active' if @selected_package_scope == option[:id]}" data-ecosystem-button="#{h(option[:id])}">#{h(option[:label])}</button>)
        end)

        <<~HTML
          <div class="list-filters list-filters-secondary" data-ecosystem-filters>
            #{buttons.join}
          </div>
        HTML
      end
    end
  end
end
