# Use official CloudBeaver image
FROM dbeaver/cloudbeaver:25.3.3

# Copy pre-defined workspace configuration
COPY workspace /opt/cloudbeaver/workspace

# Set working directory
WORKDIR /opt/cloudbeaver

# Set proper permissions if needed (optional, uncomment if required)
# RUN chown -R dbeaver:dbeaver /opt/cloudbeaver/workspace

# Use exec form for ENTRYPOINT for signal forwarding and better PID 1 behavior
ENTRYPOINT ["./launch-product.sh"]

# Add a health check to verify the server is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD curl --fail http://localhost:8978/cloudbeaver/status || exit 1