# frozen_string_literal: true

module Types
  class ApplicationListType < Types::BaseObject
    field :api_version, String, null: false
    field :kind, String, null: false
    field :metadata, GraphQL::Types::JSON, null: false
    field :applications, [ Types::ApplicationType ], null: false do
      description "List of applications defined in the spec"
      # Resolve the applications from the spec field
      def resolve
        object.spec["applications"] || []
      end
    end
  end
end
