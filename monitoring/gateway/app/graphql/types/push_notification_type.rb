# frozen_string_literal: true

module Types
  class PushNotificationType < Types::BaseObject
    description "Represents the result of a push notification operation"
    field :success, Boolean, null: false, description: "True if the operation was successful"
    field :message, String, null: true, description: "A message related to the operation result"
  end
end
