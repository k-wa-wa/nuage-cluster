# frozen_string_literal: true

module Types
  class AdditionalLinkType < Types::BaseObject
    field :button_name, String, null: false, hash_key: "buttonName"
    field :icon_name, String, null: true, hash_key: "iconName"
    field :link_urls, Types::LinkUrlsType, null: false, hash_key: "linkUrls"
  end
end
