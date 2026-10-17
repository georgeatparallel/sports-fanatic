"""Collect MLB research sources using the anonymous Parallel Search MCP."""

import argparse
import asyncio
import json
import math
import sys
import uuid
from urllib.parse import urlsplit

import httpx
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client
from mcp.shared.exceptions import McpError
from mcp.types import Implementation

ENDPOINT = "https://search.parallel.ai/mcp"
USER_AGENT = (
    "sports-fanatic-parallel-example/0.1 (+https://github.com/joestein/sports-fanatic)"
)


def positive_timeout(value):
    seconds = float(value)
    if not math.isfinite(seconds) or seconds <= 0:
        raise argparse.ArgumentTypeError("timeout must be a finite positive number")
    return seconds


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=positive_timeout, default=60.0)
    parser.add_argument(
        "--session-id",
        default=str(uuid.uuid4()),
        help="reuse this ID for related searches and page fetches",
    )
    modes = parser.add_subparsers(dest="mode", required=True)
    search = modes.add_parser("search", help="find relevant news sources")
    search.add_argument("objective", help="information to find, including freshness")
    search.add_argument("--query", action="append", required=True)
    fetch = modes.add_parser("fetch", help="read specific source pages in more detail")
    fetch.add_argument("urls", nargs="+")
    fetch.add_argument(
        "--objective", help="information to extract, up to 200 characters"
    )
    args = parser.parse_args(argv)
    if not args.session_id.strip() or len(args.session_id) > 100:
        parser.error("session ID must contain 1 to 100 characters")
    if args.mode == "search":
        if not args.objective.strip() or any(not q.strip() for q in args.query):
            parser.error("objective and queries must not be blank")
    else:
        if len(args.urls) > 20:
            parser.error("fetch accepts at most 20 URLs")
        for url in args.urls:
            try:
                parsed = urlsplit(url)
                valid = parsed.scheme in ("http", "https") and parsed.hostname
            except ValueError:
                valid = False
            if not valid:
                parser.error("fetch URLs must use HTTP or HTTPS with a hostname")
        if args.objective is not None and len(args.objective) > 200:
            parser.error("fetch objective must be at most 200 characters")
    return args


async def research(args, *, transport=None):
    """Use the real MCP client; transport is replaceable for offline HTTP tests."""
    if args.mode == "search":
        tool = "web_search"
        arguments = {"objective": args.objective, "search_queries": args.query}
    else:
        tool = "web_fetch"
        arguments = {"urls": args.urls}
        if args.objective is not None:
            arguments["objective"] = args.objective
    arguments["session_id"] = args.session_id

    # No credentials, .env files, OAuth or saved application settings are loaded.
    async with (
        asyncio.timeout(args.timeout),
        httpx.AsyncClient(
            headers={"User-Agent": USER_AGENT},
            timeout=args.timeout,
            transport=transport,
        ) as client,
        streamable_http_client(ENDPOINT, http_client=client) as streams,
        ClientSession(
            streams[0],
            streams[1],
            client_info=Implementation(
                name="sports-fanatic-parallel-example", version="0.1"
            ),
        ) as session,
    ):
        await session.initialize()
        result = await session.call_tool(tool, arguments)
        if result.isError:
            detail = "\n".join(
                block.text for block in result.content if block.type == "text"
            )
            raise RuntimeError(detail or "MCP tool returned an error")
        return {
            "session_id": args.session_id,
            "tool": tool,
            "response": (
                result.structuredContent
                if result.structuredContent is not None
                else result.model_dump(mode="json", exclude_none=True)
            ),
        }


def error_detail(error):
    if isinstance(error, BaseExceptionGroup):
        return "; ".join(error_detail(child) for child in error.exceptions)
    return str(error) or type(error).__name__


def main(argv=None):
    args = parse_args(argv)
    try:
        report = asyncio.run(research(args))
    except KeyboardInterrupt:
        print("Research cancelled.", file=sys.stderr)
        return 130
    except (
        ExceptionGroup,
        httpx.HTTPError,
        McpError,
        RuntimeError,
        TimeoutError,
        ValueError,
    ) as error:
        print(f"Research failed: {error_detail(error)}", file=sys.stderr)
        return 1
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
