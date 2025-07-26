FROM node:22-slim as base

FROM base as builder

WORKDIR /usr/src/app

COPY package*.json ./
RUN npm install

COPY nest-cli.json tsconfig*.json ./
COPY libs ./libs
COPY src ./src

RUN npm run build

FROM base as runner

WORKDIR /usr/src/app
COPY --from=builder /usr/src/app/node_modules ./node_modules
COPY --from=builder /usr/src/app/dist ./dist

EXPOSE 3000
CMD [ "node", "dist/src/main.js" ]
