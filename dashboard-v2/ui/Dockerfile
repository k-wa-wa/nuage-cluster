FROM node:22-slim as base

FROM base as deps

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci

FROM base as builder
COPY --from=deps /app/node_modules ./node_modules
WORKDIR /app

ENV NODE_ENV=production

COPY package.json package-lock.json tsconfig.json app.json ./
COPY public ./public
COPY assets ./assets
COPY app ./app
COPY components ./components

RUN npm run build:web

FROM base as runner
WORKDIR /app
COPY --from=builder /app/dist /app/dist

# TODO: 他のベターな方法を検討
CMD [ "npx", "-y", "serve", "dist" ]
