# VENTISCA dedicated server image (ARQ v2 §16.4, M5). Build context = the exported server directory made by
# server/build_server.sh (ventisca_server.x86_64 with the .pck embedded + libgdsqlite.linux.template_release.x86_64.so
# + these scripts), so the image never needs Godot, templates or network access:
#   server/build_server.sh                                   # → export/server/
#   docker build -t ventisca-server -f server/Dockerfile export/server
#   docker run -d --name ventisca -p 7777:7777/udp -v ventisca-data:/data --restart unless-stopped ventisca-server
# The world (world.db + backups/) and server.cfg live in the /data volume (created from server.cfg.example on the
# first start, with a random admin token). `docker stop` = save-and-quit through the admin socket (run_server.sh).
# BASE: another registry when Docker Hub rate-limits (e.g. --build-arg BASE=public.ecr.aws/debian/debian:bookworm-slim)
ARG BASE=debian:bookworm-slim
FROM ${BASE}
# nothing to install: admin.sh talks to the admin socket through bash's /dev/tcp when netcat is missing
RUN useradd -m -d /data ventisca
WORKDIR /srv/ventisca
COPY --chown=ventisca ventisca_server.x86_64 libgdsqlite.linux.template_release.x86_64.so run_server.sh admin.sh server.cfg.example ./
RUN chmod +x ventisca_server.x86_64 run_server.sh admin.sh
USER ventisca
ENV HOME=/data VENTISCA_SERVER_CFG=/data/server.cfg
VOLUME ["/data"]
EXPOSE 7777/udp
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=6s --start-period=60s --retries=3 CMD ["/srv/ventisca/admin.sh", "status"]
ENTRYPOINT ["/srv/ventisca/run_server.sh"]
