require 'spec_helper'
require_relative '../monitor_helper'

RSpec.describe MonitorHelper do
  include MonitorHelper

  describe '#get_cloud_environment' do
    context 'when uaa_url contains "uaa."' do
      it 'extracts environment from production URL' do
        uaa_url = 'https://uaa.fr.cloud.gov'
        expect(get_cloud_environment(uaa_url)).to eq('fr.cloud.gov')
      end

      it 'extracts environment from staging URL' do
        uaa_url = 'https://uaa.fr-stage.cloud.gov'
        expect(get_cloud_environment(uaa_url)).to eq('fr-stage.cloud.gov')
      end
    end

    context 'when uaa_url does not contain "uaa."' do
      it 'returns "unknown"' do
        uaa_url = 'https://auth.example.com'
        expect(get_cloud_environment(uaa_url)).to eq('unknown')
      end
    end
  end
end