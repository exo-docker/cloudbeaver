FROM dbeaver/cloudbeaver:25.0.5

COPY ${PWD}/workspace /opt/cloudbeaver/workspace

WORKDIR /opt/cloudbeaver/

ENTRYPOINT ["./run-server.sh"]

# Health Check
HEALTHCHECK CMD curl --fail http://localhost:8978/cloudbeaver/status || exit 1