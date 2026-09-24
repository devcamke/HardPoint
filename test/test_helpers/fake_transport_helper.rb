# Stands in for the network in integration tests: answers requests by URL path and keeps them, so
# tests exercise the real clients (fields, headers, error handling) without calling out.
class FakeTransport
  Request = Data.define(:method, :url, :headers, :json, :form) do
    def path = URI(url).path
  end

  attr_reader :requests

  def initialize(responses)
    @responses = responses
    @requests = []
  end

  def request(method, url, headers: {}, json: nil, form: nil)
    request = Request.new(method, url, headers, json, form)
    @requests << request
    response = @responses.fetch(request.path) { raise "No fake response for #{method.upcase} #{url}" }
    response = response.call(request) if response.respond_to?(:call)
    raise response if response.is_a?(Exception)

    status, body = response.is_a?(Array) ? response : [ 200, response ]
    JsonHttp::Response.new(status, body.deep_stringify_keys)
  end

  def last(path)
    @requests.reverse.find { _1.path == path }
  end
end

module FakeTransportHelper
  # Swaps a client's transport for the rest of the test.
  def fake_transport(client_class, responses)
    FakeTransport.new(responses).tap do |fake|
      previous = client_class.transport
      client_class.transport = fake
      (@restore_transports ||= []) << -> { client_class.transport = previous }
    end
  end

  def self.included(base)
    base.teardown do
      Array(@restore_transports).each(&:call)
      Sms::Outbox.deliveries.clear
    end
  end
end

ActiveSupport.on_load(:active_support_test_case) { include FakeTransportHelper }
ActiveSupport.on_load(:action_dispatch_integration_test) { include FakeTransportHelper }
