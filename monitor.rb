# Note: if this all looks vaguely familiar, it's because this is based on the code in the sandbox-bot, but modified to copy permissions from cloud.gov users to login.gov users instead of monitoring for sandbox quota usage

require_relative './cf_client'
require_relative './monitor_helper'
require 'slack-notifier'

include MonitorHelper

$stdout.sync = true

@notifier = Slack::Notifier.new ENV["SLACK_HOOK"],
              channel: "#cloud-gov",
              username: "sandboxbot"

@cf_client = CFClient.new(ENV["CLIENT_ID"], ENV["CLIENT_SECRET"], ENV["UAA_URL"])
@last_user_date = nil
@environment = get_cloud_environment(ENV["UAA_URL"])

def send_slack_notification(msg)
  puts msg
  if (ENV["DO_SLACK"] === true || ENV["DO_SLACK"].downcase == "true")
    begin
      @notifier.ping msg, icon_emoji: ":cloud:"
    rescue
      puts "Could not post #{msg} to slack"
    end
  end
end

def get_role_context(role)
  context = ""
  if role["relationships"]["organization"] && role["relationships"]["organization"]["data"]
    org_guid = role["relationships"]["organization"]["data"]["guid"]
    begin
      org = @cf_client.get_organization(org_guid)
      context = "in organization '#{org["name"]}'"
    rescue => e
      context = "in organization '#{org_guid}' (name lookup failed)"
    end
  elsif role["relationships"]["space"] && role["relationships"]["space"]["data"]
    space_guid = role["relationships"]["space"]["data"]["guid"]
    begin
      space = @cf_client.get_space(space_guid)
      # Also get the organization name for the space
      if space["relationships"]["organization"]["data"]
        org_guid = space["relationships"]["organization"]["data"]["guid"]
        org = @cf_client.get_organization(org_guid)
        context = "in space '#{space["name"]}' (organization '#{org["name"]}')"
      else
        context = "in space '#{space["name"]}'"
      end
    rescue => e
      context = "in space '#{space_guid}' (name lookup failed)"
    end
  end
  return context
end

def should_delete_source_user?
  ENV["DELETE_SOURCE_USER"] && ENV["DELETE_SOURCE_USER"].downcase == "true"
end

def process_new_users

  last_user_date = nil
	users = @cf_client.get_users

  users.each do |user|

    is_new_org = false

    # save the date of the most recent user added
    if last_user_date.nil? || last_user_date < user["created_at"]
      last_user_date = user["created_at"]
    end

    #break out of processing if we already processed this user in previous run
    break if @last_user_date && @last_user_date >= user["created_at"]

  	email = user["username"]
    origin = user["origin"]
    next if origin != "login.gov"

    # Logic from here on is:
    #   Check to see if there is another user with the same email address for cloud.gov origin
    #   If there is, copy the permissions from the cloud.gov user to the login.gov user 

    # Find users with same username
    matching_users = @cf_client.get_user_by_username(email)
    
    # Find the cloud.gov origin user
    cloud_gov_user = matching_users.find { |u| u["origin"] == "cloud.gov" }
    
    if cloud_gov_user
      puts "Found matching cloud.gov user for #{email}"
      
      # Get roles from the cloud.gov user
      cloud_gov_roles = @cf_client.get_user_roles(cloud_gov_user["guid"])
            
      # Track successful copies
      successful_copies = 0
      failed_copies = 0
      
      # Copy each role to the login.gov user
      cloud_gov_roles.each do |role|
        begin
          response = @cf_client.copy_role(role, user["guid"])
          role_context = get_role_context(role)
          puts "Copied role #{role["type"]} #{role_context} to login.gov user #{email}, status: #{response.status}"
          successful_copies += 1          
        rescue => e
          puts "Error copying role #{role["type"]} for user #{email}: #{e.message}"
          failed_copies += 1
        end
      end
      
      msg = "Copied #{successful_copies} of #{cloud_gov_roles.length} permissions from cloud.gov user to new login.gov user #{user["username"]} on #{@environment}"
      
      # Delete the cloud.gov user if all roles were copied successfully and DELETE_SOURCE_USER is true
      if failed_copies == 0 && cloud_gov_roles.length > 0 && should_delete_source_user?
        begin
          delete_response = @cf_client.delete_user(cloud_gov_user["guid"])
          puts "Deleted cloud.gov origin user #{email}, status: #{delete_response.status}"
          msg += " - cloud.gov origin user deleted"
        rescue => e
          puts "Error deleting cloud.gov origin user #{email}: #{e.message}"
          msg += " - ERROR: failed to delete cloud.gov origin user"
        end
      elsif failed_copies > 0
        puts "Not deleting cloud.gov origin user #{email} due to #{failed_copies} failed role copies"
      elsif !should_delete_source_user?
        puts "Not deleting cloud.gov origin user #{email} - DELETE_SOURCE_USER not set to true"
      end
    else
      msg = "No matching cloud.gov user found for new login.gov user #{user["username"]} on #{@environment}"
    end

    send_slack_notification(msg)
  end

  # save the date of the most recent user processed so that we can
  # ignore users added before that date on the next iteration

  @last_user_date = last_user_date

end

while true
  puts "Getting users on #{@environment}"
  process_new_users
  puts @last_user_date
  sleep(ENV["SLEEP_TIMEOUT"].to_i)
end
