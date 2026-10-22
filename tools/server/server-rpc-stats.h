#pragma once

#include "server-http.h"

#include <string>

// GET /rpc/stats: polls the stats agent (tools/rpc/stats-agent.ps1) of this machine and of every --rpc host
// note: never queries the ggml RPC devices, a down host would abort the process
server_http_context::handler_t server_rpc_stats_make_handler(const std::string & rpc_servers);
