FROM dbeaver/cloudbeaver:24.2.4

COPY ${PWD}/workspace /opt/cloudbeaver/workspace

WORKDIR /opt/cloudbeaver/

ENTRYPOINT ["./run-server.sh"]

# Health Check
HEALTHCHECK CMD curl --fail http://localhost:8978/cloudbeaver/status || exit 1