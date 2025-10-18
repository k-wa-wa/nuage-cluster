# Gateway

This is the Gateway service for the Nuage Cluster monitoring system.

## Setup

To set up the project, follow these steps:

1.  **Install Dependencies**:
    ```bash
    bundle install
    ```

2.  **Create GraphQL Schema**:
    ```bash
    bundle exec rake graphql:schema:idl
    ```

## Running the Server

To start the Rails server, run:

```bash
rails s
```
