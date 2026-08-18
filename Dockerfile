FROM dbeaver/cloudbeaver:26.1.5

COPY workspace /opt/cloudbeaver/workspace

WORKDIR /opt/cloudbeaver

RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["./launch-product.sh"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl --fail http://localhost:8978/cloudbeaver/status || exit 1