const { createSchema, createYoga } = require('graphql-yoga');
const { readFileSync } = require('fs');
const { resolve } = require('path'); // Use resolve instead of join
const { addMocksToSchema } = require('@graphql-tools/mock');
const { makeExecutableSchema } = require('@graphql-tools/schema');

const schemaString = readFileSync(resolve(process.cwd(), 'schema.graphql'), 'utf-8');

const mocks = {
  Query: () => ({
    applicationLists: () => [
      {
        apiVersion: 'v1',
        kind: 'ApplicationList',
        metadata: { name: 'mock-app-list-1' },
        applications: [
          {
            name: 'Mock App 1',
            description: 'This is the first mock application.',
            icon: '🚀',
            namespace: 'default',
            status: 'Running',
            url: 'https://mockapp1.example.com',
            version: '1.0.0',
          },
          {
            name: 'Mock App 2',
            description: 'Another mock application for testing.',
            icon: '💡',
            namespace: 'staging',
            status: 'Stopped',
            url: 'https://mockapp2.example.com',
            version: '1.2.0',
          },
          {
            name: 'Mock App 3',
            description: 'A third mock application.',
            icon: '⚙️',
            namespace: 'production',
            status: 'Running',
            url: 'https://mockapp3.example.com',
            version: '2.0.0',
          },
        ],
      },
      {
        apiVersion: 'v1',
        kind: 'ApplicationList',
        metadata: { name: 'mock-app-list-2' },
        applications: [
          {
            name: 'Mock App 4',
            description: 'Fourth mock application.',
            icon: '📦',
            namespace: 'default',
            status: 'Running',
            url: 'https://mockapp4.example.com',
            version: '1.0.0',
          },
        ],
      },
    ],
    reports: () => [], // Mock reports to be empty for now
    temporaryResponse: () => 'Mock temporary response',
    vapidPublicKey: () => 'MOCK_VAPID_PUBLIC_KEY',
  }),
  Application: () => ({
    name: () => 'Default Mock App',
    description: () => 'Default mock description',
    icon: () => '❓',
    namespace: () => 'default',
    status: () => 'Unknown',
    url: () => 'https://default.example.com',
    version: () => '0.0.1',
  }),
};

const schema = makeExecutableSchema({ typeDefs: schemaString });
const schemaWithMocks = addMocksToSchema({ schema, mocks });

const http = require('http'); // Import http module

const yoga = createYoga({
  schema: schemaWithMocks,
  logging: true,
  // Integrate with Node.js http server
  fetchAPI: { Response }
});

const port = process.env.GRAPHQL_MOCK_PORT || 4001; // Changed port to 4001

const server = http.createServer(yoga);

server.listen(port, () => {
  console.log(`Mock GraphQL Server is running on http://localhost:${port}/graphql`);
});
