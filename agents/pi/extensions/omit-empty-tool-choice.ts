import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasTools(payload: Record<string, unknown>): boolean {
  const tools = payload.tools;
  return Array.isArray(tools) && tools.length > 0;
}

/**
 * Pi summarization sets toolChoice "none" even when no tools are sent.
 * xAI's OpenAI-Responses API rejects that with:
 * "A tool_choice was set on the request but no tools were specified."
 * Drop tool_choice unless tools are actually present.
 */
export default function omitEmptyToolChoice(pi: ExtensionAPI) {
  pi.on("before_provider_request", (event) => {
    const payload = event.payload;
    if (!isRecord(payload)) return undefined;
    if (!("tool_choice" in payload)) return undefined;
    if (hasTools(payload)) return undefined;

    const next = { ...payload };
    delete next.tool_choice;
    return next;
  });
}
