# ────────────────────────────────────────────────────────────────────────────────
# Stage 1: download jenkins-agent.jar
# ────────────────────────────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS downloader

ARG JENKINS_AGENT_JAR_VERSION=3256.v88a_f6e922152

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
    "https://repo.jenkins-ci.org/public/org/jenkins-ci/main/remoting/${JENKINS_AGENT_JAR_VERSION}/remoting-${JENKINS_AGENT_JAR_VERSION}.jar" \
    -o /agent.jar

# ────────────────────────────────────────────────────────────────────────────────
# Stage 2: final minimal image
# ────────────────────────────────────────────────────────────────────────────────
FROM debian:bookworm-slim

# ── Java (headless, smallest available for ARM64) ──────────────────────────────
# OpenJDK 17 headless is the minimum required by modern Jenkins remoting
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        openjdk-17-jre-headless \
        git \
        curl \
        ca-certificates \
        openssh-client && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ── Non-root user ──────────────────────────────────────────────────────────────
ARG AGENT_UID=1000
ARG AGENT_GID=1000

RUN groupadd -g "${AGENT_GID}" jenkins && \
    useradd -u "${AGENT_UID}" -g jenkins -m -s /bin/bash jenkins

# ── Agent jar ─────────────────────────────────────────────────────────────────
COPY --from=downloader /agent.jar /usr/share/jenkins/agent.jar
RUN chmod 444 /usr/share/jenkins/agent.jar

# ── Workspace directory ───────────────────────────────────────────────────────
RUN mkdir -p /home/jenkins/agent && \
    chown -R jenkins:jenkins /home/jenkins

# ── JVM tuning for 1 GB RAM ───────────────────────────────────────────────────
ENV JAVA_OPTS="-Xms64m -Xmx256m -XX:+UseSerialGC -Djava.awt.headless=true"

# ── Entry-point script ────────────────────────────────────────────────────────
COPY scripts/start-agent.sh /usr/local/bin/start-agent.sh
RUN chmod +x /usr/local/bin/start-agent.sh

USER jenkins
WORKDIR /home/jenkins/agent

ENTRYPOINT ["/usr/local/bin/start-agent.sh"]
