# frozen_string_literal: true

module Types
  class LaunchUrlsType < Types::BaseObject
    field :web, String, null: true, hash_key: "web"
    field :ios, String, null: true, hash_key: "ios"
  end
end
