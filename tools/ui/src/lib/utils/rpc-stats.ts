import type { RpcGpuStats, RpcMetrics } from '$lib/types/rpc';

/** Samples kept per sparkline: 60 polls at 2 s is two minutes. */
export const RPC_HISTORY_LENGTH = 60;

const METRIC_PREFIX = 'llamacpp:';

/**
 * Read the gauges the RPC tab shows out of Prometheus text.
 * Returns null when the text has none of them (e.g. the server runs without --metrics).
 */
export function parsePrometheusMetrics(text: string): RpcMetrics | null {
	const values = new Map<string, number>();

	for (const line of text.split('\n')) {
		if (!line.startsWith(METRIC_PREFIX)) continue;

		const [name, value] = line.trim().split(/\s+/);
		const number = Number(value);

		if (name && Number.isFinite(number)) values.set(name.slice(METRIC_PREFIX.length), number);
	}

	if (values.size === 0) return null;

	return {
		generationTokensPerSecond: values.get('predicted_tokens_seconds') ?? null,
		promptTokensPerSecond: values.get('prompt_tokens_seconds') ?? null,
		requestsDeferred: values.get('requests_deferred') ?? null,
		requestsProcessing: values.get('requests_processing') ?? null
	};
}

/** Percentage of `used` in `total`, or null when either is unknown. */
export function percentOf(used: number | null, total: number | null): number | null {
	if (used === null || total === null || total <= 0) return null;

	return Math.min(100, Math.round((used / total) * 100));
}

/** Append a sample and keep the newest `limit`. */
export function pushSample(series: number[] | undefined, value: number, limit: number): number[] {
	const next = [...(series ?? []), value];

	return next.length > limit ? next.slice(next.length - limit) : next;
}

/** SVG polyline points for a series scaled into width x height; a flat series sits at the bottom. */
export function sparklinePoints(
	series: number[],
	width: number,
	height: number,
	max: number = 100
): string {
	if (series.length < 2) return '';

	const step = width / (RPC_HISTORY_LENGTH - 1);
	const offset = (RPC_HISTORY_LENGTH - series.length) * step;

	return series
		.map((value, i) => {
			const x = offset + i * step;
			const y = height - (Math.min(Math.max(value, 0), max) / max) * height;

			return `${x.toFixed(1)},${y.toFixed(1)}`;
		})
		.join(' ');
}

/** Stable key of one GPU of one machine, used for its history. */
export function gpuHistoryKey(endpoint: string, gpu: Pick<RpcGpuStats, 'index'>): string {
	return `${endpoint}#${gpu.index}`;
}
