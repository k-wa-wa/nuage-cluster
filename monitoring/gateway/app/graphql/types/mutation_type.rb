# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    field :subscribe, Types::PushNotificationType, null: false,
      description: "Subscribes a client to WebPush notifications" do
      argument :subscription, Types::SubscriptionInputType, required: true
    end
    def subscribe(subscription:)
      PushNotificationService.subscribe(subscription.to_h)
    rescue StandardError => e
      Rails.logger.error "Error subscribing to push notifications: #{e.message}"
      { success: false, message: "Failed to subscribe: #{e.message}" }
    end

    field :notify_all, Types::PushNotificationType, null: false,
      description: "Sends a push notification to all subscribed clients"
    def notify_all
      PushNotificationService.notify_all
    rescue StandardError => e
      Rails.logger.error "Error sending push notifications: #{e.message}"
      { success: false, message: "Failed to send notifications: #{e.message}" }
    end

    # TODO: remove me
    field :test_field, String, null: false,
      description: "An example field added by the generator"
    def test_field
      "Hello World"
    end
  end
end
