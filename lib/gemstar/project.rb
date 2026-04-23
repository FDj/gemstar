require "time"

module Gemstar
  class Project
    REVISION_HISTORY_LIMIT = 100

    attr_reader :directory
    attr_reader :gemfile_path
    attr_reader :lockfile_path
    attr_reader :importmap_path
    attr_reader :package_json_path
    attr_reader :package_lock_path
    attr_reader :name

    def self.from_cli_argument(input)
      expanded_input = File.expand_path(input)
      if File.directory?(expanded_input)
        directory = expanded_input
      else
        basename = File.basename(expanded_input)
        directory =
          case basename
          when "Gemfile", "package.json", "package-lock.json"
            File.dirname(expanded_input)
          when "importmap.rb"
            File.dirname(File.dirname(expanded_input))
          else
            nil
          end
      end

      raise ArgumentError, "No supported project files found for #{input}" unless directory
      raise ArgumentError, "No supported project files found for #{input}" unless supported_project_directory?(directory)

      new(directory: directory)
    end

    def self.supported_project_directory?(directory)
      File.file?(File.join(directory, "Gemfile")) ||
        File.file?(File.join(directory, "config", "importmap.rb")) ||
        File.file?(File.join(directory, "package.json")) ||
        File.file?(File.join(directory, "package-lock.json"))
    end

    def initialize(directory:)
      @directory = File.expand_path(directory)
      @gemfile_path = File.join(@directory, "Gemfile")
      @lockfile_path = File.join(@directory, "Gemfile.lock")
      @importmap_path = File.join(@directory, "config", "importmap.rb")
      @package_json_path = File.join(@directory, "package.json")
      @package_lock_path = File.join(@directory, "package-lock.json")
      @name = File.basename(@directory)
      @lockfile_cache = {}
      @importmap_cache = {}
      @package_lock_cache = {}
      @gem_states_cache = {}
      @gem_added_on_cache = {}
      @history_cache = {}
    end

    def git_repo
      @git_repo ||= Gemstar::GitRepo.new(directory)
    end

    def git_root
      git_repo.tree_root_directory
    end

    def lockfile?
      File.file?(lockfile_path)
    end

    def current_lockfile
      return nil unless lockfile?

      @current_lockfile ||= Gemstar::LockFile.new(path: lockfile_path)
    end

    def gemfile?
      File.file?(gemfile_path)
    end

    def importmap?
      File.file?(importmap_path)
    end

    def current_importmap
      return nil unless importmap?

      @current_importmap ||= Gemstar::ImportmapFile.new(path: importmap_path, vendor_reader: importmap_vendor_reader("worktree"))
    end

    def package_lock?
      File.file?(package_lock_path)
    end

    def package_json?
      File.file?(package_json_path)
    end

    def current_package_lock
      return nil unless package_lock?

      @current_package_lock ||= Gemstar::PackageLockFile.new(path: package_lock_path)
    end

    def revision_history(limit: REVISION_HISTORY_LIMIT)
      history_for_paths(tracked_git_paths, limit: limit)
    end

    def lockfile_revision_history(limit: REVISION_HISTORY_LIMIT)
      return [] unless lockfile?

      relative_path = git_repo.relative_path(lockfile_path)
      return [] if relative_path.nil?

      history_for_paths([relative_path], limit: limit)
    end

    def gemfile_revision_history(limit: REVISION_HISTORY_LIMIT)
      return [] unless gemfile?

      relative_path = git_repo.relative_path(gemfile_path)
      return [] if relative_path.nil?

      history_for_paths([relative_path], limit: limit)
    end

    def default_from_revision_id
      default_changed_revision_id ||
        gemfile_revision_history(limit: 1).first&.dig(:id) ||
        "worktree"
    end

    def revision_options(limit: REVISION_HISTORY_LIMIT)
      [{ id: "worktree", label: "Worktree", description: "Current Gemfile.lock in the working tree" }] +
        revision_history(limit: limit).map do |revision|
          {
            id: revision[:id],
            label: revision[:short_sha],
            description: "#{revision[:subject]} (#{revision[:authored_at].strftime("%Y-%m-%d %H:%M")})"
          }
        end
    end

    def package_scopes
      scopes = []
      scopes << :gems if gemfile? || lockfile?
      scopes << :js if importmap? || package_lock? || package_json?
      scopes
    end

    def package_scope_options
      package_scopes.map do |scope|
        {
          id: package_scope_id(scope),
          label: package_scope_label(scope)
        }
      end
    end

    def package_collection_label
      package_scopes == [:gems] ? "Gems" : "Packages"
    end

    def lockfile_for_revision(revision_id)
      cache_key = revision_id || "worktree"
      return @lockfile_cache[cache_key] if @lockfile_cache.key?(cache_key)
      return @lockfile_cache[cache_key] = current_lockfile if revision_id.nil? || revision_id == "worktree"
      return nil unless lockfile?

      relative_lockfile_path = git_repo.relative_path(lockfile_path)
      return nil if relative_lockfile_path.nil?

      content = git_repo.try_git_command(["show", "#{revision_id}:#{relative_lockfile_path}"])
      return nil if content.nil? || content.empty?

      @lockfile_cache[cache_key] = Gemstar::LockFile.new(content: content)
    end

    def importmap_for_revision(revision_id)
      cache_key = revision_id || "worktree"
      return @importmap_cache[cache_key] if @importmap_cache.key?(cache_key)
      return @importmap_cache[cache_key] = current_importmap if revision_id.nil? || revision_id == "worktree"
      return nil unless importmap?

      relative_importmap_path = git_repo.relative_path(importmap_path)
      return nil if relative_importmap_path.nil?

      content = git_repo.try_git_command(["show", "#{revision_id}:#{relative_importmap_path}"])
      return nil if content.nil? || content.empty?

      @importmap_cache[cache_key] = Gemstar::ImportmapFile.new(content: content, vendor_reader: importmap_vendor_reader(revision_id))
    end

    def package_lock_for_revision(revision_id)
      cache_key = revision_id || "worktree"
      return @package_lock_cache[cache_key] if @package_lock_cache.key?(cache_key)
      return @package_lock_cache[cache_key] = current_package_lock if revision_id.nil? || revision_id == "worktree"
      return nil unless package_lock?

      relative_package_lock_path = git_repo.relative_path(package_lock_path)
      return nil if relative_package_lock_path.nil?

      content = git_repo.try_git_command(["show", "#{revision_id}:#{relative_package_lock_path}"])
      return nil if content.nil? || content.empty?

      @package_lock_cache[cache_key] = Gemstar::PackageLockFile.new(content: content)
    end

    def gem_states(from_revision_id: default_from_revision_id, to_revision_id: "worktree")
      cache_key = [from_revision_id, to_revision_id]
      return @gem_states_cache[cache_key] if @gem_states_cache.key?(cache_key)

      from_lockfile = lockfile_for_revision(from_revision_id)
      to_lockfile = lockfile_for_revision(to_revision_id)
      from_specs = from_lockfile&.specs || {}
      to_specs = to_lockfile&.specs || {}

      gem_states = (from_specs.keys | to_specs.keys).map do |gem_name|
        old_version = from_specs[gem_name]
        new_version = to_specs[gem_name]
        effective_lockfile = new_version ? to_lockfile : from_lockfile
        bundle_origins = effective_lockfile&.origins_for(gem_name) || []

        {
          name: gem_name,
          package_scope: "gems",
          package_type_label: "Gem",
          old_version: old_version,
          new_version: new_version,
          status: gem_status(old_version, new_version),
          version_label: version_label(old_version, new_version),
          platform: effective_lockfile&.platform_for(gem_name),
          source: effective_lockfile&.source_for(gem_name),
          bundle_origins: bundle_origins,
          bundle_origin_labels: bundle_origin_labels(bundle_origins)
        }
      end

      from_importmap = importmap_for_revision(from_revision_id)
      to_importmap = importmap_for_revision(to_revision_id)
      from_js_specs = from_importmap&.specs || {}
      to_js_specs = to_importmap&.specs || {}
      js_states = (from_js_specs.keys | to_js_specs.keys).map do |package_name|
        old_target = from_js_specs[package_name]
        new_target = to_js_specs[package_name]
        old_source = from_importmap&.source_for(package_name) || {}
        new_source = to_importmap&.source_for(package_name) || {}
        old_source = enrich_importmap_source(old_source, from_lockfile)
        new_source = enrich_importmap_source(new_source, to_lockfile)
        effective_source = new_target ? new_source : old_source
        old_package_version = js_package_version(old_source)
        new_package_version = js_package_version(new_source)
        comparison_old = old_package_version || old_target
        comparison_new = new_package_version || new_target

        {
          name: package_name,
          package_scope: "js",
          package_type_label: "JS",
          package_source_file: :importmap,
          old_version: old_package_version,
          new_version: new_package_version,
          raw_old_version: old_target,
          raw_new_version: new_target,
          status: gem_status(comparison_old, comparison_new),
          version_label: js_version_label(old_target, new_target, old_source, new_source),
          platform: nil,
          source: effective_source,
          bundle_origins: [],
          bundle_origin_labels: []
        }
      end

      from_package_lock = package_lock_for_revision(from_revision_id)
      to_package_lock = package_lock_for_revision(to_revision_id)
      from_npm_specs = from_package_lock&.specs || {}
      to_npm_specs = to_package_lock&.specs || {}
      npm_states = (from_npm_specs.keys | to_npm_specs.keys).map do |package_name|
        old_version = from_npm_specs[package_name]
        new_version = to_npm_specs[package_name]
        effective_package_lock = new_version ? to_package_lock : from_package_lock

        {
          name: package_name,
          package_scope: "js",
          package_type_label: "JS",
          package_source_file: :package_lock,
          old_version: old_version,
          new_version: new_version,
          status: gem_status(old_version, new_version),
          version_label: version_label(old_version, new_version),
          platform: nil,
          source: effective_package_lock&.source_for(package_name),
          bundle_origins: [],
          bundle_origin_labels: []
        }
      end

      @gem_states_cache[cache_key] = (gem_states + js_states + npm_states).sort_by { |gem| [gem[:name], gem[:package_scope], gem[:package_source_file].to_s] }
    end

    def package_added_on(package_name, package_scope:, revision_id: "worktree", source_file: nil)
      cache_key = [package_name, package_scope, source_file, revision_id]
      return @gem_added_on_cache[cache_key] if @gem_added_on_cache.key?(cache_key)

      tracked_file, reader =
        if source_file == :importmap
          [importmap_path, method(:importmap_for_revision)]
        elsif source_file == :package_lock
          [package_lock_path, method(:package_lock_for_revision)]
        elsif package_scope == "js"
          [importmap_path, method(:importmap_for_revision)]
        else
          [lockfile_path, method(:lockfile_for_revision)]
        end
      return @gem_added_on_cache[cache_key] = nil unless File.file?(tracked_file)

      target_snapshot = reader.call(revision_id)
      return @gem_added_on_cache[cache_key] = nil unless target_snapshot&.specs&.key?(package_name)

      relative_path = git_repo.relative_path(tracked_file)
      return @gem_added_on_cache[cache_key] = nil if relative_path.nil?

      first_seen_revision = history_for_paths([relative_path], limit: nil, reverse: true).find do |revision|
        snapshot = reader.call(revision[:id])
        snapshot&.specs&.key?(package_name)
      end

      return @gem_added_on_cache[cache_key] = worktree_added_on_info(tracked_file) if first_seen_revision.nil? && revision_id == "worktree"
      return @gem_added_on_cache[cache_key] = nil unless first_seen_revision

      @gem_added_on_cache[cache_key] = {
        project_name: name,
        date: first_seen_revision[:authored_at].strftime("%Y-%m-%d"),
        revision: first_seen_revision[:short_sha],
        revision_url: revision_url(first_seen_revision[:id]),
        worktree: false
      }
    end

    private

    def default_changed_revision_id
      current_specs = current_lockfile&.specs || {}
      current_importmap_specs = current_importmap&.specs || {}
      current_package_lock_specs = current_package_lock&.specs || {}

      revision_history(limit: REVISION_HISTORY_LIMIT).find do |revision|
        revision_lockfile = lockfile_for_revision(revision[:id])
        revision_importmap = importmap_for_revision(revision[:id])
        revision_package_lock = package_lock_for_revision(revision[:id])
        (revision_lockfile && revision_lockfile.specs != current_specs) ||
          (revision_importmap && revision_importmap.specs != current_importmap_specs) ||
          (revision_package_lock && revision_package_lock.specs != current_package_lock_specs)
      end&.dig(:id)
    end

    def history_for_paths(paths, limit: REVISION_HISTORY_LIMIT, reverse: false)
      return [] if git_root.nil? || git_root.empty?
      return [] if paths.empty?

      cache_key = [paths.sort, limit, reverse]
      return @history_cache[cache_key] if @history_cache.key?(cache_key)

      output = git_repo.log_for_paths(paths, limit: limit, reverse: reverse)
      return [] if output.nil? || output.empty?

      @history_cache[cache_key] = output.lines.filter_map do |line|
        full_sha, short_sha, authored_at, subject = line.strip.split("\u001f", 4)
        next if full_sha.nil?

        {
          id: full_sha,
          full_sha: full_sha,
          short_sha: short_sha,
          authored_at: Time.iso8601(authored_at),
          subject: subject
        }
      end
    rescue ArgumentError
      []
    end

    def tracked_git_paths
      [gemfile_path, lockfile_path, importmap_path, package_json_path, package_lock_path, *importmap_vendor_paths].filter_map do |path|
        next unless File.file?(path)

        git_repo.relative_path(path)
      end.uniq
    end

    def importmap_vendor_paths
      return [] unless current_importmap

      current_importmap.specs.values.filter_map do |target|
        next unless target.to_s.end_with?(".js", ".mjs")

        File.join(directory, "vendor", "javascript", target.to_s)
      end
    end

    def gem_status(old_version, new_version)
      return :added if old_version.nil? && !new_version.nil?
      return :removed if !old_version.nil? && new_version.nil?
      return :unchanged if old_version == new_version

      comparison = compare_versions(new_version, old_version)
      return :upgrade if comparison.positive?
      return :downgrade if comparison.negative?

      :changed
    end

    def version_label(old_version, new_version)
      return "new → #{new_version}" if old_version.nil? && !new_version.nil?
      return "#{old_version} → removed" if !old_version.nil? && new_version.nil?
      return new_version.to_s if old_version == new_version

      "#{old_version} → #{new_version}"
    end

    def importmap_version_label(old_target, new_target)
      old_label = importmap_target_label(old_target)
      new_label = importmap_target_label(new_target)
      return "new → #{new_label}" if old_target.nil? && !new_target.nil?
      return "#{old_label} → removed" if !old_target.nil? && new_target.nil?
      return new_label.to_s if old_target == new_target

      "#{old_label} → #{new_label}"
    end

    def js_version_label(old_target, new_target, old_source, new_source)
      old_label = js_version_label_part(old_target, old_source)
      new_label = js_version_label_part(new_target, new_source)
      return "new → #{new_label}" if old_target.nil? && !new_target.nil?
      return "#{old_label} → removed" if !old_target.nil? && new_target.nil?
      return new_label.to_s if old_target == new_target

      "#{old_label} → #{new_label}"
    end

    def js_version_label_part(target, source)
      version = js_package_version(source)
      return version if version && !version.empty?

      importmap_target_label(target)
    end

    def js_package_version(source)
      source && source[:package_version].to_s.empty? ? nil : source&.dig(:package_version)
    end

    def enrich_importmap_source(source, lockfile)
      source = (source || {}).dup
      provider_gem = source[:provider_gem]
      return source if provider_gem.to_s.empty?

      provider_version = lockfile&.specs&.[](provider_gem)
      source[:provider_version] = provider_version unless provider_version.to_s.empty?
      source[:package_version] ||= provider_version unless provider_version.to_s.empty?
      source
    end

    def importmap_target_label(target)
      return "" if target.nil?

      version = target.to_s[/@(\d+(?:\.\d+)*[\w.-]*)/, 1]
      return version if version

      target.to_s.sub(%r{\Ahttps?://}, "").slice(0, 36)
    end

    def importmap_vendor_reader(revision_id)
      lambda do |target|
        next nil unless target.to_s.end_with?(".js", ".mjs")

        vendor_path = File.join(directory, "vendor", "javascript", target.to_s)
        if revision_id.nil? || revision_id == "worktree"
          File.file?(vendor_path) ? File.read(vendor_path) : nil
        else
          relative_path = git_repo.relative_path(vendor_path)
          next nil if relative_path.nil?

          git_repo.try_git_command(["show", "#{revision_id}:#{relative_path}"])
        end
      end
    end

    def compare_versions(left, right)
      Gem::Version.new(left.to_s.gsub(/-[\w\-]+$/, "")) <=> Gem::Version.new(right.to_s.gsub(/-[\w\-]+$/, ""))
    rescue ArgumentError
      left.to_s <=> right.to_s
    end

    def bundle_origin_labels(origins)
      Array(origins).map do |origin|
        next "Gemfile" if origin[:type] == :direct

        label = ["Gemfile", *origin[:path]].join(" → ")
        origin[:requirement] ? "#{label} (#{origin[:requirement]})" : label
      end.compact.uniq
    end

    def worktree_added_on_info(path)
      return nil unless File.file?(path)

      {
        project_name: name,
        date: File.mtime(path).strftime("%Y-%m-%d"),
        revision: "Worktree",
        revision_url: nil,
        worktree: true
      }
    end

    def revision_url(full_sha)
      repo_url = git_repo.origin_repo_url
      return nil unless repo_url&.include?("github.com")

      "#{repo_url}/commit/#{full_sha}"
    end

    def package_scope_id(scope)
      case scope
      when :gems then "gems"
      when :js then "js"
      when :python then "python"
      else scope.to_s
      end
    end

    def package_scope_label(scope)
      case scope
      when :gems then "Gems"
      when :js then "JS"
      when :python then "Python"
      else scope.to_s.capitalize
      end
    end
  end
end
