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

    @token = @client.client_credentials.get_token;

  end

  def api_url
    "https://api.#{ENV["DOMAIN_NAME"]}/v3"
  end

  def get_users

    response = @token.get("#{api_url}/users?order_by=-created_at")
    return response.parsed["resources"];

  end

  def get_user_by_username(username)
    response = @token.get("#{api_url}/users?usernames=#{CGI.escape(username)}")
    return response.parsed["resources"]
  end

  def get_user_roles(user_guid)
    response = @token.get("#{api_url}/roles?user_guids=#{user_guid}&include=organization,space")
    return response.parsed["resources"]
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

    response = @token.post(
      "#{api_url}/roles",
      headers: { 'Content-Type' => 'application/json' },
      body: req.to_json
    )

    return response
  end  

  def get_organization(org_guid)
    response = @token.get("#{api_url}/organizations/#{org_guid}")
    return response.parsed
  end

  def get_space(space_guid)
    response = @token.get("#{api_url}/spaces/#{space_guid}")
    return response.parsed
  end

  def delete_user(user_guid)
    response = @token.delete("#{api_url}/users/#{user_guid}")
    return response
  end
  
end