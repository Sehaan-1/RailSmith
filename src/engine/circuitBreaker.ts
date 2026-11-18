export interface CircuitOutcome {
  edgeId: string;
  failed: boolean;
}

export interface CircuitMetric {
  sampleCount: number;
  errorRate: number;
}

export interface CircuitBreakerSnapshot {
  openEdgeIds: string[];
  metrics: Record<string, CircuitMetric>;
}

const WINDOW_SIZE = 20;
const MIN_SAMPLES = 5;
const ERROR_THRESHOLD = 0.5;
const RECOVER_THRESHOLD = 0.25;

/** Local equivalent of RailSmith::CircuitBreaker for API-offline previews. */
export function evaluateCircuitBreaker(
  outcomes: readonly CircuitOutcome[],
  edgeIds: readonly string[],
): CircuitBreakerSnapshot {
  const windows = new Map(edgeIds.map((id) => [id, [] as boolean[]]));
  const tripped = new Set<string>();

  for (const outcome of outcomes) {
    const window = windows.get(outcome.edgeId);
    if (!window) throw new Error(`unknown rail edge ${JSON.stringify(outcome.edgeId)}`);

    window.push(outcome.failed);
    if (window.length > WINDOW_SIZE) window.shift();

    const errorRate = window.filter(Boolean).length / window.length;
    if (window.length >= MIN_SAMPLES && errorRate >= ERROR_THRESHOLD) {
      tripped.add(outcome.edgeId);
    } else if (tripped.has(outcome.edgeId) && errorRate <= RECOVER_THRESHOLD) {
      tripped.delete(outcome.edgeId);
    }
  }

  const metrics = Object.fromEntries(
    edgeIds.map((id) => {
      const window = windows.get(id)!;
      return [id, {
        sampleCount: window.length,
        errorRate: window.length === 0 ? 0 : window.filter(Boolean).length / window.length,
      }];
    }),
  );

  return { openEdgeIds: [...tripped].sort(), metrics };
}
