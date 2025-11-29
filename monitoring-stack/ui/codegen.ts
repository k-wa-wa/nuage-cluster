import type { CodegenConfig } from "@graphql-codegen/cli"

const config: CodegenConfig = {
  schema: "schema.graphql",
  generates: {
    "./types/generated/graphql.ts": {
      plugins: ["typescript", "typescript-operations", "typescript-resolvers"],
      config: {
        useIndexSignature: true,
        noSchemaStitching: true,
        useTypeImports: true,
      },
    },
  },
}

export default config
