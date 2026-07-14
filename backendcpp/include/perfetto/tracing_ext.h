#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <string>

namespace ainas::tracing {

void Init();
void SetEnabled(bool enabled);
bool IsEnabled();
std::string& TraceOutputPath();
void FlushAndStop();

/// Called from the signal handler — just sets a flag.
/// The actual flush happens from the main loop via CheckAndFlush().
void RequestFlush();

/// Check-and-flush for the main loop; returns true if a flush happened.
bool CheckAndFlush();

class Block {
 public:
  Block(const char* cat, const char* name);
  ~Block();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace ainas::tracing

#if defined(AINAS_ENABLE_TRACING) && AINAS_ENABLE_TRACING

#define TRACE_INIT()             ::ainas::tracing::Init()
#define TRACE_SET_ENABLED(v)     ::ainas::tracing::SetEnabled(v)
#define TRACE_FLUSH()            ::ainas::tracing::FlushAndStop()
#define TRACE_REQUEST_FLUSH()    ::ainas::tracing::RequestFlush()
#define TRACE_CHECK_FLUSH()      ::ainas::tracing::CheckAndFlush()
#define TRACE_DURATION(cat, name) \
  ::ainas::tracing::Block _tr_block_##__LINE__{cat, name}
#define TRACE_EVENT(cat, name)                         \
  do {                                                 \
    if (::ainas::tracing::IsEnabled())                  \
      ::ainas::tracing::Block _tr_ev_##__LINE__{cat, name}; \
  } while (0)

#else

#define TRACE_INIT()             (void)0
#define TRACE_SET_ENABLED(v)     (void)0
#define TRACE_FLUSH()            (void)0
#define TRACE_REQUEST_FLUSH()    (void)0
#define TRACE_CHECK_FLUSH()      false
#define TRACE_DURATION(cat, name) (void)0
#define TRACE_EVENT(cat, name)   (void)0

#endif
