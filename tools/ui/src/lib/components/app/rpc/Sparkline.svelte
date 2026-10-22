<script lang="ts">
	import { sparklinePoints } from '$lib/utils/rpc-stats';

	interface Props {
		class?: string;
		max?: number;
		values: number[];
	}

	const WIDTH = 120;
	const HEIGHT = 28;

	let { class: className = '', max = 100, values }: Props = $props();

	let points = $derived(sparklinePoints(values, WIDTH, HEIGHT, max));
</script>

<svg
	aria-hidden="true"
	class="h-7 w-full text-primary {className}"
	preserveAspectRatio="none"
	viewBox="0 0 {WIDTH} {HEIGHT}"
>
	<line class="stroke-border" x1="0" x2={WIDTH} y1={HEIGHT - 0.5} y2={HEIGHT - 0.5} />

	{#if points}
		<polyline
			fill="none"
			{points}
			stroke="currentColor"
			stroke-linejoin="round"
			stroke-width="1.5"
			vector-effect="non-scaling-stroke"
		/>
	{/if}
</svg>
