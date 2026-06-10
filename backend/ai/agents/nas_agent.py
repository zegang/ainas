import logging
import json
import re
import uuid

import asyncio # Import asyncio for cancellation event
from langchain_core.messages import SystemMessage, AIMessage, AIMessageChunk, BaseMessage
from langgraph.graph import StateGraph, START
from langgraph.prebuilt import ToolNode, tools_condition
from backend.monitoring.prometheus import TrackNodeTime, AI_AGENT_ITERATIONS_PER_REQUEST, AI_TOOL_CALL_TOTAL, AI_TOOL_DURATION

logger = logging.getLogger(__name__)

def create_nas_agent(llm, tools):
    llm_with_tools = llm.bind_tools(tools)

    async def call_agent(state: dict): # State is a dict
        with TrackNodeTime("agent"):
            logger.info("--- Entering Node: 'agent' ---")
            
            # Check for cancellation at the start of the node
            if state.get('cancellation_event') and state['cancellation_event'].is_set():
                logger.info("Agent node: Cancellation event detected.")
                raise asyncio.CancelledError("Agent processing cancelled.")

            state.setdefault('iterations', 0)
            state['iterations'] += 1
            
            filenames = state.get('filenames', [])
            nas_context = f"\n\n[NAS CONTEXT]: {', '.join([f'\"{f}\"' for f in filenames])}" if filenames else ""

            sys_msg = SystemMessage(content=(
            "STRICT RULES:\n"
            "1. Filenames in [NAS CONTEXT] are wrapped in quotes (e.g., \"file with spaces.png\"). "
            "When calling tools, use the EXACT content inside those quotes. "
            "Do not truncate, modify, or summarize the filename or path.\n"
            "2. If multiple files are provided, ensure you use the one the user is explicitly asking about."
            "\n3. To call a tool, use the following format: <tool_call>{\"name\": \"tool_name\", \"arguments\": {\"arg\": \"val\"}}</tool_call>"
            f"{nas_context}"
        ))
            
            # Use llm_with_tools.astream instead of invoke for streaming capabilities
            full_response = None
            async for chunk in llm_with_tools.astream([sys_msg] + state['messages']):
                # Check for cancellation during streaming
                if state.get('cancellation_event') and state['cancellation_event'].is_set():
                    logger.info("Agent node: Cancellation event detected during LLM stream.")
                    raise asyncio.CancelledError("Agent LLM stream cancelled.")
                
                # Defensive check: only merge if chunk is a valid message type
                if isinstance(chunk, BaseMessage):
                    if full_response is None:
                        full_response = chunk
                    else:
                        full_response += chunk
            
            responds = full_response or AIMessage(content="")
        
        # Fallback mechanism: Manually parse tool calls from content if structured tool_calls are missing
        if not (hasattr(responds, "tool_calls") and responds.tool_calls) and responds.content and "<tool_call>" in responds.content:
            logger.info("Structured tool_calls missing. Attempting manual parse from content tags.")
            # Regex to capture JSON content inside <tool_call> tags
            tool_call_regex = r"<tool_call>\s*(.*?)\s*</tool_call>"
            matches = re.findall(tool_call_regex, responds.content, re.DOTALL)
            
            manual_calls = []
            for m in matches:
                try:
                    # Clean common artifacts (extra braces, triple braces, etc.)
                    cleaned_json = m.strip()
                    # Iteratively remove unbalanced trailing braces instead of all of them
                    while cleaned_json.count('{') < cleaned_json.count('}') and cleaned_json.endswith('}'):
                        cleaned_json = cleaned_json[:-1].strip()
                    
                    data = json.loads(cleaned_json)
                    manual_calls.append({
                        "name": data.get("name"),
                        "args": data.get("arguments", data.get("args", {})),
                        "id": f"call_{uuid.uuid4().hex[:12]}", # Required for ToolNode execution
                        "type": "tool_call"
                    })
                except Exception as e:
                    logger.warning("Manual tool call parsing failed for: %s. Error: %s", m, e)
            
            if manual_calls:
                responds.tool_calls = manual_calls
                # Remove the parsed tool calls from the content to avoid displaying raw tags to the user
                responds.content = re.sub(tool_call_regex, "", responds.content, flags=re.DOTALL).strip()
                logger.info("Successfully recovered %d tool calls from content tags.", len(manual_calls))

        if hasattr(responds, "tool_calls") and responds.tool_calls:
            for tool_call in responds.tool_calls:
                logger.info("Agent requesting tool: %s with args: %s", tool_call['name'], tool_call['args'])
                AI_TOOL_CALL_TOTAL.labels(tool_name=tool_call['name']).inc()
        else:
            logger.info("Agent final response: %s", responds.content)
            # Record final iteration count when agent finishes
            AI_AGENT_ITERATIONS_PER_REQUEST.observe(state.get('iterations', 1))
            
        return {"messages": [responds]}

    async def call_tools_node(state: dict): # State is a dict
        with TrackNodeTime("tools"):
            logger.info("--- Entering Node: 'tools' ---")
            
            # Check for cancellation at the start of the node
            if state.get('cancellation_event') and state['cancellation_event'].is_set():
                logger.info("Tools node: Cancellation event detected.")
                raise asyncio.CancelledError("Tools processing cancelled.")

            tool_node = ToolNode(tools)
            # ToolNode.invoke is synchronous. Run in a thread to avoid blocking the event loop.
            result = await asyncio.to_thread(tool_node.invoke, state)
            
            if state.get('cancellation_event') and state['cancellation_event'].is_set():
                logger.info("Tools node: Cancellation event detected after tool invocation.")
                raise asyncio.CancelledError("Tools processing cancelled.")
            
            return result

    # LangGraph's StateGraph can work with a simple dict for state.
    # We'll pass the cancellation_event in this dict.
    workflow = StateGraph(dict) 
    workflow.add_node("agent", call_agent)
    workflow.add_node("tools", call_tools_node)
    workflow.add_edge(START, "agent")
    workflow.add_conditional_edges("agent", tools_condition)
    workflow.add_edge("tools", "agent")
    return workflow.compile()