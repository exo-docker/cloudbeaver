FROM dbeaver/cloudbeaver:24.1.3

COPY ${PWD}/workspace /opt/cloudbeaver/workspace

WORKDIR /opt/cloudbeaver/

ENTRYPOINT ["./run-server.sh"]