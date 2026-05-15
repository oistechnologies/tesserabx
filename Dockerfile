# TesseraBX application image.
#
# Built on ortussolutions/commandbox. CommandBox installs BoxLang on
# first server start (`cfengine: "boxlang@1"` in server.json). The
# critical step is `warmup-server.sh`: it boots the server once during
# image build, which fires `onServerInitialInstall` and lays the bx-*
# server modules down into the BoxLang serverHome at
# `.engine/boxlang/WEB-INF/boxlang/modules/`. After warmup the image
# contains a fully primed serverHome; container starts are fast and
# the bx-* BIFs (encodeForHTMLAttribute, EncodeFor, GetSafeHTML, ...)
# are registered with the BoxLang runtime.
#
# We layer:
#   - PostgreSQL client tools (pg_dump) for the nightly backup task.
#   - All CommandBox-managed dependencies declared in box.json.

FROM ortussolutions/commandbox:boxlang-snapshot

ENV APP_DIR=/app \
    PORT=8080 \
    BOX_SERVER_PROFILE=production

LABEL maintainer="OIS Technologies"
LABEL repository="https://github.com/oistechnologies/tesserabx"

ENV HEALTHCHECK_URI="http://127.0.0.1:${PORT}/health"

# OS deps: PostgreSQL client tools for pg_dump in the backup task,
# tini for clean signal handling.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        postgresql-client \
        tini \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Copy the entire project so server.json is present when `box install`
# and the warmup step run. With cfengine: "boxlang@1" in server.json,
# CommandBox detects a BoxLang webroot and routes BoxLang module
# installs into the BoxLang server home.
COPY ./ ${APP_DIR}/

WORKDIR ${APP_DIR}

# Install CommandBox-managed dependencies declared in box.json,
# including devDependencies (testbox, cbdebugger, etc.). The
# `--production` flag is deferred to Phase 6 hardening when we'll
# split a separate production-targeted build.
RUN box install

# Warmup: boots the server once during build to trigger
# onServerInitialInstall (which installs the bx-* server modules into
# `.engine/boxlang/WEB-INF/boxlang/modules/`) and download the right
# Runwar jar for the BoxLang version in use. With `config/boxlang.json`
# absent and `.boxlang.json` at the project root referenced by
# `server.json`'s `engineConfigFile`, the commandbox-boxlang interceptor
# routes bx-* installs into the BoxLang server home.
RUN ${BUILD_DIR}/util/warmup-server.sh

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=60s \
    CMD curl -fsS http://localhost:${PORT}/health || exit 1

ENTRYPOINT [ "/usr/bin/tini", "--" ]

# Default command applies pending migrations (idempotent — no-op when
# nothing is pending) and then starts the server via the Ortus run.sh.
# Worker and scheduler containers share this image but override CMD in
# compose.yaml to skip migrations; the app container owns the schema
# and they consume it.
CMD [ "/app/docker/app-entrypoint.sh" ]
