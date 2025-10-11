# Stage 1: Build the application
FROM node:24-slim AS base

# Upgrade system packages to reduce vulnerabilities and remove cache
RUN apt-get update && apt-get upgrade -y && apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/*

FROM base AS builder

WORKDIR /app

# Copy package.json and package-lock.json to install dependencies
COPY package*.json ./

# Install production dependencies
RUN npm ci

# Copy all source code
COPY . .

# Build the TypeScript application
RUN npm run build

# Stage 2: Run the application
FROM base

WORKDIR /app

# Copy only necessary files from the builder stage
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist

# Expose the port the application runs on (assuming default Express port 3000)
EXPOSE 3000

# Command to run the application
CMD ["npm", "start"]
