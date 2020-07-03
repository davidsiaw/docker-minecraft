# frozen_string_literal: true

require 'pty'
require 'discordrb'
require 'json'
require 'sinatra/base'

class MyApp < Sinatra::Base
  set :bind, '0.0.0.0'
  set :port, 25_001

  get '/' do
    logchan = settings.logchan
    bot = settings.bot
    stdin = settings.stdin

    begin
      logchan.send_message("[HTTP] Received command #{params['command']}")

      MyApp.quit! if params['command'] == 'stop'

      stdin.puts params['command']
    rescue StandardError => e
      puts "[HTTP] Error: #{e}"
    end
    "ok #{params['command']}"
  end
end

def start_minecraft(bot, chan, logchan, stdin, stdout, _pid)
  Thread.new do
    players = {}

    # Do stuff with the output here. Just printing to show it works
    stdout.each do |line|
      begin
        # remove colors
        line.gsub!(/\r?\e\[(K|\d+(;\d+)*m)/, '')

        infomatch = %r{^\[[0-9]+:[0-9]+:[0-9]+\] \[Server thread/INFO\]: (?<message>.+)}.match(line)

        p line

        if infomatch

          logchan.send_message("[INFO] #{infomatch[:message]}")

          joinmatch = /^(?<name>[^\<\>]+?) joined the game/.match(infomatch[:message])
          leftmatch = /^(?<name>[^\<\>]+?) left the game/.match(infomatch[:message])

          if joinmatch
            players[joinmatch[:name]] = true if joinmatch[:name]
          end

          can_display = false

          players.keys.each do |name|
            can_display = true if infomatch[:message].include?(name) && (players[name] == true)
          end

          if leftmatch
            players[leftmatch[:name]] = false if leftmatch[:name]
            can_display = true
          end

          can_display = false if infomatch[:message].start_with? '[Server]'
          can_display = false if infomatch[:message].start_with? '['

          msg_to_discord = infomatch[:message]

          user_list = chan.users

          msg_to_discord = msg_to_discord.gsub(/@[^ ]+/) do |mention|
            mention = mention[1..-1].strip

            matches = user_list.select { |user| user.username == mention || user.nick == mention }.map(&:id)

            if !matches.empty?
              matches.map { |x| "<@#{x}>" }.join(' ')
            else
              "@#{mention}"
            end
          end

          chan.send_message msg_to_discord if can_display
        end

        # [12:24:39] [Server thread/INFO]: azunyansan joined the game

        if %r{^\[[0-9]+:[0-9]+:[0-9]+\] \[Server thread/INFO\]: Done}.match(line)
          p line
          chan.send_message 'Minecraft server is ready for players to login.'
          logchan.send_message '[SERV] Start complete'
        end
      rescue StandardError => e
        puts 'Error sending message:'
        p e
      end
    end
  end

  MyApp.set :bot, bot
  MyApp.set :stdin, stdin
  MyApp.set :logchan, logchan
  MyApp.run!

  puts 'Server shutting down'
  chan.send_message 'Minecraft server is shutting down.'

  # stdout.each do |line|
  #  puts "[STOPPING] #{line}"
  # end

  bot.stop
end

def start_server
  cmd = '/start'

  bot = Discordrb::Bot.new token: ENV['DISCORD_TOKEN'], client_id: ENV['CLIENT_ID']

  channel_name = ENV['MINECRAFT_CHANNEL'] || 'bot-test'

  # bot.message(with_text: 'Ping!') do |event|
  #  event.respond 'Pong!'
  # end

  emodata = JSON.parse(File.read('emodata.json'))

  bot.run :async

  logchan = nil
  chan = nil

  loop do
    # looped code goes here:

    begin
      logchan = bot.find_channel('mcbotlog')[0]
      chan = bot.find_channel(channel_name.to_s)[0]
      chan.send_message('Minecraft server starting up...')
      logchan.send_message('[SERV] Start')
      break
    rescue StandardError => e
      puts "Can't find channels. retrying..."
    end
  end

  begin
    PTY.spawn(cmd) do |stdout, stdin, pid|
      bot.message(in: ["##{channel_name}"]) do |event|
        message = event.message.content

        p event.message

        message = message.scan(/./).map { |x| emodata.key?(x) ? ":#{emodata[x]}:" : x }.join

        emote_r = /\<:(?<emote_name>[^\:]+):[0-9]+\>/
        mention_r = /\<@(?<member_id>[0-9]+)\>/

        message = message.gsub(emote_r) { |x| ":#{emote_r.match(x)[:emote_name]}:" }
        message = message.gsub(mention_r) do |x|
          user = chan.server.member(mention_r.match(x)[:member_id].to_i)
          "@#{user.username}" if user
        end

        stdin.puts "say <#{event.author.username}> #{message}"
      end

      bot.message(containing: 'who is online') do |event|
        online = players.keys.select { |x| players[x] }

        text = online.join(', ')

        if !online.empty?
          event.respond "Players currently online: #{text}"
        else
          event.respond 'No one is online :('
        end
      end

      begin
        start_minecraft(bot, chan, logchan, stdin, stdout, pid)
      rescue Errno::EIO
        puts 'Errno:EIO error, but this probably just means ' \
             'that the process has finished giving output'
        chan.send_message 'Minecraft server is shutting down.'
      end
    end
  rescue PTY::ChildExited
    puts 'The child process exited!'
    chan.send_message 'Minecraft server is shutting down.'
  end
end

start_server
