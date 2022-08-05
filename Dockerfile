# This file is part of REANA.
# Copyright (C) 2017, 2018, 2019, 2020, 2021 CERN.
#
# REANA is free software; you can redistribute it and/or modify it
# under the terms of the MIT License; see LICENSE file for more details.

# Install base image and its dependencies
FROM centos/python-38-centos7:latest
LABEL maintainer = "Agisilaos Kounelis agisilaos.kounelis@cern.ch"

USER root
# hadolint ignore=DL3008, DL3013, DL3015
RUN yum install -y epel-release
RUN yum update -y && \
    yum install -y \
      gcc \
      git \
      gfal2-all \
      gfal2-util \
      vim-tiny && \
    yum clean all && \
    rm -rf /var/cache/yum && \
    pip install --upgrade pip
# gfal2-python bindings
RUN curl -o /etc/yum.repos.d/gfal2-repo.repo https://dmc-repo.web.cern.ch/dmc-repo/dmc-el7.repo && \
    git clone --branch v1.12.0 https://github.com/cern-fts/gfal2-python.git && \
    cd gfal2-python/ && \
    ./ci/fedora-packages.sh && \
    cd packaging/ && \
    RPMBUILD_SRC_EXTRA_FLAGS="--without docs --without python2" make srpm && \
    yum-builddep -y python3-gfal2 && \
    pip install gfal2-python
# Certificates
RUN curl -Lo /etc/pki/tls/certs/CERN-bundle.pem https://gitlab.cern.ch/plove/rucio/-/raw/7121c7200257a4c537b56ce6e7e438f0b35c6e48/etc/web/CERN-bundle.pem
RUN curl -o /etc/yum.repos.d/EGI-trustanchors.repo https://raw.githubusercontent.com/indigo-iam/egi-trust-anchors-container/main/EGI-trustanchors.repo && \
    yum -y install ca-certificates ca-policy-egi-core

# Install dependencies
COPY requirements.txt /code/
RUN pip install --no-cache-dir -r /code/requirements.txt

# Copy cluster component source code
WORKDIR /code
COPY . /code

# Are we debugging?
ARG DEBUG=0
RUN if [ "${DEBUG}" -gt 0 ]; then pip install -e ".[debug]"; else pip install .; fi;

# Are we building with locally-checked-out shared modules?
# hadolint ignore=SC2102
RUN if test -e modules/reana-commons; then pip install -e modules/reana-commons[kubernetes] --upgrade; fi
RUN if test -e modules/reana-db; then pip install -e modules/reana-db --upgrade; fi

# Check if there are broken requirements
RUN pip check

# Set useful environment variables
ARG UWSGI_PROCESSES=2
ARG UWSGI_THREADS=2
ENV FLASK_APP=reana_workflow_controller/app.py \
    PYTHONPATH=/workdir \
    TERM=xterm \
    UWSGI_PROCESSES=${UWSGI_PROCESSES:-2} \
    UWSGI_THREADS=${UWSGI_THREADS:-2}

# Expose ports to clients
EXPOSE 5000

# Run server
# hadolint ignore=DL3025
CMD uwsgi --module reana_workflow_controller.app:app \
    --http-socket 0.0.0.0:5000 --master \
    --processes ${UWSGI_PROCESSES} --threads ${UWSGI_THREADS} \
    --stats /tmp/stats.socket \
    --wsgi-disable-file-wrapper
