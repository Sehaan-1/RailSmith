# frozen_string_literal: true
# typed: strict

module RailSmith
  # Live health of a rail. The starter sketch modeled this as a
  # boolean; three states let Stage 4's circuit breakers express a
  # degraded-but-usable rail (routed at a penalty) alongside a fully
  # tripped one.
  class RailHealth < T::Enum
    enums do
      Healthy = new('HEALTHY')
      Degraded = new('DEGRADED')
      CircuitOpen = new('CIRCUIT_OPEN')
    end
  end
end
