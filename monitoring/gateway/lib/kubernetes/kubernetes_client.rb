# frozen_string_literal: true

require "kubeclient"

module Kubernetes
  class KubernetesClient
    def initialize(config)
      @client = Kubeclient::Client.new(
        config.context.api_endpoint,
        "example.com/v1alpha1", # API version for ApplicationList custom resource
        ssl_options: config.context.ssl_options,
        auth_options: config.context.auth_options
      )
    end

    def get_application_lists
      @client.get_custom_resources(
        group: "example.com",
        version: "v1alpha1",
        plural: "applicationlists"
      )
    rescue Kubeclient::ResourceNotFoundError
      raise GraphQL::ExecutionError, "ApplicationList custom resource not found."
    rescue StandardError => e
      raise GraphQL::ExecutionError, "Error fetching ApplicationList custom resources: #{e.message}"
    end
  end
end
