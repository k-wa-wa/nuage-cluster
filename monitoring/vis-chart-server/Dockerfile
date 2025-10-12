# Stage 1: Build the application
FROM node:24-slim AS base

# Upgrade system packages to reduce vulnerabilities and remove cache
RUN apt-get update && apt-get upgrade -y && apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Japanese fonts and set locale for proper display of Japanese characters
RUN apt-get update && apt-get install -y locales fonts-ipaexfont \
    && rm -rf /var/lib/apt/lists/* \
    && localedef -i ja_JP -f UTF-8 ja_JP.UTF-8
ENV LANG ja_JP.UTF-8
ENV LC_ALL ja_JP.UTF-8

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
