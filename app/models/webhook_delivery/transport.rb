require "net/http"

# Posts webhooks, but only to public internet addresses: the host is resolved once, every address is
# checked (no loopback, private, link-local or carrier-grade NAT ranges, so a webhook can't be aimed at
# the server's own network), and the connection goes to that checked address. No redirects are followed.
class WebhookDelivery::Transport
  Refused = Class.new(StandardError)

  BLOCKED = %w[ 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16
                198.18.0.0/15 224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8 ::ffff:0:0/96 ].map { IPAddr.new(_1) }.freeze
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  # Development and tests post to local test servers.
  def self.private_addresses_allowed?
    Rails.configuration.x.webhooks_allow_private_addresses
  end

  def self.blocked?(address)
    BLOCKED.any? { _1.include?(address) }
  end

  # For checking a URL as it's saved: an IP address in a blocked range, or an obviously local name.
  def self.private_host?(host)
    blocked?(IPAddr.new(host.to_s.delete("[]")))
  rescue IPAddr::InvalidAddressError
    host.to_s.downcase.then { _1 == "localhost" || _1.end_with?(".localhost", ".internal", ".local") }
  end

  def request(method, url, headers: {}, json: nil, form: nil)
    uri = URI(url)
    post = Net::HTTP::Post.new(uri, headers.merge("Content-Type" => "application/json"))
    post.body = json.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = resolve(uri.host)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    response = http.start { _1.request(post) }
    JsonHttp::Response.new(response.code.to_i, { "raw" => response.body.to_s.first(500) })
  rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, EOFError => error
    raise JsonHttp::Unreachable, "#{uri&.host}: #{error.message}"
  end

  private
    def resolve(host)
      addresses = Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map { IPAddr.new(_1.ip_address) }.uniq
      raise Refused, "#{host} doesn't resolve" if addresses.empty?
      if !self.class.private_addresses_allowed? && addresses.any? { self.class.blocked?(_1) }
        raise Refused, "#{host} points at a private address"
      end

      addresses.first.to_s
    rescue SocketError => error
      raise Refused, "#{host} doesn't resolve (#{error.message})"
    end
end
