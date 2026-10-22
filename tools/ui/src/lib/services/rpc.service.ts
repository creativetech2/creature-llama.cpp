/**
 * RpcService - Stateless API layer of the RPC tab
 *
 * Wraps /rpc/stats plus the /slots and /metrics endpoints of a loaded model.
 * No reactive state; consumed by rpcStore.
 */

import { base } from '$app/paths';
import type { ApiSlotData, RpcMetrics, RpcStatsResponse } from '$lib/types';
import { apiFetch } from '$lib/utils';
import { getAuthHeaders } from '$lib/utils/api-headers';
import { parsePrometheusMetrics } from '$lib/utils/rpc-stats';

export class RpcService {
	/** Null when the server runs without --metrics (the endpoint then answers an error). */
	static async metrics(model: string | null, signal?: AbortSignal): Promise<RpcMetrics | null> {
		const response = await fetch(`${base}${this.withModel('/metrics', model)}`, {
			headers: getAuthHeaders(),
			signal
		});

		if (!response.ok) return null;

		return parsePrometheusMetrics(await response.text());
	}

	static async slots(model: string | null, signal?: AbortSignal): Promise<ApiSlotData[]> {
		return apiFetch<ApiSlotData[]>(this.withModel('/slots', model), { authOnly: true, signal });
	}

	static async stats(signal?: AbortSignal): Promise<RpcStatsResponse> {
		return apiFetch<RpcStatsResponse>('/rpc/stats', { authOnly: true, signal });
	}

	/** Router mode addresses a loaded model with ?model=<id>, a single model server takes no query. */
	private static withModel(path: string, model: string | null): string {
		return model ? `${path}?model=${encodeURIComponent(model)}` : path;
	}
}
