FROM dbeaver/cloudbeaver:24.1.4

COPY ${PWD}/workspace /opt/cloudbeaver/workspace

WORKDIR /opt/cloudbeaver/

ENTRYPOINT ["./run-server.sh"]