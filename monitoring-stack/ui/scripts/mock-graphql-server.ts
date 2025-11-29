import { addMocksToSchema } from "@graphql-tools/mock"
import { makeExecutableSchema } from "@graphql-tools/schema"
import { readFileSync } from "fs"
import { createYoga } from "graphql-yoga"
import http from "http"
import { resolve } from "path"

import type { Resolvers } from "./../types/generated/graphql.ts"

const schemaString = readFileSync(
  resolve(process.cwd(), "schema.graphql"),
  "utf-8"
)

const mocks: Resolvers = {
  Query: {
    me: () => ({
      id: "mock-user-id",
      displayName: "Mock User",
      notificationSettings: {},
    }),
    reports: () => [],
    report: (parent: any, { reportId }: { reportId: string }) => ({
      reportId: reportId,
      reportBody: `Mock report body for ${reportId}`,
      userId: "mock-user-id",
      createdAtUnix: Math.floor(Date.now() / 1000),
    }),
    vapidPublicKey: (): string => "MOCK_VAPID_PUBLIC_KEY",
  },
  Mutation: {
    login: () => ({
      token: "mock-jwt-token",
      expiresIn: 3600,
    }),
    updateUserProfile: (
      parent: any,
      { displayName, notificationSettings }
    ) => ({
      id: "mock-user-id",
      displayName: displayName || "Mock User",
      notificationSettings: notificationSettings
        ? notificationSettings.reduce(
            (acc, setting) => ({ ...acc, [setting.key]: setting.value }),
            {}
          )
        : {},
    }),
    subscribe: () => ({
      success: true,
      message: "Mock subscription successful",
    }),
  },
}

const schema = makeExecutableSchema({ typeDefs: schemaString })
const schemaWithMocks = addMocksToSchema({ schema, resolvers: mocks })

const yoga = createYoga({
  schema: schemaWithMocks,
  logging: true,
  fetchAPI: { Response },
})

const port = process.env.GRAPHQL_MOCK_PORT || 4001

const server = http.createServer(yoga)

server.listen(port, () => {
  console.log(
    `Mock GraphQL Server is running on http://localhost:${port}/graphql`
  )
})
