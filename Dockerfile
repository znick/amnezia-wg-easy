# AmneziaWG versions — bump these to update AWG.
ARG AWG_GO_VERSION=v3.1.20260828
ARG AWG_TOOLS_VERSION=v3.1.20260812

FROM docker.io/library/node:22-alpine AS build_node_modules
COPY src /app
WORKDIR /app
RUN npm ci --omit=dev &&\
    mv node_modules /node_modules

# Userspace AmneziaWG implementation
FROM docker.io/library/golang:1.25-alpine AS build_awg_go
ARG AWG_GO_VERSION
RUN apk add --no-cache git make
RUN git clone --depth 1 --branch ${AWG_GO_VERSION} https://github.com/amnezia-vpn/amneziawg-go /src
WORKDIR /src
RUN make && install -D -m 0755 amneziawg-go /out/usr/bin/amneziawg-go

# awg / awg-quick
FROM docker.io/library/alpine:3.22 AS build_awg_tools
ARG AWG_TOOLS_VERSION
RUN apk add --no-cache git make build-base linux-headers
RUN git clone --depth 1 --branch ${AWG_TOOLS_VERSION} https://github.com/amnezia-vpn/amneziawg-tools /src
WORKDIR /src/src
RUN make && make install DESTDIR=/out WITH_WGQUICK=yes WITH_BASHCOMPLETION=no WITH_SYSTEMDUNITS=no

FROM docker.io/library/alpine:3.22
HEALTHCHECK CMD /usr/bin/timeout 5s /bin/sh -c "/usr/bin/wg show | /bin/grep -q interface || exit 1" --interval=1m --timeout=5s --retries=3

RUN apk add --no-cache \
    bash \
    dumb-init \
    iproute2 \
    iptables \
    iptables-legacy \
    nodejs \
    openresolv

COPY --from=build_awg_go /out/ /
COPY --from=build_awg_tools /out/usr/bin/ /usr/bin/

# The Web UI calls wg / wg-quick and keeps configs in /etc/wireguard,
# so alias the AmneziaWG tools to the stock WireGuard names.
RUN ln -sf awg /usr/bin/wg &&\
    ln -sf awg-quick /usr/bin/wg-quick &&\
    ln -sf amneziawg-go /usr/bin/wireguard-go &&\
    mkdir -p /etc/wireguard /etc/amnezia &&\
    ln -sfn /etc/wireguard /etc/amnezia/amneziawg

COPY --from=build_node_modules /app /app
COPY --from=build_node_modules /node_modules /node_modules
COPY --from=build_node_modules /app/wgpw.sh /bin/wgpw
RUN chmod +x /bin/wgpw

# Use iptables-legacy
RUN for t in iptables iptables-restore iptables-save; do ln -sf xtables-legacy-multi /usr/sbin/$t; done

ENV DEBUG=Server,WireGuard

WORKDIR /app
CMD ["/usr/bin/dumb-init", "node", "server.js"]
