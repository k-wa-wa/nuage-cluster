# frozen_string_literal: true

require "kubeclient"

module Kubernetes
  class KubernetesClient
    def initialize
      if ENV["KUBE_CONFIG"]
        config = Kubeclient::Config.read(ENV["KUBE_CONFIG"])
        @client = Kubeclient::Client.new(
          config.context.api_endpoint,
          "v1",
          ssl_options: config.context.ssl_options,
          auth_options: config.context.auth_options
        )
      else
        auth_options = {
          bearer_token_file: "/var/run/secrets/kubernetes.io/serviceaccount/token"
        }
        ssl_options = {}
        if File.exist?("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")
          ssl_options[:ca_file] = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
        end
        @client = Kubeclient::Client.new(
          "https://kubernetes.default.svc",
          "v1",
          auth_options: auth_options,
          ssl_options:  ssl_options
        )
      end
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
