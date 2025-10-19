# frozen_string_literal: true

module Types
  class IconUrlsType < Types::BaseObject
    field :small, String, null: true, hash_key: "small"
    field :medium, String, null: true, hash_key: "medium"
    field :large, String, null: true, hash_key: "large"
  end
end
