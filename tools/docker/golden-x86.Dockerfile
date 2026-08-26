# x86_64 Flutter gazdakép a golden-raszterizáció architektúra-hű méréséhez.
#
# MIÉRT LÉTEZIK: a goldeneket ezen a boxon (aarch64) vesszük fel, a merge-kaput
# adó CI viszont `ubuntu-latest` = x86_64. A `LocalFileComparator` nulla
# toleranciájú, ezért minden olyan raszterizációs eltérés, ami a két ISA között
# megmarad, CSAK a CI-ban derül ki — körönként egy ~15 perces vak kör
# (docs/LESSONS.md L486, L493).
#
# A kép a CI-vel BIT AZONOS Flutter-verziót használ; a pinnelt verziót a
# `tools/golden-x86.sh` olvassa ki a `.github/workflows/`-ból, és
# `--build-arg FLUTTER_VERSION=` -ként adja ide, hogy a kettő ne tudjon
# szétcsúszni. A verzió-paritást a `tools/tests/test_golden_x86_parity.py`
# őrzi.
FROM --platform=linux/amd64 debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils zip libglu1-mesa python3 \
    && rm -rf /var/lib/apt/lists/*

ARG FLUTTER_VERSION
RUN test -n "$FLUTTER_VERSION" \
    && curl -fsSL -o /tmp/flutter.tar.xz \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz

ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"
ENV PUB_CACHE=/pub-cache

RUN git config --global --add safe.directory '*' \
    && flutter config --no-analytics --no-cli-animations \
    && flutter precache --universal --no-android --no-ios --no-linux --no-web
