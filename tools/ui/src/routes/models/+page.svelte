<script lang="ts">
	import { RefreshCw } from '@lucide/svelte';
	import ModelsManager from '$lib/components/app/models/ModelsManager/ModelsManager.svelte';
	import { Button } from '$lib/components/ui/button';
	import { modelsStore, serverStore } from '$lib/stores';
	import { apiFetch } from '$lib/utils';
	import { onMount } from 'svelte';

	let isRescanning = $state(false);
	let rescanError = $state<string | null>(null);

	onMount(() => {
		void modelsStore.fetchRouterModels();
	});

	/** The router re-reads its models folder and preset file on GET /models?reload=1. */
	async function rescan() {
		isRescanning = true;
		rescanError = null;

		try {
			await apiFetch('/models?reload=1', { authOnly: true });
			await modelsStore.fetchRouterModels();
		} catch (error) {
			rescanError = error instanceof Error ? error.message : String(error);
		} finally {
			isRescanning = false;
		}
	}
</script>

<svelte:head>
	<title>Models · llama.cpp</title>
</svelte:head>

<div class="mx-auto flex h-dvh w-full max-w-7xl flex-col gap-3 p-4 md:p-6">
	<header class="flex flex-wrap items-baseline justify-between gap-2">
		<h1 class="text-xl font-semibold">Models</h1>

		<p class="text-xs text-muted-foreground">
			{#if serverStore.isRouterMode}
				One model is loaded at a time across the RPC pool: loading another unloads the current one.
			{:else}
				This server runs a single model. Start it without <code>-m</code> (router mode) to manage models
				here.
			{/if}
		</p>
	</header>

	{#if rescanError}
		<p class="text-sm text-destructive">{rescanError}</p>
	{/if}

	<ModelsManager class="min-h-0 flex-1">
		{#snippet toolbarEnd()}
			{#if serverStore.isRouterMode}
				<Button
					class="gap-1.5"
					disabled={isRescanning}
					onclick={rescan}
					size="sm"
					variant="tertiary"
				>
					<RefreshCw class="h-3.5 w-3.5 {isRescanning ? 'animate-spin' : ''}" />

					Rescan folder
				</Button>
			{/if}
		{/snippet}
	</ModelsManager>
</div>
