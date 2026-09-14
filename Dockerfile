# syntax=docker/dockerfile:1

# The simulation in Sources/TinyFarmCore has no UI dependencies, so the exact
# same code that drives the iOS app compiles and passes its tests on Linux.
# Running it here gives us a second, non-Apple opinion on the game logic and
# catches anything that only works because of Apple's Foundation.
#
# Built on Namespace Remote Builders: layer caching is automatic, and the
# --mount=type=cache below keeps SwiftPM's build directory warm across runs.

FROM swift:6.0-noble AS test

WORKDIR /src

RUN set -x && swift --version && uname -m

# Manifest first so dependency resolution caches independently of source edits.
COPY Package.swift ./
RUN --mount=type=cache,target=/src/.build,sharing=locked \
    set -x && swift package resolve --verbose

COPY Sources ./Sources
COPY Tests ./Tests

RUN --mount=type=cache,target=/src/.build,sharing=locked \
    set -x && swift build --build-tests --verbose

RUN --mount=type=cache,target=/src/.build,sharing=locked \
    set -x && swift test --verbose

# A tiny artifact proving which commit was verified on Linux.
FROM scratch AS report
COPY --from=test /src/Package.swift /verified/Package.swift
