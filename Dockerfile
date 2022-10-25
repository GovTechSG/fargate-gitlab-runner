FROM debian:bullseye-slim

RUN apt-get update && apt-get install -y curl unzip openssl gettext-base \
       && curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | bash \
       && apt install -y gitlab-runner \
       && rm -rf /var/lib/apt/lists/* \
       && rm -f "/home/gitlab-runner/.bash_logout" \
       && mkdir -p /opt/gitlab-runner/metadata /opt/gitlab-runner/builds /opt/gitlab-runner/cache \
       && curl -Lo /opt/gitlab-runner/fargate https://gitlab-runner-custom-fargate-downloads.s3.amazonaws.com/latest/fargate-linux-amd64 \
       && chmod +x /opt/gitlab-runner/fargate

COPY config.toml /tmp/
COPY ecs.toml /tmp/
COPY entrypoint.sh /

RUN chmod +x /entrypoint.sh

USER gitlab-runner

ENTRYPOINT ["/entrypoint.sh"]
CMD ["run", "--user=gitlab-runner", "--working-directory=/home/gitlab-runner"]
