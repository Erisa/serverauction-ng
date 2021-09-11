#!/usr/bin/env ruby

require 'json'
require 'bundler/setup'
Bundler.require(:default)
require 'net/http'

class String
  def is_integer?
    self.to_i.to_s == self
  end
end

token = ENV['DISCORD_TOKEN']

time_taken = 0
def update_list(old_servers)
  init_time = Time.now
  source = "https://www.hetzner.com/a_hz_serverboerse/live_data.json?m=#{init_time}"
  resp = Net::HTTP.get_response(URI.parse(source))
  data = JSON.parse(resp.body)
  servers = {}
  data['server'].each {|server|
    servers[server['key']] = server
  }
  time_taken = Time.now - init_time
  data['server'] = servers
  compare_servers(old_servers, servers) unless old_servers == {}
  return data
end

def compare_servers(old_servers, servers)
  channel = $bot.channel(734625388184993813)
  old_servers.each {|key, server|
    newserv = servers[key]
    if newserv.nil?
      channel.send_message("Server `#{key}` was bought or removed!", false, build_embed(server, 0xff0000))
    elsif server['price'] != newserv['price']
      channel.send_message("Server `#{key}` changed price: `€#{server['price'].to_f.round(2)}` => `€#{newserv['price'].to_f.round(2)}`", false, build_embed(newserv, 0x00ffff))
    end
  }
  servers.each {|key, server|
    old = old_servers[key]
    if old.nil?
      channel.send_message("Server `#{key}` added!", false, build_embed(server))
    end
  }
end


data = update_list({})
servers = data['server']

puts "Downloaded and parsed URL with #{servers.length} auction servers in #{time_taken} seconds!"

$bot = Discordrb::Commands::CommandBot.new token: token, prefix: '!'

def build_embed(server, colour = 0xd084)
  priceDrop = server['fixed_price'] ? 'N/A' : server['next_reduce_hr']
  ecc = server['is_ecc'] ? '(ECC)' : '(non-ECC)'

  if server['specialHdd'] == ''
    if server['specials'].include?('SSD')
      specialHdd = 'SSD'
    elsif server['specials'].include?('DC SSD')
      specialHdd = 'DC SSD'
    elsif server['specials'].include?('Ent. HDD')
      specialHdd = 'Ent HDD'
    else
      specialHdd = 'HDD'
    end
  else
    specialHdd = server['specialHdd']
  end

  raid_cont = 'N/A'
  if server['specials'].include?('HWR')
    raid_cont = 'Unknown'
    server['description'].each {|d|
      if d.include?('RAID')
        raid_cont = d
      end
    }
  end

  specials = server['specials'].count == 0 ? 'N/A' : server['specials'].join(', ')

  embed = Discordrb::Webhooks::Embed.new()
  embed.colour = colour
  embed.author = Discordrb::Webhooks::EmbedAuthor.new(name: "Hetzner #{server['name']} (#{server['key']}) - €#{server['price'].to_f.round(2)}")

  embed.add_field(name: "CPU", value: "#{server['cpu']} (Bench: #{server['cpu_benchmark']})", inline: true)
  embed.add_field(name: "RAM", value: "#{server['ram_hr']} #{ecc}", inline: true)
  embed.add_field(name: "Drives:", value: "#{server['hdd_hr']} #{specialHdd}", inline: true)
  embed.add_field(name: "Next price drop", value: priceDrop, inline: true)
  embed.add_field(name: "Datacenter", value: server['datacenter'][0], inline: true)
  embed.add_field(name: "Special attributes", value: specials , inline: true)
  embed.add_field(name: "Hardware RAID Controller", value: raid_cont)
  embed
end

$bot.command :server do |event, searchQuery, num|
  puts searchQuery
  count = 0
  chosen_count = 0
  if searchQuery == 'random' || searchQuery.nil?
    server = servers[servers.keys.sample]
  else
    server_search = servers.select {|key, server| server["freetext"].downcase.include? searchQuery.downcase }
    if server_search.count == 0
      event.respond 'I couldn\'t find a Hetzner auction server matching your search in my cache!'
      next
    else

      count = server_search.count
      if !num.nil? && num.is_integer?
        chosen_count = num.to_i
      else
        chosen_count = rand(1..count)
      end

      server = server_search[server_search.keys[chosen_count - 1]]
      if server.nil? || chosen_count < 1
        event.respond "I found `#{count}` results, but you asked for result `#{chosen_count}`, which does not exist."
        next
      end

    end
  end
  embed = build_embed(server)
  begin
    msg = 'Here you go:'
    if count > 1
      msg = "I found `#{count}` results. Here is result `#{chosen_count}`:"
    end
    event.respond(msg, false, embed)
  rescue StandardError => e
    "an error occured: ```rb\n#{e}```\nserver id: #{server['key'].to_s}"
  end

end

$bot.command(:eval, help_available: false) do |event, *code|
  break unless event.user.id == 228574821590499329 # Replace number with your ID
  begin
    eval code.join(' ')
  rescue StandardError => e
    "an error occured: ```rb\n#{e}```"
  end
end

$bot.command(:update) do |event|
  data = update_list(servers)
  servers = data['server']
  event.respond "Updated to list `#{data['hash']}` with `#{servers.count}` auction servers in #{time_taken.to_f.to_s} seconds!"
end

$bot.run(true)

loop do
  data = update_list(servers)
  servers = data['server']
  puts "Updated to list `#{data['hash']}` with `#{servers.count}` auction servers in #{time_taken.to_f.to_s} seconds!"
  sleep 180
end