require "set"
require "thread"

module Gemstar
  class CacheWarmer
    DEFAULT_THREADS = 10

    def initialize(io: $stderr, debug: false, thread_count: DEFAULT_THREADS)
      @io = io
      @debug = debug
      @thread_count = thread_count
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @queue = []
      @queued = Set.new
      @in_progress = Set.new
      @completed = Set.new
      @workers = []
      @started = false
      @total = 0
      @completed_count = 0
    end

    def enqueue_many(package_states)
      states = normalize_package_states(package_states)

      @mutex.synchronize do
        states.each do |package_state|
          key = package_key(package_state)
          next if @completed.include?(key) || @queued.include?(key) || @in_progress.include?(key)

          @queue << package_state
          @queued << key
        end
        @total += states.count
        start_workers_unlocked unless @started
      end

      log "Background cache refresh queued for #{states.count} packages."
      @condition.broadcast
      self
    end

    def prioritize(package_name)
      @mutex.synchronize do
        existing = @queue.find do |item|
          item[:name] == package_name || item.dig(:source, :package_name) == package_name
        end

        if existing
          key = package_key(existing)
          return if @completed.include?(key) || @in_progress.include?(key)
          @queue.delete(existing)
          @queue.unshift(existing)
        else
          synthetic = {
            name: package_name,
            package_scope: "gems",
            source: {}
          }
          key = package_key(synthetic)
          return if @completed.include?(key) || @in_progress.include?(key)
          @queued << key
          @queue.unshift(synthetic)
          @total += 1
        end
        start_workers_unlocked unless @started
      end

      log "Prioritized #{package_name}"
      @condition.broadcast
    end

    def pending?(package_name)
      @mutex.synchronize do
        @queue.any? { |item| item[:name] == package_name || item.dig(:source, :package_name) == package_name } ||
          @in_progress.any? { |key| key.end_with?(":#{package_name}") }
      end
    end

    private

    def start_workers_unlocked
      return if @started

      @started = true
      @thread_count.times do
        @workers << Thread.new { worker_loop }
      end
    end

    def worker_loop
      Thread.current.name = "gemstar-cache-worker" if Thread.current.respond_to?(:name=)

      loop do
        package_state = @mutex.synchronize do
          while @queue.empty?
            @condition.wait(@mutex)
          end

          next_package = @queue.shift
          key = package_key(next_package)
          @queued.delete(key)
          @in_progress << key
          next_package
        end

        warm_cache_for_package(package_state)

        current = @mutex.synchronize do
          key = package_key(package_state)
          @in_progress.delete(key)
          @completed << key
          @completed_count += 1
        end

        log_progress(package_label(package_state), current)
      end
    end

    def warm_cache_for_package(package_state)
      metadata = metadata_adapter_for(package_state)
      return unless metadata

      metadata.meta
      metadata.repo_uri
      Gemstar::ChangeLog.new(metadata).sections
    rescue StandardError => e
      log "Cache refresh failed for #{package_label(package_state)}: #{e.class}: #{e.message}"
    end

    def log_progress(package_name, current)
      return unless @debug
      return unless current <= 5 || (current % 25).zero?

      log "Background cache refresh #{current}/#{@total}: #{package_name}"
    end

    def log(message)
      @io.puts(message)
    end

    def normalize_package_states(package_states)
      Array(package_states).filter_map do |package_state|
        next unless package_state.is_a?(Hash)

        package_state
      end.uniq { |package_state| package_key(package_state) }
    end

    def package_key(package_state)
      scope = package_state[:package_scope].to_s
      source_type = package_state[:package_source_file].to_s
      package_name = package_state.dig(:source, :package_name) || package_state[:name]
      "#{scope}:#{source_type}:#{package_name}"
    end

    def package_label(package_state)
      package_state.dig(:source, :package_name) || package_state[:name]
    end

    def metadata_adapter_for(package_state)
      if package_state[:package_scope] == "js"
        provider_gem = package_state.dig(:source, :provider_gem)
        return Gemstar::RubyGemsMetadata.new(provider_gem) unless provider_gem.to_s.empty?

        package_name = package_state.dig(:source, :package_name) || package_state[:name]
        return nil if package_name.to_s.empty?

        return Gemstar::NpmMetadata.new(package_name)
      end

      Gemstar::RubyGemsMetadata.new(package_state[:name])
    end
  end
end
