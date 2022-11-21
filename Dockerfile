#syntax=docker/dockerfile:1

ARG GO_VERSION="1.19"
ARG ALPINE_VERSION="3.16"
ARG XX_VERSION="1.1.2"

FROM --platform=$BUILDPLATFORM tonistiigi/xx:${XX_VERSION} AS xx

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine AS base
COPY --link --from=xx / /
ENV CGO_ENABLED=0
RUN apk add --no-cache file git
WORKDIR /src

FROM base AS version
ARG GIT_REF
RUN --mount=target=. <<EOT
  set -e
  case "$GIT_REF" in
    refs/tags/v*) version="${GIT_REF#refs/tags/}" ;;
    *) version=$(git describe --match 'v[0-9]*' --dirty='.m' --always --tags) ;;
  esac
  pkg=github.com/docker/buildkit-syft-scanner
  echo "${version}" | tee /tmp/.version
  echo "-extldflags -static -X ${pkg}/version.Version=${version} -X ${pkg}/version.SyftVersion=$(go list -mod=mod -u -m -f '{{.Version}}' 'github.com/anchore/syft')" | tee /tmp/.ldflags
EOT

FROM base as build
RUN --mount=type=bind,target=. \
    --mount=type=cache,target=/go/pkg/mod \
    go mod download
ARG TARGETPLATFORM
RUN --mount=type=bind,target=. \
    --mount=type=bind,from=version,source=/tmp/.ldflags,target=/tmp/.ldflags \
    --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache <<EOT
  set -e
  xx-go build -trimpath -ldflags "$(cat /tmp/.ldflags)" -o /usr/local/bin/syft-scanner ./cmd/syft-scanner
  xx-verify --static /usr/local/bin/syft-scanner
EOT

FROM scratch
COPY --from=build /usr/local/bin/syft-scanner /bin/syft-scanner
ENV LOG_LEVEL="warn"
ENTRYPOINT [ "/bin/syft-scanner" ]
