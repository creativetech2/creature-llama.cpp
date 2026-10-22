<script lang="ts">
	import { Badge } from '$lib/components/ui/badge';
	import { ServerModelStatus } from '$lib/enums';
	import { modelsStore, rpcStore, serverStore } from '$lib/stores';
	import type { ApiModelDataEntry } from '$lib/types';

	// a single model server has no model list, its one model is keyed by ''
	let entries = $derived(
		serverStore.isRouterMode
			? modelsStore.routerModels.filter(
					(model) =>
						model.status.value === ServerModelStatus.LOADED ||
						model.status.value === ServerModelStatus.LOADING ||
						model.status.value === ServerModelStatus.SLEEPING ||
						model.status.value === ServerModelStatus.FAILED
				)
			: []
	);

	function detailOf(model: ApiModelDataEntry | null) {
		return rpcStore.details[model?.id ?? ''];
	}

	function tps(value: number | null | undefined): string {
		return value === null || value === undefined ? '-' : `${value.toFixed(1)} t/s`;
	}
</script>

{#snippet row(title: string, status: string, detail: ReturnType<typeof detailOf>)}
	{@const busy = detail?.slots.filter((slot) => slot.is_processing) ?? []}

	<div class="space-y-2 rounded-md border bg-background/40 p-3">
		<div class="flex flex-wrap items-center justify-between gap-2">
			<span class="min-w-0 truncate text-sm font-medium">{title}</span>

			<Badge variant={status === ServerModelStatus.FAILED ? 'destructive' : 'secondary'}>
				{status}
			</Badge>
		</div>

		{#if detail}
			<dl class="grid grid-cols-2 gap-2 text-xs sm:grid-cols-4">
				<div>
					<dt class="text-muted-foreground">Slots busy</dt>

					<dd class="font-mono tabular-nums">{busy.length} / {detail.slots.length}</dd>
				</div>

				<div>
					<dt class="text-muted-foreground">Generation</dt>

					<dd class="font-mono tabular-nums">{tps(detail.metrics?.generationTokensPerSecond)}</dd>
				</div>

				<div>
					<dt class="text-muted-foreground">Prompt</dt>

					<dd class="font-mono tabular-nums">{tps(detail.metrics?.promptTokensPerSecond)}</dd>
				</div>

				<div>
					<dt class="text-muted-foreground">Requests</dt>

					<dd class="font-mono tabular-nums">
						{detail.metrics?.requestsProcessing ?? '-'} running &middot; {detail.metrics
							?.requestsDeferred ?? '-'} queued
					</dd>
				</div>
			</dl>

			{#if busy.length > 0}
				<ul class="space-y-1 text-xs text-muted-foreground">
					{#each busy as slot (slot.id)}
						<li class="font-mono tabular-nums">
							slot {slot.id} &middot; task {slot.id_task} &middot; {slot.next_token.n_decoded} tokens
							decoded of {slot.n_ctx} context
						</li>
					{/each}
				</ul>
			{/if}

			{#if detail.metrics === null}
				<p class="text-xs text-muted-foreground">
					Start the server with <code>--metrics</code> to see tokens per second.
				</p>
			{/if}
		{/if}
	</div>
{/snippet}

<section class="space-y-3 rounded-lg border bg-card p-4 text-card-foreground">
	<h2 class="text-base font-semibold">Now running</h2>

	{#if serverStore.isRouterMode}
		{#each entries as model (model.id)}
			{@render row(model.id, model.status.value, detailOf(model))}
		{:else}
			<p class="text-sm text-muted-foreground">
				No model is loaded. Load one in the Models tab, or send a request and it loads on demand.
			</p>
		{/each}
	{:else}
		{@render row(
			serverStore.props?.model_alias ?? 'model',
			ServerModelStatus.LOADED,
			detailOf(null)
		)}
	{/if}
</section>
