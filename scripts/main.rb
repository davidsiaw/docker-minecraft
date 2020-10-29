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
    begin
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

            unless msg_to_discord.start_with?('<')
              msg_to_discord.gsub!('lost connection', '接続が切断されました')
              msg_to_discord.gsub!('Disconnected', '断線')
              msg_to_discord.gsub!('left the game', 'はゲームから退出しました')
              msg_to_discord.gsub!('joined the game', 'はゲームに入りました')

              msg_to_discord.gsub!(/^(.*?) (was shot by )(.+?)\r?$/, '\1は\3に打たされた')
              msg_to_discord.gsub!(/^(.*?) (was slain by )(.+?)\r?$/, '\1は\3に殺された')
              msg_to_discord.gsub!(/^(.*?) (was impaled by )(.+?)\r?$/, '\1は\3に刺された')
              msg_to_discord.gsub!(/^(.*?) (was blown up by )(.+?)\r?$/, '\1は\3の爆発に死んだ')
              msg_to_discord.gsub!(/^(.*?) (was killed by )(.+?)\r?$/, '\1は\3に殺された')
              msg_to_discord.gsub!(/^(.*?) (got revenge on )(.+?)\r?$/, '\1は\3に復讐された')
              msg_to_discord.gsub!(/^(.*?) (has made the achievement )(.+?)\r?$/, '\1は\3のアチーブメントゲット')

              msg_to_discord.gsub!('fell from a high place', 'は高い場所から飛び降りた')
              msg_to_discord.gsub!('burned to death', 'は火に燃やされた')

              msg_to_discord.gsub!('fell off a ladder', 'はしごから転落した')
              msg_to_discord.gsub!('fell off some vines', 'はツタから転落した')
              msg_to_discord.gsub!('fell out of the water', 'は水から転落した')
              msg_to_discord.gsub!('fell into a patch of fire', 'は火に燃やされた')
              msg_to_discord.gsub!('fell into a patch of cacti', 'はサボテンにやられた')

              msg_to_discord.gsub!('tried to swim in lava', 'は')
              msg_to_discord.gsub!('blew up', 'が爆発された')
              msg_to_discord.gsub!('drowned', 'が溺れた')
              msg_to_discord.gsub!('withered away', 'は干からびた')
            end

            chan.send_message msg_to_discord if can_display
          end

          if %r{^\[[0-9]+:[0-9]+:[0-9]+\] \[Server thread/INFO\]: Done}.match(line)
            p line
            chan.send_message 'サーバー起動完了'
            logchan.send_message '[SERV] Start complete'
          end
        rescue StandardError => e
          puts 'Error sending message:'
          p e
        end
      end
    rescue StandardError => e
      puts '********************Error******************'
      p e
      begin
        logchan.send_message "[ERRO] #{e.message}"
        logchan.send_message "[ERRO] #{e.backtrace}"
        chan.send_message 'サーバーエラーが発生しました'
      rescue StandardError => e
        puts 'Could not send'
        p e
      end
      MyApp.quit!
    end
  end

  MyApp.set :bot, bot
  MyApp.set :stdin, stdin
  MyApp.set :logchan, logchan
  MyApp.run!

  puts 'Server shutting down'
  chan.send_message 'サーバーは停止しました'

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
      chan.send_message('サーバー起動中...')
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

        if message.start_with?('!') && event.author.id.to_s == ENV['ADMIN_ID'].to_s
          stdin.puts message[1..-1]

        else
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
      end

      start_minecraft(bot, chan, logchan, stdin, stdout, pid)
    end
  rescue PTY::ChildExited
    puts 'The child process exited!'
    chan.send_message 'サーバーは停止しました'
  end
end

start_server
