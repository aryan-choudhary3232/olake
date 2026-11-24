ARG GO_BUILD=cross
# Where the driver binary comes from:
#   source  compiled in this build: local builds, the test suites, images of any commit
#   dist    copied from dist/<driver>/<os>/<arch>/, built on the host by `make dist.<driver>`:
#           the release workflow, so a release image build only copies files
ARG BINARIES=source

FROM --platform=$BUILDPLATFORM golang:1.26.11-bookworm AS go-cross
FROM golang:1.26.11-bookworm AS go-target

FROM go-cross AS makefiles
WORKDIR /home/app
COPY . .
RUN mkdir /out && cp --parents Makefile $(find drivers -maxdepth 2 -name driver.mk) /out

# Build Stage. Leaves the same layout dist.<driver> does: /dist/olake and /dist/overlay/.
FROM go-${GO_BUILD} AS build-source

WORKDIR /home/app

ARG DRIVER_NAME=olake
ARG TARGETARCH

# prepare the driver
# OVERLAY_DIR tells it to stage runtime files for this image instead of onto a host (copied onto / below).
COPY --from=makefiles /out/ .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    make prepare.${DRIVER_NAME} OVERLAY_DIR=/dist/overlay \
    && make -s print.runtime-packages.${DRIVER_NAME} > /dist/runtime-packages

COPY . .
# GO_BUILD_FLAGS is single-quoted, so make (not the shell) expands it: the Makefile owns the flags.
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    GOARCH=${TARGETARCH} make dev.${DRIVER_NAME}.build OVERLAY_DIR=/dist/overlay \
    GO_OUT=/dist/olake GO_BUILD_FLAGS='$(RELEASE_GO_BUILD_FLAGS)'

# Prebuilt by `make dist.<driver>`; overlay/ and runtime-packages are always there, empty for
# every driver but db2.
FROM scratch AS build-dist
ARG DRIVER_NAME=olake
ARG TARGETOS
ARG TARGETARCH
COPY dist/${DRIVER_NAME}/${TARGETOS}/${TARGETARCH}/ /dist/

FROM build-${BINARIES} AS binaries

FROM eclipse-temurin:17-jre-noble AS runtime-base

# Install runtime dependencies. The JRE comes from the base image: installing
# Debian's openjdk-*-jre-headless pulls ca-certificates-java, whose postinst is
# a perl script, which drags in perl (2 CRITICAL CVEs with no fix in any Debian
# release) plus libnss3. Temurin ships the JRE directly and avoids both.
#
# ca-certificates-java + the symlink keep the OS trust store and the JVM's in
# sync. Debian's openjdk did this for us; Temurin instead bakes a static cacerts,
# so a private CA added to the OS store would never reach the JVM and TLS to an
# internal REST catalog, Hive metastore or self-signed S3 endpoint would fail with
# "PKIX path building failed" while the Go side (which reads /etc/ssl/certs) kept
# working. Ubuntu's ca-certificates-java, unlike Debian's, needs no perl.
# update-ca-certificates must run here: the symlink dangles until it materializes
# the keystore, and a dangling cacerts means the JVM trusts nothing at all.
# iproute2 provides ss, which the Iceberg writer uses to find a stale JVM on its port.
# Driver-only packages (db2's libxml2) are installed per image below, not here.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    ca-certificates-java \
    libpam-modules \
    libcrypt1 \
    iproute2 \
    && ln -sf /etc/ssl/certs/java/cacerts "$JAVA_HOME/lib/security/cacerts" \
    && update-ca-certificates -f \
    && rm -rf /var/lib/apt/lists/*

FROM runtime-base

# Driver metadata
ARG DRIVER_VERSION=dev
ARG DRIVER_NAME=olake

# The driver's RUNTIME_PACKAGES (Makefile fragment), empty for every driver but db2. Bind-mounted
# so the list leaves no layer, and first so a new binary does not redo the install.
RUN --mount=type=bind,from=binaries,source=/dist/runtime-packages,target=/tmp/runtime-packages \
    pkgs="$(cat /tmp/runtime-packages)" \
    && if [ -n "$pkgs" ]; then \
        apt-get update \
        && apt-get install -y --no-install-recommends $pkgs \
        && rm -rf /var/lib/apt/lists/*; \
    fi

# The driver binary, from whichever stage BINARIES picked
COPY --from=binaries --chmod=0755 /dist/olake /home/olake

# Sets the version of olake in ENV
ENV DRIVER_VERSION=${DRIVER_VERSION}

# Copy the pre-built JAR file from Maven
# First try to copy from the source location (works after Maven build)
COPY destination/iceberg/olake-iceberg-java-writer/target/olake-iceberg-java-writer-0.0.1-SNAPSHOT.jar /home/olake-iceberg-java-writer.jar

# Copy driver and destination spec files
COPY drivers/${DRIVER_NAME}/resources/spec.json /drivers/${DRIVER_NAME}/resources/spec.json
COPY destination/iceberg/resources/spec.json /destination/iceberg/resources/spec.json
COPY destination/parquet/resources/spec.json /destination/parquet/resources/spec.json

# Driver-specific runtime files staged by `make prepare.<driver>`. Empty for every driver except
# db2, which stages the IBM clidriver its cgo build links against.
COPY --from=binaries /dist/overlay/ /
RUN ldconfig

# Metadata labels
LABEL io.eggwhite.version=${DRIVER_VERSION}
LABEL io.eggwhite.name=olake/source-${DRIVER_NAME}

# Set working directory
WORKDIR /home

# Entrypoint
ENTRYPOINT ["./olake"]