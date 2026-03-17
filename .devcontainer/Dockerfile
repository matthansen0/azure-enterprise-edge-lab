FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# Install Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install Bicep CLI (via Azure CLI)
RUN az bicep install

# Install Node.js 20 LTS for API app
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Install jq, curl, openssh-client, hey (HTTP load generator)
RUN apt-get update && apt-get install -y \
    jq \
    curl \
    openssh-client \
    zip \
    && rm -rf /var/lib/apt/lists/*

# Install hey (HTTP load generator) for traffic generation
RUN curl -sL https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64 -o /usr/local/bin/hey \
    && chmod +x /usr/local/bin/hey

# Install ShellCheck for linting
RUN apt-get update && apt-get install -y shellcheck && rm -rf /var/lib/apt/lists/*

# Install Azure Developer CLI (azd)
RUN curl -fsSL https://aka.ms/install-azd.sh | bash
