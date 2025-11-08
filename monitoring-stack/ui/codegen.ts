import { CodegenConfig } from '@graphql-codegen/cli';

const config: CodegenConfig = {
  schema: './schema.graphql',
  documents: ['app/**/*.tsx', 'components/**/*.tsx', 'app/**/*.ts', 'components/**/*.ts'],
  generates: {
    './types/graphql.ts': {
      plugins: ['typescript', 'typescript-operations', 'typescript-graphql-request'],
      config: {
        scalars: {
          JSONObject: 'Record<string, any>',
        },
      },
    },
  },
  ignoreNoDocuments: true,
};

export default config;
