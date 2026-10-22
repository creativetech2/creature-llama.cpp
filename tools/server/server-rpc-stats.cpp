#include "server-rpc-stats.h"
#include "server-common.h"

#include <cpp-httplib/httplib.h>

#include <algorithm>
#include <cstdlib>
#include <future>
#include <sstream>

static constexpr int DEFAULT_STATS_PORT = 50053;
static constexpr int STATS_TIMEOUT_MS   = 1000;

struct rpc_stats_host {
    std::string label;
    std::string endpoint;
    std::string host;
};

static int get_stats_port() {
    const char * env = std::getenv("LLAMA_RPC_STATS_PORT");
    if (env) {
        try {
            return std::stoi(env);
        } catch (const std::exception &) {
            // fall through to the default
        }
    }
    return DEFAULT_STATS_PORT;
}

static std::vector<rpc_stats_host> parse_hosts(const std::string & rpc_servers) {
    std::vector<rpc_stats_host> hosts;
    hosts.push_back({"master", "local", "127.0.0.1"});

    std::stringstream ss(rpc_servers);
    std::string endpoint;
    while (std::getline(ss, endpoint, ',')) {
        // children get --rpc from both argv and the environment
        const bool known = std::any_of(hosts.begin(), hosts.end(), [&](const rpc_stats_host & h) { return h.endpoint == endpoint; });
        if (endpoint.empty() || known) {
            continue;
        }
        const size_t colon = endpoint.rfind(':');
        hosts.push_back({endpoint, endpoint, colon == std::string::npos ? endpoint : endpoint.substr(0, colon)});
    }
    return hosts;
}

static json fetch_stats(const rpc_stats_host & h, int port) {
    json out = {
        {"label",     h.label},
        {"endpoint",  h.endpoint},
        {"agent",     h.host + ":" + std::to_string(port)},
        {"reachable", false},
    };
    try {
        httplib::Client cli(h.host, port);
        cli.set_connection_timeout(0, STATS_TIMEOUT_MS * 1000);
        cli.set_read_timeout(0, STATS_TIMEOUT_MS * 1000);
        cli.set_write_timeout(0, STATS_TIMEOUT_MS * 1000);

        auto res = cli.Get("/stats");
        if (!res) {
            out["error"] = httplib::to_string(res.error());
        } else if (res->status != 200) {
            out["error"] = "HTTP " + std::to_string(res->status) + " " + res->body;
        } else {
            out["stats"]     = json::parse(res->body);
            out["reachable"] = true;
        }
    } catch (const std::exception & e) {
        out["error"] = e.what();
    }
    return out;
}

server_http_context::handler_t server_rpc_stats_make_handler(const std::string & rpc_servers) {
    const std::vector<rpc_stats_host> hosts = parse_hosts(rpc_servers);
    const int port = get_stats_port();

    return [hosts, port](const server_http_req &) -> server_http_res_ptr {
        // slow or dead hosts run in parallel, so the worst case stays at one timeout
        std::vector<std::future<json>> futures;
        for (const auto & h : hosts) {
            futures.push_back(std::async(std::launch::async, fetch_stats, h, port));
        }

        json list = json::array();
        for (auto & f : futures) {
            list.push_back(f.get());
        }

        auto res = std::make_unique<server_http_res>();
        res->data = safe_json_to_str({{"hosts", list}});
        return res;
    };
}
