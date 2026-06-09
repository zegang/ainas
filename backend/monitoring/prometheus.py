from prometheus_client import Counter, Histogram, Summary
import time

# 1. AI Chat/Stream metrics
AI_REQUEST_DURATION = Histogram(
    'ai_request_duration_seconds', 
    'Time taken for full AI response',
    ['type']  # 'stream' or 'chat'
)

# TTFC (Time to First Chunk) metrics
AI_STREAM_TTFC = Histogram(
    'ai_stream_ttfc_seconds',
    'Latency from request start to the first yielded chunk in a stream',
    ['type']
)

# 2. AI Tool metrics
AI_TOOL_CALL_TOTAL = Counter(
    'ai_tool_calls_total', 
    'Total number of AI tool calls',
    ['tool_name']
)
AI_TOOL_DURATION = Histogram(
    'ai_tool_duration_seconds', 
    'Time spent executing specific tools',
    ['tool_name']
)

# 3. LangGraph Node metrics
AI_AGENT_NODE_DURATION = Histogram(
    'ai_agent_node_duration_seconds',
    'Time spent in each LangGraph node',
    ['node_name']
)

AI_AGENT_ITERATIONS_PER_REQUEST = Summary(
    'ai_agent_iterations_per_request',
    'Number of node loops/iterations per single user request'
)

class TrackNodeTime:
    def __init__(self, node_name: str):
        self.node_name = node_name

    def __enter__(self):
        self.start = time.perf_counter()

    def __exit__(self, exc_type, exc_val, exc_tb):
        duration = time.perf_counter() - self.start
        AI_AGENT_NODE_DURATION.labels(node_name=self.node_name).observe(duration)