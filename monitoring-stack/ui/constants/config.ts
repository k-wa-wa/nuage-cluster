export const graphqlEndpoint =
  process.env.EXPO_PUBLIC_USE_MOCK_GRAPHQL === "true"
    ? "http://localhost:4001/graphql"
    : process.env.EXPO_PUBLIC_GRAPHQL_ENDPOINT || "http://localhost:5051/graphql"
