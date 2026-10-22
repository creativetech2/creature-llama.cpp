<script lang="ts">
	import RpcMachineCard from '$lib/components/app/rpc/RpcMachineCard.svelte';
	import RpcNowRunning from '$lib/components/app/rpc/RpcNowRunning.svelte';
	import { rpcStore } from '$lib/stores';
	import { onMount } from 'svelte';

	onMount(() => {
		rpcStore.start();

		return () => rpcStore.stop();
	});

	let updated = $derived(
		rpcStore.lastUpdated ? new Date(rpcStore.lastUpdated).toLocaleTimeString() : null
	);
</script>

<svelte:head>
	<title>RPC · llama.cpp</title>
</svelte:head>

<div class="mx-auto h-dvh w-full max-w-6xl space-y-4 overflow-y-auto p-4 md:p-6">
	<header class="flex flex-wrap items-baseline justify-between gap-2">
		<h1 class="text-xl font-semibold">RPC pool</h1>

		<p class="text-xs text-muted-foreground">
			{#if rpcStore.error}
				<span class="text-destructive">{rpcStore.error}</span>
			{:else if updated}
				Updated {updated}, every 2 s
			{:else}
				Loading...
			{/if}
		</p>
	</header>

	<RpcNowRunning />

	<div class="grid gap-4 lg:grid-cols-2">
		{#each rpcStore.hosts as host (host.endpoint)}
			<RpcMachineCard history={rpcStore.history} {host} />
		{/each}
	</div>
</div>
