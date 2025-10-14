# frozen_string_literal: true

module Types
  class SubscriptionKeysInputType < Types::BaseInputObject
    description "Keys for a WebPush subscription"
    argument :p256dh, String, required: true
    argument :auth, String, required: true
  end

  class SubscriptionInputType < Types::BaseInputObject
    description "Input for a WebPush subscription"
    argument :endpoint, String, required: true
    argument :expiration_time, GraphQL::Types::ISO8601DateTime, required: false
    argument :keys, SubscriptionKeysInputType, required: true
  end
end
