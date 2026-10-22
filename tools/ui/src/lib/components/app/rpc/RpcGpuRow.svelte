<script lang="ts">
	import Sparkline from './Sparkline.svelte';
	import {
		colorLevelBgClass,
		colorLevelFromPercent,
		colorLevelTextClass
	} from '$lib/components/app/chat/ChatForm/ChatFormContextGauge/context-gauge';
	import type { RpcGpuStats } from '$lib/types';
	import { percentOf } from '$lib/utils/rpc-stats';

	interface Props {
		gpu: RpcGpuStats;
		history: number[];
	}

	let { gpu, history }: Props = $props();

	let utilPercent = $derived(gpu.util_gpu === null ? null : Math.round(gpu.util_gpu));
	let vramPercent = $derived(percentOf(gpu.mem_used_mib, gpu.mem_total_mib));

	function gib(mib: number | null): string {
		return mib === null ? '-' : (mib / 1024).toFixed(1);
	}
</script>

{#snippet bar(percent: number | null)}
	<div class="h-1.5 w-full overflow-hidden rounded-full bg-muted">
		<div
			class="h-full rounded-full transition-all duration-300 {colorLevelBgClass(
				colorLevelFromPercent(percent)
			)}"
			style="width: {percent ?? 0}%"
		></div>
	</div>
{/snippet}

<div class="space-y-2 rounded-md border bg-background/40 p-3">
	<div class="flex items-baseline justify-between gap-2">
		<span class="min-w-0 truncate text-sm font-medium">
			<span class="text-muted-foreground">#{gpu.index}</span>
			{gpu.name}
		</span>

		<span class="shrink-0 font-mono text-xs text-muted-foreground tabular-nums">
			{gpu.temp_c ?? '-'}&deg;C &middot; {gpu.power_w === null ? '-' : Math.round(gpu.power_w)} W
			{#if gpu.power_limit_w !== null}/ {Math.round(gpu.power_limit_w)} W{/if}
		</span>
	</div>

	<div class="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
		<div class="space-y-1">
			<div class="flex justify-between">
				<span class="text-muted-foreground">GPU</span>

				<span
					class="font-mono tabular-nums {colorLevelTextClass(colorLevelFromPercent(utilPercent))}"
				>
					{utilPercent ?? '-'}%
				</span>
			</div>

			{@render bar(utilPercent)}
		</div>

		<div class="space-y-1">
			<div class="flex justify-between">
				<span class="text-muted-foreground">VRAM</span>

				<span
					class="font-mono tabular-nums {colorLevelTextClass(colorLevelFromPercent(vramPercent))}"
				>
					{gib(gpu.mem_used_mib)} / {gib(gpu.mem_total_mib)} GiB
				</span>
			</div>

			{@render bar(vramPercent)}
		</div>
	</div>

	<Sparkline values={history} />
</div>
