FROM dbeaver/cloudbeaver:24.0.0

COPY ${PWD}/workspace /opt/cloudbeaver/workspace

WORKDIR /opt/cloudbeaver/

ENTRYPOINT ["./run-server.sh"]

# Health Check
HEALTHCHECK CMD curl --fail http://localhost:8978/cloudbeaver/ || exit 1