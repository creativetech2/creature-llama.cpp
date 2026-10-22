/**
 * rpcStore - Live state of the RPC tab
 *
 * Polls /rpc/stats (GPU pool machines) and the slots/metrics of the loaded models while
 * the RPC page is open. Keeps a short history per GPU for the sparklines.
 * Uses RpcService for the fetches and modelsStore for the loaded models.
 */

import { modelsStore } from './models/index.svelte';
import { serverStore } from './server.svelte';
import { RpcService } from '$lib/services/rpc.service';
import type { RpcHostEntry, RpcModelDetail } from '$lib/types';
import { gpuHistoryKey, pushSample, RPC_HISTORY_LENGTH } from '$lib/utils/rpc-stats';

const POLL_INTERVAL_MS = 2000;

class RpcStore {
	/** Slots and metrics of each loaded model; the key is '' for a single model server. */
	details = $state<Record<string, RpcModelDetail>>({});
	error = $state<string | null>(null);
	/** GPU utilisation samples keyed by gpuHistoryKey. */
	history = $state<Record<string, number[]>>({});
	hosts = $state<RpcHostEntry[]>([]);
	lastUpdated = $state<number | null>(null);

	private active = false;
	private controller: AbortController | null = null;
	private timer: ReturnType<typeof setTimeout> | null = null;

	start(): void {
		if (this.active) return;

		this.active = true;
		void this.tick();
	}

	stop(): void {
		this.active = false;
		this.controller?.abort();
		this.controller = null;

		if (this.timer) {
			clearTimeout(this.timer);
			this.timer = null;
		}
	}

	private recordHistory(hosts: RpcHostEntry[]): void {
		const next = { ...this.history };

		for (const host of hosts) {
			for (const gpu of host.stats?.gpus ?? []) {
				const key = gpuHistoryKey(host.endpoint, gpu);

				next[key] = pushSample(next[key], gpu.util_gpu ?? 0, RPC_HISTORY_LENGTH);
			}
		}

		this.history = next;
	}

	private async refreshDetails(signal: AbortSignal): Promise<void> {
		const models = serverStore.isRouterMode ? modelsStore.loadedModelIds : [null];
		const next: Record<string, RpcModelDetail> = {};

		await Promise.all(
			models.map(async (model) => {
				try {
					const [slots, metrics] = await Promise.all([
						RpcService.slots(model, signal),
						RpcService.metrics(model, signal).catch(() => null)
					]);

					next[model ?? ''] = { metrics, slots };
				} catch {
					// slots are optional (--no-slots), the model row still shows its status
				}
			})
		);

		if (!signal.aborted) this.details = next;
	}

	private async refreshStats(signal: AbortSignal): Promise<void> {
		try {
			const response = await RpcService.stats(signal);

			this.hosts = response.hosts;
			this.error = null;
			this.lastUpdated = Date.now();
			this.recordHistory(response.hosts);
		} catch (error) {
			if (signal.aborted) return;

			this.error = error instanceof Error ? error.message : String(error);
		}
	}

	private async tick(): Promise<void> {
		// no requests while the tab is in the background, the next tick re-checks
		if (document.visibilityState === 'visible') {
			const controller = new AbortController();

			this.controller = controller;

			await Promise.all([
				this.refreshStats(controller.signal),
				this.refreshDetails(controller.signal)
			]);
		}

		if (this.active) {
			this.timer = setTimeout(() => void this.tick(), POLL_INTERVAL_MS);
		}
	}
}

export const rpcStore = new RpcStore();
