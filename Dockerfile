FROM dbeaver/cloudbeaver

COPY ${PWD}/workspace /opt/cloudbeaver/workspace

WORKDIR /opt/cloudbeaver/

ENTRYPOINT ["./run-server.sh"]

# Health Check
HEALTHCHECK CMD curl --fail http://localhost:8978/ || exit 1