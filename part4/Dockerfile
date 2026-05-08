# Part 4.1 — Starter file
#
# This Dockerfile was written quickly and has several security problems.
# Review it, identify the issues, and produce a hardened version.
# You can replace this file in place or write a Dockerfile.hardened alongside it.
#
# Add comments to explain your changes — we are assessing your reasoning,
# not just the end result.

FROM node:18

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
ENV NODE_ENV=production
ENV PORT=3000

EXPOSE 3000

CMD ["node", "src/server.js"]
