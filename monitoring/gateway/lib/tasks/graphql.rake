# frozen_string_literal: true

require "graphql/rake_task"

GraphQL::RakeTask.new(
  schema_name: "GatewaySchema",
  idl_outfile: "schema.graphql"
)
