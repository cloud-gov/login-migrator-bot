require 'spec_helper'
require_relative '../cf_client'

RSpec.describe CFClient do
  let(:client_id) { 'test_client_id' }
  let(:client_secret) { 'test_client_secret' }
  let(:uaa_url) { 'https://uaa.example.com' }
  let(:domain_name) { 'example.com' }
  let(:cf_client) { described_class.new(client_id, client_secret, uaa_url) }
  let(:mock_token) { double('OAuth2::AccessToken', expires_in: 43200) } # 12 hours
  let(:mock_client) { instance_double(OAuth2::Client) }
  let(:mock_strategy) { instance_double(OAuth2::Strategy::ClientCredentials) }

  before do
    ENV['DOMAIN_NAME'] = domain_name
    allow(OAuth2::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:client_credentials).and_return(mock_strategy)
    allow(mock_strategy).to receive(:get_token).and_return(mock_token)
    allow(Time).to receive(:now).and_return(Time.new(2024, 1, 1, 12, 0, 0))
  end

  describe '#initialize' do
    it 'creates an OAuth2 client with correct parameters' do
      expect(OAuth2::Client).to receive(:new).with(client_id, client_secret, site: uaa_url).and_return(mock_client)
      described_class.new(client_id, client_secret, uaa_url)
    end

    it 'obtains an initial token' do
      expect(mock_strategy).to receive(:get_token).and_return(mock_token)
      described_class.new(client_id, client_secret, uaa_url)
    end

    it 'sets token expiry with safety buffer' do
      cf_client
      expected_expiry = Time.new(2024, 1, 1, 12, 0, 0) + 43200 - 300 # 12 hours minus 5 minutes
      expect(cf_client.instance_variable_get(:@token_expiry)).to eq(expected_expiry)
    end
  end

  describe '#api_url' do
    it 'returns the correct API URL based on DOMAIN_NAME' do
      expect(cf_client.api_url).to eq("https://api.#{domain_name}/v3")
    end
  end

  describe 'token refresh functionality' do
    context 'when token is not expired' do
      it 'does not refresh the token' do
        expect(mock_strategy).to receive(:get_token).once # Only during initialization
        
        response = double('response', parsed: { "resources" => [] })
        allow(mock_token).to receive(:get).and_return(response)
        
        cf_client.get_users
      end
    end

    context 'when token is expired' do
      before do
        # Fast forward time to after token expiry
        allow(Time).to receive(:now).and_return(Time.new(2024, 1, 2, 12, 0, 0))
      end

      it 'refreshes the token before making request' do
        new_mock_token = double('OAuth2::AccessToken', expires_in: 43200)
        expect(mock_strategy).to receive(:get_token).and_return(mock_token, new_mock_token)
        
        response = double('response', parsed: { "resources" => [] })
        allow(new_mock_token).to receive(:get).and_return(response)
        
        cf_client.get_users
      end
    end

    context 'when receiving 401 error' do
      it 'refreshes token and retries the request' do
        error_response = double('error_response', status: 401)
        error = OAuth2::Error.new(error_response)
        
        new_mock_token = double('OAuth2::AccessToken', expires_in: 43200)
        success_response = double('response', parsed: { "resources" => [] })
        
        expect(mock_token).to receive(:get).and_raise(error)
        expect(mock_strategy).to receive(:get_token).twice.and_return(mock_token, new_mock_token)
        expect(new_mock_token).to receive(:get).and_return(success_response)
        
        result = cf_client.get_users
        expect(result).to eq([])
      end
    end

    context 'when receiving non-401 error' do
      it 'raises the error without retrying' do
        error_response = double('error_response', status: 500)
        error = OAuth2::Error.new(error_response)
        
        expect(mock_token).to receive(:get).and_raise(error)
        expect(mock_strategy).to receive(:get_token).once # Only during initialization
        
        expect { cf_client.get_users }.to raise_error(OAuth2::Error)
      end
    end
  end

  describe '#get_users' do
    let(:users_response) do
      {
        "resources" => [
          { "guid" => "user1-guid", "username" => "user1@example.com" },
          { "guid" => "user2-guid", "username" => "user2@example.com" }
        ]
      }
    end

    before do
      response = double('response', parsed: users_response)
      allow(mock_token).to receive(:get).with("#{cf_client.api_url}/users?order_by=-created_at").and_return(response)
    end

    it 'fetches users with correct ordering' do
      result = cf_client.get_users
      expect(result).to eq(users_response["resources"])
    end
  end

  describe '#get_user_by_username' do
    let(:username) { 'test@example.com' }
    let(:user_response) do
      {
        "resources" => [
          { "guid" => "user-guid", "username" => username }
        ]
      }
    end

    before do
      response = double('response', parsed: user_response)
      allow(mock_token).to receive(:get).with("#{cf_client.api_url}/users?usernames=#{CGI.escape(username)}").and_return(response)
    end

    it 'fetches user by username with proper encoding' do
      result = cf_client.get_user_by_username(username)
      expect(result).to eq(user_response["resources"])
    end

    it 'properly encodes special characters in username' do
      special_username = 'user+test@example.com'
      response = double('response', parsed: { "resources" => [] })
      
      expect(mock_token).to receive(:get).with("#{cf_client.api_url}/users?usernames=user%2Btest%40example.com").and_return(response)
      
      cf_client.get_user_by_username(special_username)
    end
  end

  describe '#get_user_roles' do
    let(:user_guid) { 'user-guid-123' }
    let(:roles_response) do
      {
        "resources" => [
          {
            "type" => "organization_user",
            "relationships" => {
              "organization" => { "data" => { "guid" => "org-guid" } }
            }
          }
        ]
      }
    end

    before do
      response = double('response', parsed: roles_response)
      allow(mock_token).to receive(:get).with("#{cf_client.api_url}/roles?user_guids=#{user_guid}&include=organization,space").and_return(response)
    end

    it 'fetches user roles with included relationships' do
      result = cf_client.get_user_roles(user_guid)
      expect(result).to eq(roles_response["resources"])
    end
  end

  describe '#copy_role' do
    let(:new_user_guid) { 'new-user-guid' }
    let(:response) { double('response', status: 201) }

    context 'with organization role' do
      let(:role) do
        {
          "type" => "organization_user",
          "relationships" => {
            "organization" => { "data" => { "guid" => "org-guid" } }
          }
        }
      end

      it 'copies role with organization relationship' do
        expected_body = {
          type: "organization_user",
          relationships: {
            user: { data: { guid: new_user_guid } },
            organization: { "data" => { "guid" => "org-guid" } }
          }
        }.to_json

        expect(mock_token).to receive(:post).with(
          "#{cf_client.api_url}/roles",
          headers: { 'Content-Type' => 'application/json' },
          body: expected_body
        ).and_return(response)

        result = cf_client.copy_role(role, new_user_guid)
        expect(result).to eq(response)
      end
    end

    context 'with space role' do
      let(:role) do
        {
          "type" => "space_developer",
          "relationships" => {
            "space" => { "data" => { "guid" => "space-guid" } }
          }
        }
      end

      it 'copies role with space relationship' do
        expected_body = {
          type: "space_developer",
          relationships: {
            user: { data: { guid: new_user_guid } },
            space: { "data" => { "guid" => "space-guid" } }
          }
        }.to_json

        expect(mock_token).to receive(:post).with(
          "#{cf_client.api_url}/roles",
          headers: { 'Content-Type' => 'application/json' },
          body: expected_body
        ).and_return(response)

        result = cf_client.copy_role(role, new_user_guid)
        expect(result).to eq(response)
      end
    end

    context 'with expired token during request' do
      let(:role) do
        {
          "type" => "organization_user",
          "relationships" => {}
        }
      end

      it 'handles token refresh on 401 error' do
        error_response = double('error_response', status: 401)
        error = OAuth2::Error.new(error_response)
        new_mock_token = double('OAuth2::AccessToken', expires_in: 43200)
        
        expect(mock_token).to receive(:post).and_raise(error)
        expect(mock_strategy).to receive(:get_token).and_return(mock_token, new_mock_token)
        expect(new_mock_token).to receive(:post).and_return(response)
        
        result = cf_client.copy_role(role, new_user_guid)
        expect(result).to eq(response)
      end
    end
  end

  describe '#get_organization' do
    let(:org_guid) { 'org-guid-123' }
    let(:org_response) { { "guid" => org_guid, "name" => "Test Org" } }

    before do
      response = double('response', parsed: org_response)
      allow(mock_token).to receive(:get).with("#{cf_client.api_url}/organizations/#{org_guid}").and_return(response)
    end

    it 'fetches organization by guid' do
      result = cf_client.get_organization(org_guid)
      expect(result).to eq(org_response)
    end
  end

  describe '#get_space' do
    let(:space_guid) { 'space-guid-123' }
    let(:space_response) { { "guid" => space_guid, "name" => "Test Space" } }

    before do
      response = double('response', parsed: space_response)
      allow(mock_token).to receive(:get).with("#{cf_client.api_url}/spaces/#{space_guid}").and_return(response)
    end

    it 'fetches space by guid' do
      result = cf_client.get_space(space_guid)
      expect(result).to eq(space_response)
    end
  end

  describe '#delete_user' do
    let(:user_guid) { 'user-guid-123' }
    let(:cc_url) { "#{cf_client.api_url}/users/#{user_guid}" }
    let(:uaa_delete_url) { "#{uaa_url}/Users/#{user_guid}" }
    let(:response) { double('response', status: 204) }
    let(:uaa_response) { double('uaa_response', status: 200) }

    before do
      allow(mock_token).to receive(:delete).with(cc_url).and_return(response)
      allow(mock_token).to receive(:delete)
        .with(uaa_delete_url, headers: { 'Content-Type' => 'application/json' })
        .and_return(uaa_response)
    end

    it 'deletes the user from the Cloud Controller' do
      expect(mock_token).to receive(:delete).with(cc_url).and_return(response)
      cf_client.delete_user(user_guid)
    end

    it 'also deletes the user from UAA (SCIM)' do
      expect(mock_token).to receive(:delete)
        .with(uaa_delete_url, headers: { 'Content-Type' => 'application/json' })
        .and_return(uaa_response)
      cf_client.delete_user(user_guid)
    end

    it 'returns the Cloud Controller response' do
      result = cf_client.delete_user(user_guid)
      expect(result).to eq(response)
    end

    context 'when the Cloud Controller record is already gone (404)' do
      let(:not_found_response) { double('error_response', status: 404) }
      let(:not_found_error) do
        OAuth2::Error.allocate.tap { |e| e.instance_variable_set(:@response, not_found_response) }
      end

      before do
        allow(not_found_error).to receive(:response).and_return(not_found_response)
        allow(mock_token).to receive(:delete).with(cc_url).and_raise(not_found_error)
      end

      it 'is idempotent and still deletes the UAA record' do
        expect(mock_token).to receive(:delete)
          .with(uaa_delete_url, headers: { 'Content-Type' => 'application/json' })
          .and_return(uaa_response)
        expect { cf_client.delete_user(user_guid) }.not_to raise_error
      end
    end

    context 'when the UAA record is already gone (404)' do
      let(:not_found_response) { double('error_response', status: 404) }
      let(:not_found_error) do
        OAuth2::Error.allocate.tap { |e| e.instance_variable_set(:@response, not_found_response) }
      end

      before do
        allow(not_found_error).to receive(:response).and_return(not_found_response)
        allow(mock_token).to receive(:delete)
          .with(uaa_delete_url, headers: { 'Content-Type' => 'application/json' })
          .and_raise(not_found_error)
      end

      it 'is idempotent and does not raise' do
        expect { cf_client.delete_user(user_guid) }.not_to raise_error
      end
    end

    context 'when a delete fails with a non-404 error' do
      let(:forbidden_response) { double('error_response', status: 403) }
      let(:forbidden_error) do
        OAuth2::Error.allocate.tap { |e| e.instance_variable_set(:@response, forbidden_response) }
      end

      before do
        allow(forbidden_error).to receive(:response).and_return(forbidden_response)
        allow(mock_token).to receive(:delete)
          .with(uaa_delete_url, headers: { 'Content-Type' => 'application/json' })
          .and_raise(forbidden_error)
      end

      it 'propagates the error' do
        expect { cf_client.delete_user(user_guid) }.to raise_error(OAuth2::Error)
      end
    end

    context 'with expired token' do
      it 'refreshes token before deletion' do
        # Instantiate the client (and consume the initial get_token) before
        # setting expectations on the refresh call.
        cf_client

        # Fast forward time to after token expiry
        allow(Time).to receive(:now).and_return(Time.new(2024, 1, 2, 12, 0, 0))

        new_mock_token = double('OAuth2::AccessToken', expires_in: 43200)
        expect(mock_strategy).to receive(:get_token).and_return(new_mock_token)
        allow(new_mock_token).to receive(:delete).with(cc_url).and_return(response)
        allow(new_mock_token).to receive(:delete)
          .with(uaa_delete_url, headers: { 'Content-Type' => 'application/json' })
          .and_return(uaa_response)

        result = cf_client.delete_user(user_guid)
        expect(result).to eq(response)
      end
    end
  end

  describe 'concurrent request handling' do
    it 'handles multiple requests with expired token correctly' do
      # Fast forward time to after token expiry
      allow(Time).to receive(:now).and_return(Time.new(2024, 1, 2, 12, 0, 0))
      
      new_mock_token = double('OAuth2::AccessToken', expires_in: 43200)
      # Should only get new token once even with multiple requests
      expect(mock_strategy).to receive(:get_token).twice.and_return(mock_token, new_mock_token)
      
      response1 = double('response1', parsed: { "resources" => [] })
      response2 = double('response2', parsed: { "name" => "Test Org" })
      
      allow(new_mock_token).to receive(:get).with("#{cf_client.api_url}/users?order_by=-created_at").and_return(response1)
      allow(new_mock_token).to receive(:get).with("#{cf_client.api_url}/organizations/org-123").and_return(response2)
      
      cf_client.get_users
      cf_client.get_organization('org-123')
    end
  end
end