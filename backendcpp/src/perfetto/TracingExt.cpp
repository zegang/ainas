#include "perfetto/tracing_ext.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <fstream>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace ainas::tracing {

// ------------------------------------------------------------------
// Internal state
// ------------------------------------------------------------------
namespace {

std::atomic<bool>      g_enabled{false};
std::atomic<bool>      g_flush_requested{false};
std::mutex             g_mutex;
std::ostringstream     g_buffer;
std::string            g_output_path = "/tmp/ainas-trace.perfetto";

// Track active begin events so we can write matching end events.
thread_local std::vector<std::string> g_event_stack;

int64_t nowUs() {
    return std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

int64_t processPid() {
    static int64_t pid = static_cast<int64_t>(::getpid());
    return pid;
}

int64_t threadId() {
    static thread_local int64_t tid = 0;
    if (tid == 0) {
        std::ostringstream ss;
        ss << std::this_thread::get_id();
        tid = static_cast<int64_t>(std::hash<std::string>{}(ss.str()));
    }
    return tid;
}

}  // anonymous namespace

// ------------------------------------------------------------------
// Init
// ------------------------------------------------------------------
void Init() {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_enabled.load()) return;

    g_buffer.str("");
    g_buffer.clear();
    g_buffer << R"({"traceEvents":[)" << std::endl;

    g_buffer << R"({"ph":"M","pid":)" << processPid()
             << R"(,"name":"process_name","args":{"name":"ainas-backend-cpp"}},)"
             << std::endl;
    g_buffer << R"({"ph":"M","pid":)" << processPid()
             << R"(,"name":"process_sort_index","args":{"sort_index":0}})"
             << std::endl;

    g_enabled.store(true);
    std::fprintf(stderr, "[tracing] Chrome Trace Event format started -> %s\n",
                 g_output_path.c_str());
}

// ------------------------------------------------------------------
// Runtime control
// ------------------------------------------------------------------
void SetEnabled(bool enabled) {
    if (enabled) Init();
    else FlushAndStop();
}

bool IsEnabled() { return g_enabled.load(); }

std::string& TraceOutputPath() { return g_output_path; }

void RequestFlush() { g_flush_requested.store(true); }

bool CheckAndFlush() {
    if (!g_flush_requested.load()) return false;
    g_flush_requested.store(false);
    FlushAndStop();
    return true;
}

void FlushAndStop() {
    if (!g_enabled.load()) return;
    g_enabled.store(false);

    // Close any unclosed events
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        while (!g_event_stack.empty()) {
            auto ts = nowUs();
            g_buffer << R"({"ph":"E","pid":)" << processPid()
                     << R"(,"tid":)" << threadId()
                     << R"(,"ts":)" << ts
                     << R"(,"name":")" << g_event_stack.back() << "\"}," << std::endl;
            g_event_stack.pop_back();
        }
    }

    std::string full;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_buffer << R"({})" << std::endl;
        g_buffer << R"(]})" << std::endl;
        full = g_buffer.str();
    }

    std::ofstream ofs(g_output_path, std::ios::binary);
    if (ofs) {
        ofs.write(full.data(), static_cast<std::streamsize>(full.size()));
        std::fprintf(stderr, "[tracing] Trace written to %s (%zu bytes)\n",
                     g_output_path.c_str(), full.size());
    } else {
        std::fprintf(stderr, "[tracing] Failed to write trace to %s\n",
                     g_output_path.c_str());
    }
}

// ------------------------------------------------------------------
// Block (RAII)
// ------------------------------------------------------------------
struct Block::Impl {
    std::string name_;
    int64_t     ts_;
    int64_t     pid_;
    int64_t     tid_;

    Impl(const char* cat, const char* name) : name_(name) {
        if (!g_enabled.load()) return;
        ts_  = nowUs();
        pid_ = processPid();
        tid_ = threadId();

        std::lock_guard<std::mutex> lock(g_mutex);
        g_buffer << R"({"ph":"B","cat":")" << cat
                 << R"(","name":")" << name
                 << R"(","pid":)" << pid_
                 << R"(,"tid":)" << tid_
                 << R"(,"ts":)" << ts_
                 << "}," << std::endl;
        g_event_stack.push_back(name);
    }

    ~Impl() {
        if (!g_enabled.load()) return;
        auto endTs = nowUs();
        std::lock_guard<std::mutex> lock(g_mutex);
        if (!g_event_stack.empty()) {
            g_event_stack.pop_back();
        }
        g_buffer << R"({"ph":"E","pid":)" << pid_
                 << R"(,"tid":)" << tid_
                 << R"(,"ts":)" << endTs
                 << R"(,"name":")" << name_ << "\"}," << std::endl;
    }
};

Block::Block(const char* cat, const char* name)
    : impl_(std::make_unique<Impl>(cat, name)) {}

Block::~Block() = default;

}  // namespace ainas::tracing
