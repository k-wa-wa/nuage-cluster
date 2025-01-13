FROM node:22-slim as base

FROM base as deps

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci

FROM base as builder
COPY --from=deps /app/node_modules ./node_modules
WORKDIR /app

ENV NODE_ENV=production

COPY index.html package.json package-lock.json tsconfig.app.json tsconfig.json tsconfig.node.json vite.config.ts ./
COPY public ./public
COPY src ./src

RUN npm run build

FROM nginx:alpine3.20-slim
COPY --from=builder /app/dist /usr/share/nginx/html
