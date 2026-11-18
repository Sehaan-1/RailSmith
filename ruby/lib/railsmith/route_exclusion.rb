# frozen_string_literal: true
# typed: strict

module RailSmith
  # A rail left out of a routing query, with the reason why.
  class RouteExclusion < T::Struct
    const :edge_id, String
    const :reason, ExclusionReason
  end
end
