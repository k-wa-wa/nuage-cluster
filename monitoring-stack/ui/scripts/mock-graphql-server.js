const { createYoga } = require("graphql-yoga")
const { readFileSync } = require("fs")
const { resolve } = require("path")
const { addMocksToSchema } = require("@graphql-tools/mock")
const { makeExecutableSchema } = require("@graphql-tools/schema")
const { buildSchema } = require("graphql") // Add buildSchema for validation

const schemaString = readFileSync(
  resolve(process.cwd(), "schema.graphql"),
  "utf-8"
)

const mocks = {
  Query: () => ({
    me: () => ({
      id: "mock-user-id",
      displayName: "Mock User",
      notificationSettings: {},
    }),
    reports: () => [],
    report: (parent, { reportId }) => ({
      reportId: reportId,
      reportBody: `Mock report body for ${reportId}`,
      userId: "mock-user-id",
      createdAtUnix: Math.floor(Date.now() / 1000),
    }),
    vapidPublicKey: () => "MOCK_VAPID_PUBLIC_KEY",
  }),
  Mutation: () => ({
    login: () => ({
      token: "mock-jwt-token",
      expiresIn: 3600,
    }),
    updateUserProfile: (parent, { displayName, notificationSettings }) => ({
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
  }),
  UserProfile: () => ({
    id: "mock-user-id",
    displayName: "Mock User",
    notificationSettings: {},
  }),
  Report: () => ({
    reportId: "mock-report-id",
    reportBody: "Mock report body",
    userId: "mock-user-id",
    createdAtUnix: Math.floor(Date.now() / 1000),
  }),
  LoginPayload: () => ({
    token: "mock-jwt-token",
    expiresIn: 3600,
  }),
  SubscribePayload: () => ({
    success: true,
    message: "Mock subscription successful",
  }),
}

// --- Schema and Mock Validation Logic ---
const validateMocks = (schemaString, mocks) => {
  const builtSchema = buildSchema(schemaString)
  let hasError = false

  // Helper to check fields for a given type
  const checkTypeFields = (typeName, schemaFields, mockFields) => {
    for (const fieldName in mockFields) {
      if (!schemaFields[fieldName]) {
        console.error(
          `Error: Mock field '${typeName}.${fieldName}' exists but is not defined in the schema.`
        )
        hasError = true
      }
    }
    for (const fieldName in schemaFields) {
      const field = schemaFields[fieldName]
      // Check for non-nullable fields that are not mocked
      if (
        field.type.toString().endsWith("!") &&
        (!mockFields || !mockFields[fieldName])
      ) {
        console.warn(
          `Warning: Non-nullable field '${typeName}.${fieldName}' is not explicitly mocked.`
        )
      }
    }
  }

  // Validate Query type
  const queryType = builtSchema.getQueryType()
  if (queryType) {
    const schemaQueryFields = queryType.getFields()
    const mockQueryFields = mocks.Query ? mocks.Query() : {}
    checkTypeFields("Query", schemaQueryFields, mockQueryFields)
  } else if (mocks.Query) {
    console.error(
      "Error: Mock 'Query' type exists but 'Query' is not defined in the schema."
    )
    hasError = true
  }

  // Validate Mutation type
  const mutationType = builtSchema.getMutationType()
  if (mutationType) {
    const schemaMutationFields = mutationType.getFields()
    const mockMutationFields = mocks.Mutation ? mocks.Mutation() : {}
    checkTypeFields("Mutation", schemaMutationFields, mockMutationFields)
  } else if (mocks.Mutation) {
    console.error(
      "Error: Mock 'Mutation' type exists but 'Mutation' is not defined in the schema."
    )
    hasError = true
  }

  // Validate other object types (e.g., UserProfile, Report)
  for (const mockTypeName in mocks) {
    if (
      mockTypeName === "Query" ||
      mockTypeName === "Mutation" ||
      mockTypeName === "JSONObject"
    ) {
      continue // Already handled or scalar
    }

    const type = builtSchema.getType(mockTypeName)
    if (!type) {
      console.error(
        `Error: Mock type '${mockTypeName}' exists but is not defined in the schema.`
      )
      hasError = true
      continue
    }

    if (type.getFields) {
      // Check if it's an object type
      const schemaFields = type.getFields()
      const mockFields = mocks[mockTypeName] ? mocks[mockTypeName]() : {}
      checkTypeFields(mockTypeName, schemaFields, mockFields)
    }
  }

  if (hasError) {
    console.error("Schema and mock JSON mismatch detected. Exiting.")
    process.exit(1)
  }
}

validateMocks(schemaString, mocks) // Call validation function
// --- End Schema and Mock Validation Logic ---

const schema = makeExecutableSchema({ typeDefs: schemaString })
const schemaWithMocks = addMocksToSchema({ schema, mocks })

const http = require("http")

const yoga = createYoga({
  schema: schemaWithMocks,
  logging: true,
  fetchAPI: { Response },
})

const port = 4001

const server = http.createServer(yoga)

server.listen(port, () => {
  console.log(
    `Mock GraphQL Server is running on http://localhost:${port}/graphql`
  )
})
