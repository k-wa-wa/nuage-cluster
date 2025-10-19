#!/bin/bash

# GraphQL endpoint URL
GRAPHQL_URL="http://localhost:3000/graphql" # Adjust if your server runs on a different port or path

# GraphQL query to fetch reports
GRAPHQL_QUERY='
  query {
    applicationList(name: "nuage-application-list") {
      applications {
        name
      }
    }
  }
'

# Send the GraphQL query using curl
curl -X POST \
     -H "Content-Type: application/json" \
     --data "{ \"query\": \"$(echo $GRAPHQL_QUERY | tr -d '\n' | sed 's/"/\\"/g')\" }" \
     $GRAPHQL_URL | jq
