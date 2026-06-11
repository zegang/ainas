import logging
import json
import re
import uuid

import asyncio # Import asyncio for cancellation event
from langchain_core.messages import SystemMessage, AIMessage, AIMessageChunk, BaseMessage, ToolMessage, HumanMessage
from langgraph.graph import StateGraph, START, END
from langgraph.prebuilt import ToolNode, tools_condition
from backend.services.monitoring.prometheus import TrackNodeTime, AI_AGENT_ITERATIONS_PER_REQUEST, AI_TOOL_CALL_TOTAL, AI_TOOL_DURATION

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
            # Safety guard: prevent the agent from looping indefinitely
            if state['iterations'] >= 8:
                logger.warning("Agent reached maximum iterations (8). Terminating loop.")
                return {"messages": [AIMessage(content="I've reached my maximum reasoning steps for this request. Please try being more specific.")]}
            
            state['iterations'] += 1
            
            sys_msg = SystemMessage(content=(
                f"You are a NAS AI Assistant. Available tools: {', '.join([t.name for t in tools])}.\n\n"
                "STRICT RULES:\n"
                "1. Filenames in [Attached files] are wrapped in quotes. Use the EXACT filename string for tool arguments.\n"
                "2. To call a tool, you MUST use: <tool_call>{\"name\": \"tool_name\", \"args\": {...}}</tool_call>\n"
                "3. Once a tool provides the requested info (e.g., image explanation), STOP using tools and give the final answer.\n"
                "4. DO NOT perform extra unrequested actions or call unrelated tools like dashboards.\n"
                "5. If you already have the data in chat history, do NOT call tools again. Respond directly and concisely."
            ))
            
            # Prepare LLM input. If we just received a tool result, add a Completion Nudge.
            llm_input = [sys_msg] + state['messages']
            if state['messages'] and isinstance(state['messages'][-1], ToolMessage):
                logger.debug(f"Agent received ToolMessage: {state['messages'][-1].content}")
                # Use a specific instruction prefix that signals the end of action-taking
                llm_input.append(HumanMessage(content="[INSTRUCTION] You have received the tool data. Do not call any more tools. Summarize the information and provide your final response to the user now."))

            # Use llm_with_tools.astream instead of invoke for streaming capabilities
            full_response = None
            async for chunk in llm_with_tools.astream(llm_input):
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
                    t_name = data.get("name")
                    t_args = data.get("arguments", data.get("args", {}))
                    
                    if not t_name:
                        continue

                    # Logic to "take care" of redundant calls:
                    # Check if this exact tool has already been called in the history
                    already_called = False
                    for msg in state['messages']:
                        if isinstance(msg, AIMessage) and hasattr(msg, 'tool_calls'):
                            if any(tc['name'] == t_name and tc['args'] == t_args for tc in msg.tool_calls):
                                already_called = True
                                break
                    
                    if already_called:
                        logger.warning("Agent attempted redundant tool call for '%s'. Ignoring to break loop.", t_name)
                        continue

                    manual_calls.append({
                        "name": t_name,
                        "args": t_args,
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
            # Use ainvoke to support both sync and async tools efficiently
            result = await tool_node.ainvoke(state)
            
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