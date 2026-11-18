# frozen_string_literal: true
# typed: strict

module RailSmith
  # The outcome of one routing query: the optimal quote, the best
  # alternative (runner-up), and every rail excluded by circuit
  # breakers or missed cutoffs at query time.
  class RouteResult < T::Struct
    const :optimal, T.nilable(RouteQuote)
    const :runner_up, T.nilable(RouteQuote)
    const :exclusions, T::Array[RouteExclusion]
  end
end
