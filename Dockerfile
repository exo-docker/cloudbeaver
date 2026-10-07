FROM dbeaver/cloudbeaver:26.2.2

COPY conf/ /opt/cloudbeaver/conf/
COPY entrypoint.sh /opt/cloudbeaver/entrypoint.sh

WORKDIR /opt/cloudbeaver

RUN apt-get update && apt-get install -y --no-install-recommends curl jq && rm -rf /var/lib/apt/lists/* \
    && chmod +x /opt/cloudbeaver/entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=3 \
  CMD curl --fail http://localhost:8978/cloudbeaver/status || exit 1
