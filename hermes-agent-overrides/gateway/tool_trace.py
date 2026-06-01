"""Helpers for rendering gateway tool progress as chat-friendly Markdown.

The gateway's legacy progress mode is line-oriented (one line per tool start).
This module keeps structured state for a turn so platforms with good Markdown
support, especially Mattermost, can show an editable trace bubble containing
reasoning snippets, assistant commentary, tool arguments, elapsed time and a
small result preview.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import json
from typing import Any


_DONE = "✅"
_FAILED = "❌"
_RUNNING = "▶️"


def format_tool_trace_duration(seconds: float | int | None) -> str:
    """Format elapsed time for a chat trace."""
    try:
        value = float(seconds or 0.0)
    except (TypeError, ValueError):
        value = 0.0
    if value < 1.0:
        return f"{max(0, int(round(value * 1000)))}ms"
    if value < 60.0:
        return f"{value:.2f}s"
    minutes = int(value // 60)
    secs = int(round(value - minutes * 60))
    if secs >= 60:
        minutes += 1
        secs -= 60
    return f"{minutes}m{secs:02d}s"


def _escape_fence(text: Any) -> str:
    """Keep user/tool text from prematurely closing Markdown fences."""
    return str(text if text is not None else "").replace("```", "`\u200b``")


def _truncate(text: str, max_chars: int) -> str:
    if max_chars and max_chars > 0 and len(text) > max_chars:
        return text[: max_chars - 12].rstrip() + "\n… truncated"
    return text


def _json_block(value: Any, *, max_chars: int) -> str:
    try:
        text = json.dumps(value, ensure_ascii=False, indent=2, default=str)
    except TypeError:
        text = str(value)
    return _truncate(_escape_fence(text), max_chars)


def _command_block(tool_name: str, args: dict[str, Any] | None, *, max_chars: int) -> tuple[str, str] | None:
    args = args or {}
    if tool_name == "terminal" and args.get("command"):
        return "bash", _truncate(_escape_fence(args.get("command")), max_chars)
    if tool_name == "execute_code" and args.get("code"):
        return "python", _truncate(_escape_fence(args.get("code")), max_chars)
    if tool_name == "browser_console" and args.get("expression"):
        return "javascript", _truncate(_escape_fence(args.get("expression")), max_chars)
    if tool_name == "browser_type" and args.get("text"):
        return "text", _truncate(_escape_fence(args.get("text")), max_chars)
    return None


@dataclass
class ToolTraceEntry:
    call_id: str
    tool_name: str
    args: dict[str, Any] | None = field(default_factory=dict)
    status: str = "running"
    duration: float | None = None
    is_error: bool = False
    result_preview: str | None = None


class GatewayToolTraceFormatter:
    """Stateful Markdown renderer for a single gateway turn."""

    def __init__(
        self,
        *,
        platform: str = "mattermost",
        max_arg_chars: int = 8000,
        max_result_chars: int = 1200,
        max_reasoning_chars: int = 1600,
        max_output_chars: int = 1600,
    ) -> None:
        self.platform = platform
        self.max_arg_chars = max_arg_chars
        self.max_result_chars = max_result_chars
        self.max_reasoning_chars = max_reasoning_chars
        self.max_output_chars = max_output_chars
        self.entries: list[ToolTraceEntry] = []
        self._by_id: dict[str, ToolTraceEntry] = {}
        self._reasoning: list[str] = []
        self._assistant_outputs: list[str] = []

    def add_reasoning(self, text: str | None) -> None:
        text = str(text or "").strip()
        if text:
            self._reasoning.append(text)

    def add_assistant_output(self, text: str | None) -> None:
        text = str(text or "").strip()
        if text:
            self._assistant_outputs.append(text)

    def tool_started(self, *, call_id: str | None, tool_name: str, args: dict[str, Any] | None = None) -> None:
        call_id = str(call_id or f"{tool_name}:{len(self.entries) + 1}")
        entry = ToolTraceEntry(call_id=call_id, tool_name=str(tool_name or "tool"), args=args or {})
        self.entries.append(entry)
        self._by_id[call_id] = entry

    def tool_completed(
        self,
        *,
        call_id: str | None = None,
        tool_name: str | None = None,
        duration: float | int | None = None,
        is_error: bool = False,
        result: Any = None,
    ) -> None:
        entry = self._resolve_entry(call_id=call_id, tool_name=tool_name)
        if entry is None:
            # Completion without a matching start should still leave evidence.
            self.tool_started(call_id=call_id, tool_name=tool_name or "tool", args={})
            entry = self.entries[-1]
        entry.status = "failed" if is_error else "completed"
        entry.duration = float(duration or 0.0)
        entry.is_error = bool(is_error)
        preview = str(result if result is not None else "").strip()
        if preview:
            entry.result_preview = _truncate(_escape_fence(preview), self.max_result_chars)

    def _resolve_entry(self, *, call_id: str | None, tool_name: str | None) -> ToolTraceEntry | None:
        if call_id and str(call_id) in self._by_id:
            return self._by_id[str(call_id)]
        for entry in reversed(self.entries):
            if entry.status == "running" and (tool_name is None or entry.tool_name == tool_name):
                return entry
        for entry in reversed(self.entries):
            if tool_name is None or entry.tool_name == tool_name:
                return entry
        return None

    def render(self) -> str:
        parts: list[str] = ["🛠️ **Tool trace**"]
        if self._reasoning:
            parts.append(self._render_text_section("💭 **Model thinking**", self._reasoning, self.max_reasoning_chars))
        if self._assistant_outputs:
            parts.append(self._render_text_section("📝 **Model output**", self._assistant_outputs, self.max_output_chars))
        if self.entries:
            parts.append("\n".join(self._render_entry(i, entry) for i, entry in enumerate(self.entries, 1)))
        return "\n\n".join(part for part in parts if part)

    def _render_text_section(self, title: str, chunks: list[str], max_chars: int) -> str:
        text = "\n\n".join(chunks[-3:])
        text = _truncate(_escape_fence(text), max_chars)
        return f"{title}\n```text\n{text}\n```"

    def _render_entry(self, index: int, entry: ToolTraceEntry) -> str:
        if entry.status == "running":
            status = f"{_RUNNING} running"
        elif entry.is_error:
            status = f"{_FAILED} {format_tool_trace_duration(entry.duration)}"
        else:
            status = f"{_DONE} {format_tool_trace_duration(entry.duration)}"

        lines = [f"{index}. {self._tool_emoji(entry.tool_name)} `{entry.tool_name}` — {status}"]
        command = _command_block(entry.tool_name, entry.args, max_chars=self.max_arg_chars)
        if command is not None:
            lang, body = command
            lines.append(f"```{lang}\n{body}\n```")
        if entry.args:
            lines.append(f"```json\n{_json_block(entry.args, max_chars=self.max_arg_chars)}\n```")
        if entry.result_preview:
            lines.append(f"Result:\n```text\n{entry.result_preview}\n```")
        return "\n".join(lines)

    @staticmethod
    def _tool_emoji(tool_name: str) -> str:
        if tool_name in {"terminal", "process"}:
            return "🖥️"
        if tool_name in {"execute_code"}:
            return "🐍"
        if tool_name.startswith("browser"):
            return "🌐"
        if tool_name in {"read_file", "write_file", "patch", "search_files"}:
            return "📄"
        if tool_name in {"web_search", "web_extract", "x_search"}:
            return "🔎"
        return "⚙️"
