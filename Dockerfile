FROM cgr.dev/chainguard/python:latest-dev AS builder

USER root
RUN apk add --no-cache \
    postgresql-16-dev=16.11-r0 \
    gcc=15.2.0-r6 \
    glibc-dev=2.42-r6 \
    tini=0.19.0-r22

WORKDIR /app

RUN python -m venv /app/venv
ENV PATH="/app/venv/bin:$PATH"

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

# Reduce botocore size by ~40MB
# We only need 'rds' for IAM Auth.
RUN find /app/venv/lib/python*/site-packages/botocore/data -maxdepth 1 -type d \
    ! -name "data" ! -name "rds" ! -name "_retry" ! -name "endpoints.json" ! -name "sdk-default-configuration.json" \
    -exec rm -rf {} + || true

# Cleanup __pycache__ and byte-code
RUN find /app/venv -name "__pycache__" -type d -exec rm -rf {} + && \
    find /app/venv -name "*.pyc" -delete

FROM cgr.dev/chainguard/python:latest AS production

WORKDIR /app

# Copy necessary shared libraries for psycopg2
COPY --from=builder /usr/lib/libpq.so* /usr/lib/
COPY --from=builder /usr/lib/libssl.so* /usr/lib/
COPY --from=builder /usr/lib/libcrypto.so* /usr/lib/
COPY --from=builder /usr/lib/libgssapi_krb5.so* /usr/lib/
COPY --from=builder /usr/lib/libkrb5.so* /usr/lib/
COPY --from=builder /usr/lib/libkrb5support.so* /usr/lib/
COPY --from=builder /usr/lib/libk5crypto.so* /usr/lib/
COPY --from=builder /usr/lib/libcom_err.so* /usr/lib/
COPY --from=builder /usr/lib/libkeyutils.so* /usr/lib/
COPY --from=builder /usr/lib/libldap* /usr/lib/
COPY --from=builder /usr/lib/liblber* /usr/lib/
COPY --from=builder /usr/lib/libintl* /usr/lib/
COPY --from=builder /usr/lib/libsasl2* /usr/lib/

COPY --from=builder /usr/bin/tini /usr/bin/tini

# Copy the virtual environment from builder
COPY --from=builder --chown=nonroot:nonroot /app/venv /app/venv
# Add venv to PATH
ENV PATH="/app/venv/bin:$PATH"

# Copy application code
COPY --chown=nonroot:nonroot . .

# Native Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ["/app/venv/bin/python", "src/healthcheck.py"]

EXPOSE 5001

ENV FLASK_ENV=production

# Explicitly switch to nonroot for extra safety
USER nonroot

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/app/venv/bin/python", "run.py"]