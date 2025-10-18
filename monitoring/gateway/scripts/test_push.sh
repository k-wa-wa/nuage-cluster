#!/bin/bash

# GraphQL endpoint URL
#GRAPHQL_URL="http://localhost:3000/graphql" # Adjust if your server runs on a different port or path
GRAPHQL_URL="https://monitoring.dev.nuage/graphql" # Adjust if your server runs on a different port or path

# GraphQL query to fetch reports
GRAPHQL_QUERY='
mutation {
  notifyAll {
    success
    message
  }
}
'

# Send the GraphQL query using curl
curl -k -X POST \
     -H "Content-Type: application/json" \
     --data "{ \"query\": \"$(echo $GRAPHQL_QUERY | tr -d '\n' | sed 's/"/\\"/g')\" }" \
     $GRAPHQL_URL | jq
