# encoding: utf-8

require './slack-adaptor'
require './twitch-adaptor'
require 'eventmachine'
require 'when'
require 'circular_queue'
require 'set'

require 'optparse'

class Bot
  def initialize(announced: [], mode: :testing)
    @announced_stream_ids = Set.new(announced)
    @mode = mode
  end
  
  def setup
    settings = JSON.parse(File.read("settings.json"))
    @slacks = Hash[settings.collect { |v| [v.fetch('name'), SlackAdaptor.new(v, @mode)]}]

    #@sa = SlackAdaptor.new(settings)

    @ta = TwitchAdaptor.new
    @streams = []

    # A simple set of all Twitch usernames we track
    @twitch_usernames = Set.new
    settings.each { |slack| @twitch_usernames.merge(slack.fetch('twitch-usernames')) }

    # A mapping from a given Twitch username to the a list of Slacks on which to announce it.
    @twitches_to_slacks = Hash.new {|h,k| h[k] = [] }
    settings.each do |slack|
      slack.fetch('twitch-usernames').each do |twitch|
        @twitches_to_slacks[twitch.downcase] << slack.fetch('name')
      end
    end
    
    # @twitch_usernames = ["minimaxz", "rooneg", "bmemike", "walkingeye", "tybs1508", "verylowsodium", "zheluzhe",
    #                      "richshay", "lsv",  # goodstuff
    #                      "oarsman79", "haumph", "jonnymagic00",  # requested by walkingeyerobot
    #                     ]

  end

  def go
    EventMachine.run do
      setup

      #refresh_twitch_usernames⏲.then do
      #refresh_online_streams⏲
      #end

      #EventMachine::PeriodicTimer.new(3600) do
      #  refresh_twitch_usernames⏲
      #end

      refresh_online_streams⏲.then do
        notify_of_new_streams
      end
      EventMachine::PeriodicTimer.new(60) do
        refresh_online_streams⏲.then do
          notify_of_new_streams
        end
      end

    end
  end

  def notify_of_new_streams
    @streams.each do |stream|
      puts "considering announcing #{stream.username} id #{stream.id} #{stream.stream_name}"
      unless @announced_stream_ids.include?(stream.id)
        @twitches_to_slacks[stream.username].each do |slackname|
          puts "announcing #{stream.username} to #{slackname}"
          @slacks[slackname].notify⏲({text: ("<http://twitch.tv/#{stream.username}|twitch.tv/#{stream.username}> has gone live — #{stream.game_name} — \"#{stream.stream_name}\" <#{stream.preview_url}| >")})
        end
        @announced_stream_ids << stream.id
      end
    end
    ann_str = @streams.map(&:id).join(',')
    puts "can restart with: #{@mode == :prod ? "-p" : ""} #{ann_str.empty? ? "" : "-a #{ann_str}"}"
    puts
  end

  # def refresh_twitch_usernames⏲
  #   deferred = When.defer

  #   promise = @sa.users⏲
  #   promise.then do |users|
  #     @twitch_usernames = users.map do |user|
  #       next nil if user['profile']['title'].nil?
  #       result = user['profile']['title'].match(/twitch\.tv\/(.*)/)
  #       next nil if result.nil?
  #       result[1]
  #     end
  #     @twitch_usernames.compact!

  #     puts "Refreshed twitch usernames: #{@twitch_usernames.inspect}"
  #     deferred.resolver.resolve
  #   end

  #   return deferred.promise
  # end

  def refresh_online_streams⏲
    deferred = When.defer

    puts Time.now.iso8601
    puts "Querying twitch usernames: #{@twitch_usernames.inspect}"
    @streams = []
    promise = @ta.streams⏲(@twitch_usernames.to_a)
    promise.then do |streams|
      @streams = streams
      #puts "#{@streams.inspect}"
      puts "Refreshed online twitch streams: #{streams.map(&:username)}"
      deferred.resolver.resolve
    end

    return deferred.promise
  end
end



if $0 == __FILE__
  options = {:mode => :testing}
  OptionParser.new do |opts|
    opts.banner = "Usage: main.rb [options]"
    opts.on("-a", "--announced a,b,c", Array, "List of already announced stream ids") do |ann|
      options[:announced] = ann.map {|v| v.to_i}
    end
    opts.on("-p", "--prod", "Run as production (default testing)") do |p|
      options[:mode] = p ? :prod : :testing
    end
  end.parse!

  puts options
  Bot.new(announced: options[:announced], mode: options[:mode]).go
end
