module MonitorHelper

  def get_cloud_environment(uaa_url)
    environment = 'unknown'
    if (uaa_url.index("uaa."))
      environment = uaa_url[uaa_url.index("uaa.")+4..-1]
    end

    environment
  end
end
