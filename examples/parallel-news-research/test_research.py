"""Offline tests through the actual MCP SDK and HTTP request boundary."""

import asyncio
import contextlib
import io
import json
import unittest
from unittest.mock import patch

import httpx
import research

SESSION = "bf89a38c-b73b-411f-bc0a-2c6cec2ae1d3"
SOURCE = {
    "url": "https://www.mlb.com/news/example-player-update",
    "title": "Player availability update",
    "publish_date": "2026-10-16",
    "excerpts": ["The manager confirmed the player is available tonight."],
}


class MCPTransport(httpx.MockTransport):
    def __init__(self, failure=None, text_only=False):
        self.requests = []
        self.failure = failure
        self.text_only = text_only
        self.call_started = asyncio.Event()
        self.closed = False
        super().__init__(self.respond)

    async def respond(self, request):
        payload = json.loads(request.content)
        self.requests.append((request, payload))
        method = payload["method"]
        if method == "notifications/initialized":
            return httpx.Response(202)
        if method == "initialize":
            result = {
                "protocolVersion": payload["params"]["protocolVersion"],
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "offline-fixture", "version": "1"},
            }
        elif method == "tools/list":
            result = {
                "tools": [
                    {"name": name, "inputSchema": {"type": "object"}}
                    for name in ("web_search", "web_fetch")
                ]
            }
        elif method == "tools/call":
            self.call_started.set()
            if self.failure == "wait":
                await asyncio.Event().wait()
            if self.failure == "http":
                return httpx.Response(503, text="service unavailable")
            if self.failure == "read_timeout":
                raise httpx.ReadTimeout("read timed out", request=request)
            if self.failure == "rpc":
                return httpx.Response(
                    200,
                    json={
                        "jsonrpc": "2.0",
                        "id": payload["id"],
                        "error": {"code": -32602, "message": "Invalid tool arguments"},
                    },
                )
            if self.failure == "tool":
                result = {
                    "isError": True,
                    "content": [
                        {"type": "text", "text": "Quota reached. Retry later."}
                    ],
                }
            else:
                data = {"results": [SOURCE], "session_id": SESSION}
                result = {"content": [{"type": "text", "text": json.dumps(data)}]}
                if not self.text_only:
                    result["structuredContent"] = data
        else:
            raise AssertionError(f"Unexpected MCP method: {method}")
        return httpx.Response(
            200, json={"jsonrpc": "2.0", "id": payload["id"], "result": result}
        )

    async def aclose(self):
        self.closed = True
        await super().aclose()


def search_args(*extra):
    return research.parse_args(
        [
            "--session-id",
            SESSION,
            *extra,
            "search",
            "Find confirmed current player availability",
            "--query",
            "MLB player availability update",
            "--query",
            "MLB injury latest news",
        ]
    )


class CallerTests(unittest.IsolatedAsyncioTestCase):
    async def test_search_and_fetch_preserve_sources_and_session(self):
        modes = [
            (
                search_args(),
                "web_search",
                {
                    "objective": "Find confirmed current player availability",
                    "search_queries": [
                        "MLB player availability update",
                        "MLB injury latest news",
                    ],
                    "session_id": SESSION,
                },
            ),
            (
                research.parse_args(
                    [
                        "--session-id",
                        SESSION,
                        "fetch",
                        SOURCE["url"],
                        "--objective",
                        "Find the confirmed availability and date",
                    ]
                ),
                "web_fetch",
                {
                    "urls": [SOURCE["url"]],
                    "objective": "Find the confirmed availability and date",
                    "session_id": SESSION,
                },
            ),
        ]
        for args, tool, expected in modes:
            with self.subTest(tool=tool):
                transport = MCPTransport()
                with patch.dict(
                    "os.environ",
                    {"PARALLEL_API_KEY": "unused", "EXA_API_KEY": "unused"},
                ):
                    output = await research.research(args, transport=transport)
                self.assertEqual(output["response"]["results"], [SOURCE])
                self.assertEqual(output["session_id"], SESSION)
                self.assertEqual(output["tool"], tool)
                calls = []
                for request, payload in transport.requests:
                    self.assertEqual(str(request.url), "https://search.parallel.ai/mcp")
                    self.assertEqual(request.headers["user-agent"], research.USER_AGENT)
                    self.assertNotIn("authorization", request.headers)
                    if payload["method"] == "tools/call":
                        calls.append(payload["params"])
                self.assertEqual(calls, [{"name": tool, "arguments": expected}])
                self.assertTrue(transport.closed)

    async def test_text_only_response_is_retained(self):
        output = await research.research(
            search_args(), transport=MCPTransport(text_only=True)
        )
        text = output["response"]["content"][0]["text"]
        self.assertEqual(json.loads(text)["results"][0], SOURCE)

    async def test_tool_rpc_and_transport_failures_are_visible(self):
        for failure, expected in [
            ("tool", "Quota reached"),
            ("rpc", "Invalid tool arguments"),
            ("http", "503"),
            ("read_timeout", "read timed out"),
        ]:
            with self.subTest(failure=failure):
                transport = MCPTransport(failure=failure)
                with self.assertRaises(Exception) as caught:
                    await research.research(search_args(), transport=transport)
                self.assertIn(expected, research.error_detail(caught.exception))
                self.assertTrue(transport.closed)
                self.assertEqual(
                    sum(p["method"] == "tools/call" for _, p in transport.requests), 1
                )

    async def test_total_timeout_closes_client(self):
        transport = MCPTransport(failure="wait")
        with self.assertRaises(TimeoutError):
            await research.research(
                search_args("--timeout", "0.1"), transport=transport
            )
        self.assertTrue(transport.call_started.is_set())
        self.assertTrue(transport.closed)

    async def test_cancellation_propagates_and_closes_client(self):
        transport = MCPTransport(failure="wait")
        task = asyncio.create_task(
            research.research(search_args(), transport=transport)
        )
        await asyncio.wait_for(transport.call_started.wait(), timeout=2)
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task
        self.assertTrue(transport.closed)


class CLITests(unittest.TestCase):
    def run_cli(self, failure=None):
        transport = MCPTransport(failure=failure)
        original = research.research

        async def offline(args):
            return await original(args, transport=transport)

        stdout, stderr = io.StringIO(), io.StringIO()
        with (
            patch.object(research, "research", side_effect=offline),
            contextlib.redirect_stdout(stdout),
            contextlib.redirect_stderr(stderr),
        ):
            status = research.main(
                ["--session-id", SESSION, "search", "MLB news", "--query", "MLB news"]
            )
        return status, stdout.getvalue(), stderr.getvalue()

    def test_cli_outputs_source_json(self):
        status, stdout, stderr = self.run_cli()
        self.assertEqual(status, 0)
        self.assertEqual(stderr, "")
        self.assertEqual(json.loads(stdout)["response"]["results"], [SOURCE])

    def test_cli_tool_error_is_nonzero_without_success_output(self):
        status, stdout, stderr = self.run_cli(failure="tool")
        self.assertEqual(status, 1)
        self.assertEqual(stdout, "")
        self.assertIn("Quota reached", stderr)

    def test_invalid_inputs_fail_before_network(self):
        invalid = [
            ["--timeout", "nan", "search", "news", "--query", "news"],
            ["--timeout", "0", "search", "news", "--query", "news"],
            ["--session-id", "x" * 101, "fetch", SOURCE["url"]],
            ["search", " ", "--query", "news"],
            ["search", "news", "--query", " "],
            ["fetch", "file:///etc/passwd"],
            ["fetch", "https://["],
            ["fetch", *([SOURCE["url"]] * 21)],
            ["fetch", SOURCE["url"], "--objective", "x" * 201],
        ]
        for argv in invalid:
            with self.subTest(argv=argv), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as caught:
                    research.parse_args(argv)
                self.assertEqual(caught.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
