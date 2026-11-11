# Dev image for the Phoenix backend. Source is bind-mounted at /app.
FROM elixir:1.19

RUN apt-get update \
 && apt-get install -y --no-install-recommends inotify-tools postgresql-client \
 && rm -rf /var/lib/apt/lists/*

ENV MIX_HOME=/opt/mix \
    HEX_HOME=/opt/hex \
    LANG=C.UTF-8

RUN mix local.hex --force \
 && mix local.rebar --force \
 && mix archive.install hex phx_new --force

WORKDIR /app
