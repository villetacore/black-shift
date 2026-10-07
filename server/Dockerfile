# Black Shift game server: an OTP release (Erlang runtime included) on a slim Debian base.
#   docker build -t blackshift-server server
#   docker run -p 7777:7777 -v blackshift-data:/data blackshift-server

# Pinned by digest so the build stage stays on the same Debian release as the runtime stage.
ARG ELIXIR_IMAGE=elixir:1.18-otp-27-slim@sha256:1dda2077640e381b35cf005bc6567c41e7ee26243c7b0c9e4b602fcccf68675f
ARG RUNTIME_IMAGE=debian:bookworm-slim

FROM ${ELIXIR_IMAGE} AS build
ENV MIX_ENV=prod
WORKDIR /src
COPY mix.exs ./
COPY config config
COPY lib lib
COPY priv priv
COPY rel rel
RUN mix compile --warnings-as-errors && mix release --path /release

FROM ${RUNTIME_IMAGE}
RUN apt-get update \
 && apt-get install -y --no-install-recommends libstdc++6 libncurses6 locales ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen \
 && useradd --system --create-home --home-dir /app blackshift \
 && mkdir /data && chown blackshift /data
ENV LANG=en_US.UTF-8 \
    BS_BIND=0.0.0.0 \
    BS_PORT=7777 \
    BS_DB_DIR=/data/mnesia \
    RELEASE_NODE=blackshift@localhost
WORKDIR /app
COPY --from=build --chown=blackshift /release ./
USER blackshift
VOLUME /data
EXPOSE 7777/tcp
# The game protocol greets every new connection, so an open port means the server is serving.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/7777' || exit 1
CMD ["/app/bin/blackshift", "start"]
