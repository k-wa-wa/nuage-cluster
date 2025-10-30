FROM node:24-slim AS base

# Stage 1: Build the application
FROM base AS builder

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm install

COPY . .
# Stage 2: Serve the application
FROM base AS runner

WORKDIR /app

# Copy the entire application from the builder stage
COPY --from=builder /app .

EXPOSE 8081

CMD ["npm", "run", "web"]
