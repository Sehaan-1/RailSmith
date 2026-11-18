# frozen_string_literal: true
# typed: strict

require 'set'

module RailSmith
  # Stage 4 — resilience. Tracks live error rates per rail over a
  # sliding window; when a rail's failure share reaches the trip
  # threshold (with enough samples to be meaningful), apply! opens
  # its circuit on the graph, so Stage 3 routing automatically
  # re-routes over a redundant rail. When the error rate falls back
  # under the recover threshold, rails this breaker tripped are
  # restored — rails an operator opened by hand are never
  # resurrected.
  class CircuitBreaker
    extend T::Sig

    DEFAULT_WINDOW_SIZE = T.let(20, Integer)
    DEFAULT_MIN_SAMPLES = T.let(5, Integer)
    DEFAULT_ERROR_THRESHOLD = T.let(0.5, Float)
    DEFAULT_RECOVER_THRESHOLD = T.let(0.25, Float)

    sig do
      params(
        window_size: Integer,
        min_samples: Integer,
        error_threshold: Float,
        recover_threshold: Float
      ).void
    end
    def initialize(
      window_size: DEFAULT_WINDOW_SIZE,
      min_samples: DEFAULT_MIN_SAMPLES,
      error_threshold: DEFAULT_ERROR_THRESHOLD,
      recover_threshold: DEFAULT_RECOVER_THRESHOLD
    )
      raise ArgumentError, 'window_size must be positive' if window_size <= 0
      raise ArgumentError, 'min_samples must be positive' if min_samples <= 0
      raise ArgumentError, 'min_samples cannot exceed window_size' if min_samples > window_size
      unless (0.0..1.0).cover?(error_threshold) && (0.0..1.0).cover?(recover_threshold)
        raise ArgumentError, 'thresholds must be within 0.0..1.0'
      end
      raise ArgumentError, 'recover_threshold cannot exceed error_threshold' if recover_threshold > error_threshold

      @window_size = window_size
      @min_samples = min_samples
      @error_threshold = error_threshold
      @recover_threshold = recover_threshold
      @windows = T.let(Hash.new { |h, k| h[k] = [] }, T::Hash[String, T::Array[T::Boolean]])
      @tripped = T.let(Set.new, T::Set[String])
    end

    sig { params(edge_id: String).void }
    def record_success(edge_id)
      record(edge_id, false)
    end

    sig { params(edge_id: String).void }
    def record_failure(edge_id)
      record(edge_id, true)
    end

    sig { params(edge_id: String).returns(Integer) }
    def sample_count(edge_id)
      @windows.fetch(edge_id, []).size
    end

    sig { params(edge_id: String).returns(Float) }
    def error_rate(edge_id)
      window = @windows.fetch(edge_id, [])
      return 0.0 if window.empty?

      window.count(true).fdiv(window.size)
    end

    sig { params(edge_id: String).returns(T::Boolean) }
    def tripped?(edge_id)
      sample_count(edge_id) >= @min_samples && error_rate(edge_id) >= @error_threshold
    end

    # Opens tripped circuits on the graph and restores recovered ones.
    # Returns the ids currently held open by this breaker.
    sig { params(graph: Graph).returns(T::Array[String]) }
    def apply!(graph)
      graph.edges.each do |edge|
        if tripped?(edge.id)
          edge.health = RailHealth::CircuitOpen
          @tripped.add(edge.id)
        elsif @tripped.include?(edge.id) && error_rate(edge.id) <= @recover_threshold
          edge.health = RailHealth::Healthy
          @tripped.delete(edge.id)
        end
      end
      @tripped.to_a.sort
    end

    sig { params(edge_id: String).void }
    def reset(edge_id)
      @windows.delete(edge_id)
      @tripped.delete(edge_id)
    end

    private

    sig { params(edge_id: String, failed: T::Boolean).void }
    def record(edge_id, failed)
      window = T.must(@windows[edge_id])
      window.shift while window.size >= @window_size
      window.push(failed)
    end
  end
end
