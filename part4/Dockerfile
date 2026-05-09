# Part 4.1 — Starter file
#
# This Dockerfile was written quickly and has several security problems.
# Review it, identify the issues, and produce a hardened version.
# You can replace this file in place or write a Dockerfile.hardened alongside it.
#
# Add comments to explain your changes — we are assessing your reasoning,
# not just the end result.

FROM node:18 
# node18 is a very old image of the Docker Hub, and contain vulnerabilities. https://snyk.io/test/docker/node%3A18.0-alpine, consider using a newer version >= 22

WORKDIR /app

# Install build tools and dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    python3 \
    vim

COPY . .

RUN npm install

# Application needs to connect to the database
ENV DB_PASSWORD=mysecretpassword123 
# Sensitive password kept in the Dockerfile, should be passed as an env variable at runtime or stored in a secret manager. 
ENV NODE_ENV=production
ENV PORT=3000

EXPOSE 3000

CMD ["node", "src/server.js"]
