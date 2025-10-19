#!/bin/bash

# GraphQL endpoint URL
GRAPHQL_URL="http://localhost:8080/graphql" # Adjust if your server runs on a different port or path

# GraphQL query to fetch reports
GRAPHQL_QUERY='
  query {
    reports(sort: "generatedAt:desc") {
      reportId
      reportName
      reportType
      generatedAt
      content
      status
    }
  }
'

# Send the GraphQL query using curl
curl -X POST \
     -H "Content-Type: application/json" \
     --data "{ \"query\": \"$(echo $GRAPHQL_QUERY | tr -d '\n' | sed 's/"/\\"/g')\" }" \
     $GRAPHQL_URL | jq
