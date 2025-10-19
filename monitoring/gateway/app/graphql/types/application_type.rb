# frozen_string_literal: true

module Types
  class ApplicationType < Types::BaseObject
    field :name, String, null: false
    field :description, String, null: true
    field :category, String, null: true
    field :icon_urls, Types::IconUrlsType, null: false, hash_key: "iconUrls"
    field :launch_urls, Types::LaunchUrlsType, null: false, hash_key: "launchUrls"
    field :additional_links, [ Types::AdditionalLinkType ], null: true, hash_key: "additionalLinks"
  end
end
