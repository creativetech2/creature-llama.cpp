<script lang="ts">
	import RpcGpuRow from './RpcGpuRow.svelte';
	import { Badge } from '$lib/components/ui/badge';
	import type { RpcHostEntry } from '$lib/types';
	import { gpuHistoryKey, percentOf } from '$lib/utils/rpc-stats';

	interface Props {
		history: Record<string, number[]>;
		host: RpcHostEntry;
	}

	let { history, host }: Props = $props();

	let stats = $derived(host.stats);
	let isMaster = $derived(host.label === 'master');
	let ramPercent = $derived(stats ? percentOf(stats.ram_used_mib, stats.ram_total_mib) : null);
	let clients = $derived(stats?.rpc.clients ?? []);

	function mbps(value: number): string {
		return value >= 1000 ? `${(value / 1000).toFixed(2)} Gbps` : `${value.toFixed(0)} Mbps`;
	}
</script>

<section class="space-y-3 rounded-lg border bg-card p-4 text-card-foreground">
	<header class="flex flex-wrap items-center justify-between gap-2">
		<div class="min-w-0">
			<h2 class="truncate text-base font-semibold">
				{isMaster ? 'Master' : host.endpoint}
			</h2>

			<p class="truncate text-xs text-muted-foreground">
				{stats?.host ?? host.agent}
			</p>
		</div>

		<div class="flex flex-wrap items-center gap-1.5">
			{#if !isMaster && stats}
				{#if !stats.rpc.running}
					<Badge variant="outline">RPC server not running</Badge>
				{:else if clients.length > 0}
					<Badge variant="secondary">RPC busy &middot; {clients.join(', ')}</Badge>
				{:else}
					<Badge variant="outline">RPC idle</Badge>
				{/if}
			{/if}

			<Badge variant={host.reachable ? 'default' : 'destructive'}>
				{host.reachable ? 'Online' : 'Agent offline'}
			</Badge>
		</div>
	</header>

	{#if stats}
		<div class="space-y-2">
			{#each stats.gpus as gpu (gpu.index)}
				<RpcGpuRow {gpu} history={history[gpuHistoryKey(host.endpoint, gpu)] ?? []} />
			{:else}
				<p class="text-sm text-muted-foreground">No NVIDIA GPU reported.</p>
			{/each}
		</div>

		<dl class="grid grid-cols-3 gap-2 text-xs">
			<div>
				<dt class="text-muted-foreground">CPU</dt>

				<dd class="font-mono tabular-nums">{stats.cpu_pct ?? '-'}%</dd>
			</div>

			<div>
				<dt class="text-muted-foreground">RAM</dt>

				<dd class="font-mono tabular-nums">
					{(stats.ram_used_mib / 1024).toFixed(0)} / {(stats.ram_total_mib / 1024).toFixed(0)} GiB
					{#if ramPercent !== null}({ramPercent}%){/if}
				</dd>
			</div>

			<div>
				<dt class="text-muted-foreground">Network</dt>

				<dd class="font-mono tabular-nums">
					{#if stats.net}
						&darr; {mbps(stats.net.rx_mbps)} &uarr; {mbps(stats.net.tx_mbps)}
					{:else}
						-
					{/if}
				</dd>
			</div>
		</dl>
	{:else}
		<p class="text-sm text-muted-foreground">
			No stats from {host.agent}{host.error ? ` (${host.error})` : ''}. Start the host with the
			latest <code>start-rpc-server.ps1</code> so its stats agent runs, and allow TCP port
			{host.agent.split(':').pop()} through its firewall.
		</p>
	{/if}
</section>
