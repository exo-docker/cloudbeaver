FROM dbeaver/cloudbeaver:24.0.1

COPY ${PWD}/workspace /opt/cloudbeaver/workspace

WORKDIR /opt/cloudbeaver/

ENTRYPOINT ["./run-server.sh"]