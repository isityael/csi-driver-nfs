# Copyright 2020 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM dhi.io/debian-base:trixie-debian13-dev@sha256:5c45913e72c90581fc4cca57c3a7cd7dcac2d9fa44fce24fe4cfa342e5ccb7a6

ARG ARCH
ARG binary=./bin/${ARCH}/nfsplugin
COPY ${binary} /nfsplugin

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates mount netbase nfs-common && \
    rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/nfsplugin"]
