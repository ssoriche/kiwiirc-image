# Build stage
FROM node:18-alpine AS builder

WORKDIR /app

# Clone specific KiwiIRC version
ARG KIWIIRC_VERSION=master
RUN apk add --no-cache git
RUN git clone --depth 1 --branch ${KIWIIRC_VERSION} https://github.com/kiwiirc/kiwiirc.git .

# Install dependencies and build
RUN npm ci
RUN npm run build

# Production stage
FROM gcr.io/distroless/nodejs18-debian11:nonroot

WORKDIR /app

# Copy built application
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/node_modules ./node_modules

EXPOSE 80

USER nonroot:nonroot

CMD ["dist/server.js"]
