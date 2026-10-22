import type { ApiSlotData } from './api';

/** One GPU as reported by the stats agent (tools/rpc/stats-agent.ps1). */
export interface RpcGpuStats {
	index: number;
	name: string;
	util_gpu: number | null;
	util_mem: number | null;
	mem_used_mib: number | null;
	mem_total_mib: number | null;
	temp_c: number | null;
	power_w: number | null;
	power_limit_w: number | null;
	sm_clock_mhz: number | null;
}

export interface RpcNetStats {
	rx_mbps: number;
	tx_mbps: number;
	link_mbps: number;
}

export interface RpcHostStats {
	host: string;
	time: string;
	gpus: RpcGpuStats[];
	cpu_pct: number | null;
	ram_used_mib: number;
	ram_total_mib: number;
	net: RpcNetStats | null;
	rpc: {
		running: boolean;
		port: number;
		/** Remote addresses currently connected to the RPC server. */
		clients: string[];
	};
}

/** One machine of the pool: the master ("local") or an --rpc host. */
export interface RpcHostEntry {
	label: string;
	endpoint: string;
	agent: string;
	reachable: boolean;
	error?: string;
	stats?: RpcHostStats;
}

export interface RpcStatsResponse {
	hosts: RpcHostEntry[];
}

/** Values read from the Prometheus /metrics text (needs --metrics). */
export interface RpcMetrics {
	promptTokensPerSecond: number | null;
	generationTokensPerSecond: number | null;
	requestsProcessing: number | null;
	requestsDeferred: number | null;
}

/** Live detail of one loaded model: its slots and metrics. */
export interface RpcModelDetail {
	slots: ApiSlotData[];
	metrics: RpcMetrics | null;
}
