# frozen_string_literal: true

module Types
  class ApplicationType < Types::BaseObject
    field :name, String, null: false
    field :namespace, String, null: true
    field :url, String, null: false
    field :status, String, null: true
    field :version, String, null: true
    field :icon, String, null: true
    field :description, String, null: true
  end
end
