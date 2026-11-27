# CASE 2: the driver binary is always built outside Docker, by `make dist.<driver>` (the release
# workflow, `make docker.<driver>.build`, the test suites); the image only copies it in.
# overlay/ and runtime-packages are always there, empty for every driver but db2.
FROM scratch AS binaries
ARG DRIVER_NAME=olake
ARG TARGETOS
ARG TARGETARCH
COPY dist/${DRIVER_NAME}/${TARGETOS}/${TARGETARCH}/ /dist/

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

# The driver binary, prebuilt by `make dist.<driver>`
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