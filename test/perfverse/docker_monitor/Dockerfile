FROM debian
# Add Docker's official GPG key:
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl
RUN install -m 0755 -d /etc/apt/keyrings
RUN curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
RUN chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
RUN echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
RUN apt-get update && apt-get install -y --no-install-recommends docker-ce-cli python3 python3-pip python3-venv

WORKDIR /app
RUN python3 -m venv /app/docker-monitor \
    && /app/docker-monitor/bin/pip install --upgrade pip \
    && /app/docker-monitor/bin/pip install docker

COPY docker-monitor-threading.py /app/docker-monitor/bin/docker-monitor.py

CMD ["/app/docker-monitor/bin/python", "/app/docker-monitor/bin/docker-monitor.py"]
