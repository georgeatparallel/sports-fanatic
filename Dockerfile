# Build stage
FROM elixir:1.17-otp-27-slim AS build

ENV MIX_ENV=prod

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    npm \
    && rm -rf /var/lib/apt/lists/*

COPY mix.exs mix.lock ./
COPY config/config.exs config/prod.exs config/runtime.exs config/
COPY lib lib
COPY priv priv
COPY assets assets

RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only prod && \
    mix assets.deploy && \
    mix compile && \
    mix phx.gen.release && \
    mix release

# Runtime stage
FROM debian:bookworm-slim AS runtime

ENV LANG=C.UTF-8 \
    MIX_ENV=prod \
    PHX_SERVER=true

RUN apt-get update && apt-get install -y --no-install-recommends \
    libstdc++6 \
    openssl \
    libncurses5 \
    locales \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN adduser --disabled-password --gecos '' appuser

WORKDIR /app
COPY --from=build --chown=appuser:appuser /app/_build/prod/rel/sports_fanatic ./
COPY --chown=appuser:appuser entrypoint.sh ./

USER appuser

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s \
    CMD curl -f http://localhost:4000/health || exit 1

CMD ["./entrypoint.sh"]
