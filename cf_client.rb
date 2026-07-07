#!/usr/bin/env ruby
require 'rubygems'
require 'oauth2'
require 'cgi'

class CFClient
  def initialize(client_id, client_secret, uaa_url)
    @client = OAuth2::Client.new(
      client_id,
      client_secret,
      :site => uaa_url)
    @client_id = client_id
    @client_secret = client_secret
    @uaa_url = uaa_url
    get_new_token
  end

  def api_url
    "https://api.#{ENV["DOMAIN_NAME"]}/v3"
  end

  def get_users
    make_request { @token.get("#{api_url}/users?order_by=-created_at") }
      .parsed["resources"]
  end

  def get_user_by_username(username)
    make_request { @token.get("#{api_url}/users?usernames=#{CGI.escape(username)}") }
      .parsed["resources"]
  end

  def get_user_roles(user_guid)
    make_request { @token.get("#{api_url}/roles?user_guids=#{user_guid}&include=organization,space") }
      .parsed["resources"]
  end

  def copy_role(role, new_user_guid)
    req = {
      type: role["type"],
      relationships: {
        user: {
          data: {
            guid: new_user_guid
          }
        }
      }
    }
    
    # Add organization relationship if present
    if role["relationships"]["organization"]
      req[:relationships][:organization] = role["relationships"]["organization"]
    end
    
    # Add space relationship if present
    if role["relationships"]["space"]
      req[:relationships][:space] = role["relationships"]["space"]
    end
    
    make_request do
      @token.post(
        "#{api_url}/roles",
        headers: { 'Content-Type' => 'application/json' },
        body: req.to_json
      )
    end
  end  

  def get_organization(org_guid)
    make_request { @token.get("#{api_url}/organizations/#{org_guid}") }
      .parsed
  end

  def get_space(space_guid)
    make_request { @token.get("#{api_url}/spaces/#{space_guid}") }
      .parsed
  end

  def delete_user(user_guid)
    # Mirrors `cf delete-user`: remove the record from the Cloud Controller
    # first, then from UAA (SCIM), so both databases stay in sync. Deleting
    # only from the Cloud Controller leaves an orphaned UAA record behind.
    # Both deletes tolerate a 404 so the operation is idempotent and safe to
    # re-run against a partially-deleted user.
    cc_response = delete_with_404_tolerance("#{api_url}/users/#{user_guid}")

    # The Cloud Controller user guid is the same value as the UAA SCIM id for
    # UAA-backed users, so it can be used directly against the UAA endpoint.
    delete_with_404_tolerance(
      "#{@uaa_url}/Users/#{user_guid}",
      headers: { 'Content-Type' => 'application/json' }
    )

    cc_response
  end

  private

  def delete_with_404_tolerance(url, headers: nil)
    make_request do
      if headers
        @token.delete(url, headers: headers)
      else
        @token.delete(url)
      end
    end
  rescue OAuth2::Error => e
    raise e unless e.response && e.response.status == 404
    puts "Delete target already absent (404), continuing: #{url}"
    e.response
  end

  def get_new_token
    puts "Obtaining new OAuth2 token..."
    @token = @client.client_credentials.get_token
    @token_expiry = Time.now + (@token.expires_in || 43200) - 300 # Subtract 5 minutes for safety
    puts "Token obtained, expires at: #{@token_expiry}"
  end

  def token_expired?
    Time.now >= @token_expiry
  end

  def refresh_token_if_needed
    if token_expired?
      puts "Token expired, refreshing..."
      get_new_token
    end
  end

  def make_request(&block)
    refresh_token_if_needed
    
    begin
      yield
    rescue OAuth2::Error => e
      if e.response.status == 401
        puts "Got 401 error, attempting to refresh token and retry..."
        get_new_token
        yield
      else
        raise e
      end
    end
  end
end