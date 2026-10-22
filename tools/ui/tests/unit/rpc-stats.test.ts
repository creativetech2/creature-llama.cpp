import {
	gpuHistoryKey,
	parsePrometheusMetrics,
	percentOf,
	pushSample,
	RPC_HISTORY_LENGTH,
	sparklinePoints
} from '$lib/utils/rpc-stats';
import { describe, expect, it } from 'vitest';

describe('parsePrometheusMetrics', () => {
	const text = [
		'# HELP llamacpp:prompt_tokens_seconds Average prompt throughput in tokens/s.',
		'# TYPE llamacpp:prompt_tokens_seconds gauge',
		'llamacpp:prompt_tokens_seconds 812.5',
		'llamacpp:predicted_tokens_seconds 24.25',
		'llamacpp:requests_processing 1',
		'llamacpp:requests_deferred 0',
		'llamacpp:prompt_tokens_total 1000'
	].join('\n');

	it('reads the gauges the tab shows', () => {
		expect(parsePrometheusMetrics(text)).toEqual({
			generationTokensPerSecond: 24.25,
			promptTokensPerSecond: 812.5,
			requestsDeferred: 0,
			requestsProcessing: 1
		});
	});

	it('returns null without any llamacpp metric', () => {
		expect(parsePrometheusMetrics('')).toBeNull();
		expect(parsePrometheusMetrics('{"error":"metrics disabled"}')).toBeNull();
	});

	it('leaves a missing gauge as null', () => {
		expect(parsePrometheusMetrics('llamacpp:requests_processing 2')).toEqual({
			generationTokensPerSecond: null,
			promptTokensPerSecond: null,
			requestsDeferred: null,
			requestsProcessing: 2
		});
	});

	it('ignores values that are not numbers', () => {
		expect(parsePrometheusMetrics('llamacpp:requests_processing abc')).toBeNull();
	});
});

describe('percentOf', () => {
	it('rounds to a whole percent', () => {
		expect(percentOf(1, 3)).toBe(33);
	});

	it('is null when a value is unknown or the total is empty', () => {
		expect(percentOf(null, 10)).toBeNull();
		expect(percentOf(5, null)).toBeNull();
		expect(percentOf(5, 0)).toBeNull();
	});

	it('caps at 100', () => {
		expect(percentOf(12, 10)).toBe(100);
	});
});

describe('pushSample', () => {
	it('starts a series', () => {
		expect(pushSample(undefined, 5, 3)).toEqual([5]);
	});

	it('keeps only the newest samples', () => {
		expect(pushSample([1, 2, 3], 4, 3)).toEqual([2, 3, 4]);
	});

	it('does not change its input', () => {
		const series = [1];

		pushSample(series, 2, 3);

		expect(series).toEqual([1]);
	});
});

describe('sparklinePoints', () => {
	it('draws nothing for fewer than two samples', () => {
		expect(sparklinePoints([], 100, 20)).toBe('');
		expect(sparklinePoints([50], 100, 20)).toBe('');
	});

	it('anchors the newest sample at the right edge', () => {
		const points = sparklinePoints([0, 100], 590, 20).split(' ');

		expect(points[1]).toBe('590.0,0.0');
		expect(points[0]).toBe(`${(590 - 590 / (RPC_HISTORY_LENGTH - 1)).toFixed(1)},20.0`);
	});

	it('clamps values to the scale', () => {
		expect(sparklinePoints([-5, 500], 590, 20)).toContain(',20.0');
		expect(sparklinePoints([-5, 500], 590, 20)).toContain(',0.0');
	});
});

describe('gpuHistoryKey', () => {
	it('separates the GPUs of one machine', () => {
		expect(gpuHistoryKey('192.168.1.44:50052', { index: 2 })).toBe('192.168.1.44:50052#2');
	});
});
