# frozen_string_literal: true

module Types
  class QueryType < Types::BaseObject
    field :node, Types::NodeType, null: true, description: "Fetches an object given its ID." do
      argument :id, ID, required: true, description: "ID of the object."
    end

    def node(id:)
      context.schema.object_from_id(id, context)
    end

    field :nodes, [ Types::NodeType, null: true ], null: true, description: "Fetches a list of objects given a list of IDs." do
      argument :ids, [ ID ], required: true, description: "IDs of the objects."
    end

    def nodes(ids:)
      ids.map { |id| context.schema.object_from_id(id, context) }
    end

    # Add root-level fields here.
    # They will be entry points for queries on your schema.

    field :temporary_response, String, null: false,
      description: "A temporary response from the gateway server"
    def temporary_response
      "This is a temporary response from the Rails GraphQL gateway server."
    end

    field :reports, [ Types::ReportType ], null: false, description: "List of reports" do
      argument :sort, String, required: false, description: "Sort by field and direction (e.g., 'generatedAt:desc')"
    end
    def reports(sort: nil)
      scope = Report.all
      if sort
        field_graphql, direction_str = sort.split(":", 2)
        field_db = field_graphql.underscore # Convert camelCase to snake_case for database column
        direction = direction_str&.downcase == "desc" ? "desc" : "asc" # Use lowercase for SQL direction

        if Report.column_names.include?(field_db)
          scope = scope.order("#{field_db} #{direction}")
        else
          # Optionally, raise an error or log a warning for invalid sort arguments
          # For now, we'll just ignore invalid arguments and return unsorted
        end
      end
      scope
    end
  end
end
