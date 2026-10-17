# MLB news research with Parallel Search MCP

Find current player, team and injury coverage with source URLs and excerpts using
[Parallel Search MCP](https://docs.parallel.ai/integrations/mcp/search-mcp).
Anonymous search uses Fast mode and needs no account or API key. This standalone
Python example is useful for collecting source material before writing a scouting
report or investigating a news item. It prints JSON and does not generate a report,
classify articles, or store them in Sports Fanatic. The application's Exa-backed
chatbot and scouting pipelines keep their existing configuration.

## Setup

Use Python 3.11 or later. From the repository root:

```bash
python3 -m venv /tmp/sports-fanatic-research-venv
/tmp/sports-fanatic-research-venv/bin/python -m pip install -r examples/parallel-news-research/requirements.txt
```

Phoenix, PostgreSQL, the Python bridge and `.env` are not needed. The client sends
requests directly to `https://search.parallel.ai/mcp`, identifies itself as the
Sports Fanatic example, and does not load API keys or saved credentials. Standard
HTTP proxy and TLS certificate environment settings are honored.

## Search for current coverage

Generate an ID once for a research task and reuse it when reading related pages:

```bash
export MLB_RESEARCH_SESSION="$(python3 -c 'import uuid; print(uuid.uuid4())')"
/tmp/sports-fanatic-research-venv/bin/python examples/parallel-news-research/research.py \
  --session-id "$MLB_RESEARCH_SESSION" search \
  'Find the latest Aaron Judge injury and availability updates from MLB and team reporting. Prefer dated primary sources.' \
  --query 'Aaron Judge latest injury update' \
  --query 'Aaron Judge availability site:mlb.com'
```

Change the player, team, objective and queries to match your research. Use two or
three related queries for one objective. The JSON includes the session ID, tool
name and server response, including source URLs, publication dates when available,
excerpts and any warnings. An empty results list means no sources were returned.
Check dates and original sources before treating an injury or lineup claim as
current; excerpts are source material, not a verified medical or lineup decision.

## Read a source page

Search excerpts are often enough. Fetch a specific page when you need exact
wording or more detail. Replace the URL below with one from your search results:

```bash
/tmp/sports-fanatic-research-venv/bin/python examples/parallel-news-research/research.py \
  --session-id "$MLB_RESEARCH_SESSION" fetch 'https://www.mlb.com/yankees/news' \
  --objective 'Find dated player availability updates and distinguish confirmed news from speculation.'
```

Fetch accepts up to 20 HTTP/HTTPS URLs and an optional objective of at most 200
characters. It returns focused excerpts, with live fetching enabled by the server
default. It does not request full-page content. Keep the same session ID across
related searches and fetches; start a new ID only for a new research task. If you
omit `--session-id`, the command generates one and includes it in the output.

## Failures and offline checks

The free anonymous service has rate limits. On a quota response, wait as directed
by the service; keep the same research session ID. Some pages may be unavailable
or return extraction errors, which remain visible in the server response.

The command exits with status 1 on a tool, transport or timeout error and prints
the reason to stderr. The default total timeout is 60 seconds; change it with
`--timeout 90` before the subcommand. Ctrl-C cancels the request. Review warnings
and per-page errors even when the command succeeds.

Run the example's offline HTTP/MCP tests without contacting Parallel:

```bash
/tmp/sports-fanatic-research-venv/bin/python -m unittest discover \
  -s examples/parallel-news-research -p 'test_*.py' -v
```
