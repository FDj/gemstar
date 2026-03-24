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

    def enqueue_many(gem_names)
      names = gem_names.uniq

      @mutex.synchronize do
        names.each do |gem_name|
          next if @completed.include?(gem_name) || @queued.include?(gem_name) || @in_progress.include?(gem_name)

          @queue << gem_name
          @queued << gem_name
        end
        @total += names.count
        start_workers_unlocked unless @started
      end

      log "Background cache refresh queued for #{names.count} gems."
      @condition.broadcast
      self
    end

    def prioritize(gem_name)
      @mutex.synchronize do
        return if @completed.include?(gem_name) || @in_progress.include?(gem_name)

        if @queued.include?(gem_name)
          @queue.delete(gem_name)
        else
          @queued << gem_name
          @total += 1
        end

        @queue.unshift(gem_name)
        start_workers_unlocked unless @started
      end

      log "Prioritized #{gem_name}"
      @condition.broadcast
    end

    def pending?(gem_name)
      @mutex.synchronize do
        @queued.include?(gem_name) || @in_progress.include?(gem_name)
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
        gem_name = @mutex.synchronize do
          while @queue.empty?
            @condition.wait(@mutex)
          end

          next_gem = @queue.shift
          @queued.delete(next_gem)
          @in_progress << next_gem
          next_gem
        end

        warm_cache_for_gem(gem_name)

        current = @mutex.synchronize do
          @in_progress.delete(gem_name)
          @completed << gem_name
          @completed_count += 1
        end

        log_progress(gem_name, current)
      end
    end

    def warm_cache_for_gem(gem_name)
      metadata = Gemstar::RubyGemsMetadata.new(gem_name)
      metadata.meta
      metadata.repo_uri
      Gemstar::ChangeLog.new(metadata).sections
    rescue StandardError => e
      log "Cache refresh failed for #{gem_name}: #{e.class}: #{e.message}"
    end

    def log_progress(gem_name, current)
      return unless @debug
      return unless current <= 5 || (current % 25).zero?

      log "Background cache refresh #{current}/#{@total}: #{gem_name}"
    end

    def log(message)
      @io.puts(message)
    end
  end
end
