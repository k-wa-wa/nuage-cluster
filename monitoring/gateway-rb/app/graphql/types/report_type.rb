# frozen_string_literal: true

module Types
  class ReportType < Types::BaseObject
    field :report_id, ID, null: false
    field :report_name, String, null: false
    field :report_type, String, null: true
    field :generated_at, GraphQL::Types::ISO8601DateTime, null: false
    field :content, String, null: false
    field :status, String, null: false
  end
end
