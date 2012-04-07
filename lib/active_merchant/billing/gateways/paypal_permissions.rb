require 'active_merchant'
require 'uri'
require 'cgi'
require 'openssl'
require 'base64'


module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PaypalPermissionsGateway < Gateway # :nodoc
      public
      def self.setup
        yield self
      end

      public
      def initialize(options = {})
        requires!(options, :login, :password, :signature, :app_id)
        @login = options.delete(:login)
        @password = options.delete(:password)
        @app_id = options.delete(:app_id)
        @api_signature = options.delete(:signature)
        request_permissions_headers = {
          'X-PAYPAL-SECURITY-USERID' => @login,
          'X-PAYPAL-SECURITY-PASSWORD' => @password,
          'X-PAYPAL-SECURITY-SIGNATURE' => @api_signature,
          'X-PAYPAL-APPLICATION-ID' => @app_id,
          'X-PAYPAL-REQUEST-DATA-FORMAT' => 'NV',
          'X-PAYPAL-RESPONSE-DATA-FORMAT' => 'NV',
        }
        get_access_token_headers = request_permissions_headers.dup
        get_basic_personal_data_headers = lambda { |access_token, access_token_verifier|
          {
            'X-PAYPAL-SECURITY-USERID' => @login,
            'X-PAYPAL-SECURITY-PASSWORD' => @password,
            'X-PAYPAL-SECURITY-SIGNATURE' => @api_signature,
            'X-PAYPAL-APPLICATION-ID' => @app_id,
            'X-PAYPAL-REQUEST-DATA-FORMAT' => 'NV',
            'X-PAYPAL-RESPONSE-DATA-FORMAT' => 'NV',
          }.update(authorization_header(get_basic_personal_data_url, access_token, access_token_verifier))
        }
        get_advanced_personal_data_headers = lambda { |access_token, access_token_verifier|
          {
            'X-PAYPAL-SECURITY-USERID' => @login,
            'X-PAYPAL-SECURITY-PASSWORD' => @password,
            'X-PAYPAL-SECURITY-SIGNATURE' => @api_signature,
            'X-PAYPAL-APPLICATION-ID' => @app_id,
            'X-PAYPAL-REQUEST-DATA-FORMAT' => 'NV',
            'X-PAYPAL-RESPONSE-DATA-FORMAT' => 'NV',
          }.update(authorization_header(get_advanced_personal_data_url, access_token, access_token_verifier))
        }
        @options = {
          :request_permissions_headers => request_permissions_headers,
          :get_access_token_headers => get_access_token_headers,
          :get_basic_personal_data_headers => get_basic_personal_data_headers,
          :get_advanced_personal_data_headers => get_advanced_personal_data_headers,
        }.update(options)
        super
      end

      public
      def request_permissions(callback_url, scope)
        query_string = build_request_permissions_query_string callback_url, scope
        nvp_response = ssl_get "#{request_permissions_url}?#{query_string}", @options[:request_permissions_headers]
        if nvp_response =~ /error\(\d+\)/
          # puts "request: #{request_permissions_url}?#{query_string}\n"
          # puts "nvp_response: #{nvp_response}\n"
        end
        response = parse_request_permissions_nvp(nvp_response)
      end

      public
      def request_permissions_url
        test? ? URLS[:test][:request_permissions] : URLS[:live][:request_permissions]
      end

      public
      def get_access_token(request_token, request_token_verifier)
        query_string = build_get_access_token_query_string request_token, request_token_verifier
        nvp_response = ssl_get "#{get_access_token_url}?#{query_string}", @options[:get_access_token_headers]
        if nvp_response =~ /error\(\d+\)/
          # puts "request: #{get_access_token_url}?#{query_string}\n"
          # puts "nvp_response: #{nvp_response}\n"
        end
        response = parse_get_access_token_nvp(nvp_response)
      end

      public
      def redirect_user_to_paypal_url token
        template = test? ? URLS[:test][:redirect_user_to_paypal] : URLS[:live][:redirect_user_to_paypal]
        template % token
      end

      public
      def get_basic_personal_data(access_token, access_token_verifier)
        body = build_get_basic_personal_data_post_body(access_token)
        opts = @options[:get_basic_personal_data_headers].call(access_token, access_token_verifier)
        # puts "ssl_post: get_basic_personal_data_url:#{get_basic_personal_data_url}\n   body:#{body}\n   opts:#{opts.inspect}"
        nvp_response = ssl_post(get_basic_personal_data_url, body, opts)
        if nvp_response =~ /error\(\d+\)/
          # puts "request: #{get_basic_personal_data_url} post_body:#{body}\n"
          # puts "nvp_response: #{nvp_response}\n"
        end
        response = parse_get_basic_personal_data_nvp(nvp_response)
      end

      public
      def get_access_token_url
        test? ? URLS[:test][:get_access_token] : URLS[:live][:get_access_token]
      end

      public
      def get_permissions_url
        test? ? URLS[:test][:get_permissions] : URLS[:live][:get_permissions]
      end

      public
      def get_basic_personal_data_url
        test? ? URLS[:test][:get_basic_personal_data] : URLS[:live][:get_basic_personal_data]
      end

      public
      def get_advanced_personal_data_url
        test? ? URLS[:test][:get_advanced_personal_data] : URLS[:live][:get_advanced_personal_data]
      end

      private
      URLS = {
        :test => {
          :request_permissions => 'https://svcs.sandbox.paypal.com/Permissions/RequestPermissions',
          :redirect_user_to_paypal => 'https://www.sandbox.paypal.com/cgi-bin/webscr?cmd=_grant-permission&request_token=%s',
          :get_access_token => 'https://svcs.sandbox.paypal.com/Permissions/GetAccessToken',
          :get_permissions => 'https://svcs.sandbox.paypal.com/Permissions/GetPermissions',
          :get_basic_personal_data => 'https://svcs.sandbox.paypal.com/Permissions/GetBasicPersonalData',
          :get_advanced_personal_data => 'https://svcs.sandbox.paypal.com/Permissions/GetAdvancedPersonalData',
        },
        :live => {
          :request_permissions => 'https://svcs.paypal.com/Permissions/RequestPermissions',
          :redirect_user_to_paypal => 'https://www.paypal.com/cgi-bin/webscr?cmd=_grant-permission&request_token=%s',
          :get_access_token => 'https://svcs.paypal.com/Permissions/GetAccessToken',
          :get_permissions => 'https://www.paypal.com/Permissions/GetPermissions',
          :get_basic_personal_data => 'https://www.paypal.com/Permissions/GetBasicPersonalData',
          :get_advanced_personal_data => 'https://www.paypal.com/Permissions/GetAdvancedPersonalData',
        }
      }

      private
      def build_request_permissions_query_string(callback_url, scope)
        scopes_query = build_scopes_query_string(scope)
        "requestEnvelope.errorLanguage=en_US&#{scopes_query}&callback=#{URI.encode(callback_url)}"
      end

      private
      def build_scopes_query_string(scope)
        if scope.is_a? String
          scopes = scope.split(',')
        elsif scope.is_a? Array
          scopes = scope
        else
          scopes = []
        end
        scopes.collect{ |s| "scope=#{URI.encode(s.to_s.strip.upcase)}" }.join("&")
      end

      private
      def build_get_access_token_query_string(request_token, verifier)
        "requestEnvelope.errorLanguage=en_US&token=#{request_token}&verifier=#{verifier}"
      end

      private
      def build_get_basic_personal_data_post_body(token)
        body = ""
        [
          "http://axschema.org/namePerson/first",
          "http://axschema.org/namePerson/last",
          "http://axschema.org/contact/email",
          "http://schema.openid.net/contact/fullname",
          "http://openid.net/schema/company/name",
          "http://axschema.org/contact/country/home",
          "https://www.paypal.com/webapps/auth/schema/payerID",
        ].each_with_index do |v, idx|
          body += "attributeList.attribute(#{idx})=#{v}&"
        end
        body += "requestEnvelope.errorLanguage=en_US"
      end

=begin
      private
      def setup_request_permission
        callback
        scope
      end
=end

      private
      def parse_request_permissions_nvp(nvp)
        response = {
          :errors => [
          ],
        }
        pairs = nvp.split "&"
        pairs.each do |pair|
          n,v = pair.split "="
          n = CGI.unescape n
          v = CGI.unescape v
          case n
          when "responseEnvelope.timestamp"
            response[:timestamp] = v
          when "responseEnvelope.ack"
            response[:ack] = v
=begin
# Client should implement these with logging...
            case v
            when "Success"
            when "Failure"
            when "Warning"
            when "SuccessWithWarning"
            when "FailureWithWarning"
            end
=end
          when "responseEnvelope.correlationId"
            response[:correlation_id] = v
          when "responseEnvelope.build"
            # do nothing
          when "token"
            response[:token] = v
          when /^error\((?<error_idx>\d+)\)/
            error_idx = error_idx.to_i
            if response[:errors].length <= error_idx
              response[:errors] << { :parameters => [] }
              raise if response[:errors].length <= error_idx
            end
            case n
            when /^error\(\d+\)\.errorId$/
              response[:errors][error_idx][:error_id] = v
=begin
# Client should implement these with logging. PayPal doesn't distinguish
# between errors which can be corrected by the user and errors which need
# to be corrected by a developer or merchant, say, in configuration.
#             case v
#             when "520002"
#             when
=end            
            when /^error\(\d+\)\.domain$/
              response[:errors][error_idx][:domain] = v
            when /^error\(\d+\)\.subdomain$/
              response[:errors][error_idx][:subdomain] = v
            when /^error\(\d+\)\.severity$/
              response[:errors][error_idx][:severity] = v
            when /^error\(\d+\)\.category$/
              response[:errors][error_idx][:category] = v
            when /^error\(\d+\)\.message$/
              response[:errors][error_idx][:message] = v
            when /^error\(\d+\)\.parameter\((?<parameter_idx>\d+)\)$/
              parameter_idx = parameter_idx.to_i
              if response[:errors][error_idx][:parameters].length <= parameter_idx
                response[:errors][error_idx][:parameters] << {}
                raise if response[:errors][error_idx][:parameters].length <= parameter_idx
              end
              response[:errors][error_idx][:parameters][parameter_idx] = v
            end
          end
        end
        response
      end

      private
      def parse_get_access_token_nvp(nvp)
        response = {
          :errors => [
          ],
        }
        pairs = nvp.split "&"
        pairs.each do |pair|
          n,v = pair.split "="
          n = CGI.unescape n
          v = CGI.unescape v
          case n
          when "responseEnvelope.timestamp"
            response[:timestamp] = v
          when "responseEnvelope.ack"
            response[:ack] = v
=begin
# Client should implement these with logging...
            case v
            when "Success"
            when "Failure"
            when "Warning"
            when "SuccessWithWarning"
            when "FailureWithWarning"
            end
=end
          when "responseEnvelope.correlationId"
            response[:correlation_id] = v
          when "responseEnvelope.build"
            # do nothing
          when "token"
            response[:token] = v
          when "tokenSecret"
            response[:tokenSecret] = v
          when /^error\((?<error_idx>\d+)\)/
            error_idx = error_idx.to_i
            if response[:errors].length <= error_idx
              response[:errors] << { :parameters => [] }
              raise if response[:errors].length <= error_idx
            end
            case n
            when /^error\(\d+\)\.errorId$/
              response[:errors][error_idx][:error_id] = v
=begin
# Client should implement these with logging. PayPal doesn't distinguish
# between errors which can be corrected by the user and errors which need
# to be corrected by a developer or merchant, say, in configuration.
#             case v
#             when "520002"
#             when
=end            
            when /^error\(\d+\)\.domain$/
              response[:errors][error_idx][:domain] = v
            when /^error\(\d+\)\.subdomain$/
              response[:errors][error_idx][:subdomain] = v
            when /^error\(\d+\)\.severity$/
              response[:errors][error_idx][:severity] = v
            when /^error\(\d+\)\.category$/
              response[:errors][error_idx][:category] = v
            when /^error\(\d+\)\.message$/
              response[:errors][error_idx][:message] = v
            when /^error\(\d+\)\.parameter\((?<parameter_idx>\d+)\)$/
              parameter_idx = parameter_idx.to_i
              if response[:errors][error_idx][:parameters].length <= parameter_idx
                response[:errors][error_idx][:parameters] << {}
                raise if response[:errors][error_idx][:parameters].length <= parameter_idx
              end
              response[:errors][error_idx][:parameters][parameter_idx] = v
            end
          end
        end
        response
      end

      def parse_get_basic_personal_data_nvp(nvp)
        # puts "parse_get_basic_personal_data_nvp: #{nvp}"
        response = {
          :errors => [
          ],
          :personal_data => {
          }
        }
        idx = nil
        key = nil
        pairs = nvp.split "&"
        pairs.each do |pair|
          n,v = pair.split "="
          n = CGI.unescape n
          v = CGI.unescape v
          case n
          when "responseEnvelope.timestamp"
            response[:timestamp] = v
          when "responseEnvelope.ack"
            response[:ack] = v
          when "responseEnvelope.correlationId"
            response[:correlation_id] = v
          when "responseEnvelope.build"
            # do nothing

          when /response\.personalData\((\d+)\)\.personalDataKey/
            idx = $1
            case v
            when "http://axschema.org/contact/country/home"
              key = :country
            when "http://axschema.org/contact/email"
              key = :email
            when "http://axschema.org/namePerson/first"
              key = :first_name
            when "http://axschema.org/namePerson/last"
              key = :last_name
            when "http://schema.openid.net/contact/fullname"
              key = :full_name
            when "https://www.paypal.com/webapps/auth/schema/payerID"
              key = :payer_id
            end

          when /response\.personalData\((\d+)\)\.personalDataValue/
            if $1 == idx
              response[:personal_data][key] = v
            else
              # puts "idx:#{idx} is out of sync with $1:#{$1} for key:#{key}"
            end

          when /^error\((?<error_idx>\d+)\)/
            error_idx = error_idx.to_i
            if response[:errors].length <= error_idx
              response[:errors] << { :parameters => [] }
              raise if response[:errors].length <= error_idx
            end
            case n
            when /^error\(\d+\)\.errorId$/
              response[:errors][error_idx][:error_id] = v
=begin
# Client should implement these with logging. PayPal doesn't distinguish
# between errors which can be corrected by the user and errors which need
# to be corrected by a developer or merchant, say, in configuration.
#             case v
#             when "520002"
#             when
=end            
            when /^error\(\d+\)\.domain$/
              response[:errors][error_idx][:domain] = v
            when /^error\(\d+\)\.subdomain$/
              response[:errors][error_idx][:subdomain] = v
            when /^error\(\d+\)\.severity$/
              response[:errors][error_idx][:severity] = v
            when /^error\(\d+\)\.category$/
              response[:errors][error_idx][:category] = v
            when /^error\(\d+\)\.message$/
              response[:errors][error_idx][:message] = v
            when /^error\(\d+\)\.parameter\((?<parameter_idx>\d+)\)$/
              parameter_idx = parameter_idx.to_i
              if response[:errors][error_idx][:parameters].length <= parameter_idx
                response[:errors][error_idx][:parameters] << {}
                raise if response[:errors][error_idx][:parameters].length <= parameter_idx
              end
              response[:errors][error_idx][:parameters][parameter_idx] = v
            end
          end
        end
        response
      end

=begin
Any API call can be submit through a third party process with your credentials. The merchant would need to add your API username to your account and then you submit the API call with your credentials and include the variable "SUBJECT" and set the value to be the merchants e-mail address. 
=end

      public
      def authorization_header url, access_token, access_token_verifier
        timestamp = Time.now.to_i.to_s
        signature = authorization_signature url, timestamp, access_token, access_token_verifier
        { 'X-PP-AUTHORIZATION' => "token=#{access_token},signature=#{signature},timestamp=#{timestamp}" }
      end

      public
      def authorization_signature url, timestamp, access_token, access_token_verifier
        # no query params, but if there were, this is where they'd go
        query_params = {}
        key = [
          URI.encode(@password),
          URI.encode(access_token_verifier),
        ].join("&")

        params = query_params.dup.merge({
          "oauth_consumer_key" => @login,
          "oauth_version" => "1.0",
          "oauth_signature_method" => "HMAC-SHA1",
          "oauth_token" => access_token,
          "oauth_timestamp" => timestamp,
        })
        sorted_params = Hash[params.sort]
        sorted_query_string = sorted_params.to_query
        # puts "sorted_query_string: #{sorted_query_string}"

        base = [
          "POST",
          URI.encode(url),
          URI.encode(sorted_query_string)
        ].join("&")

        hexdigest = OpenSSL::HMAC.hexdigest('sha1', key, base)
        Base64.encode64(hexdigest).chomp
      end

      private
      def setup_purchase(options)
        commit('Pay', build_adaptive_payment_pay_request(options))
      end
    end
  end
end
