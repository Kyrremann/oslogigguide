#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative './models'

require 'json'
require 'date'
require 'github/markup'
require 'httparty'
require 'rss'
require 'uri'

urls = [
  {
    'url': 'https://www.goldie.no/api/eventsEdge',
    'type': ''
  },
  {
    'url': 'https://www.blaaoslo.no/api/eventsEdge',
    'type': ''
  },
  {
    'url': 'https://www.rockefeller.no/api/eventsEdge',
    'type': ''
  },
  {
    'url': 'https://www.kafe-haerverk.com/api/events',
    'type': ''
  },
  {
    'url': 'https://demo.broadcastapp.no/api/layoutWidgetCors?limit=99&venue=mTP5efb3tQ&recommended=false&hostname=www-brewgata-no.filesusr.com&city=Oslo',
    'type': 'broadcast'
  },
  {
    'url': 'https://demo.broadcastapp.no/api/layoutWidgetCors?limit=99&venue=EBIs19AJFr&recommended=false&hostname=www-revolveroslo-no.filesusr.com&city=Oslo',
    'type': 'broadcast'
  },
  {
    'url': 'https://demo.broadcastapp.no/api/layoutWidgetCors?limit=99&venue=none&recommended=false&hostname=www.vaterlandoslo.no&city=Oslo&key=zXg-2T9s4NWH_NLD6R5KjsDgtT3aeWL2',
    'type': 'broadcast'
  },
  {
    'url': 'https://demo.broadcastapp.no/api/layoutWidgetCors?limit=99&venue=APJXjIH1ND&recommended=false&hostname=www-lufthavna-no.filesusr.com&city=Oslo',
    'type': 'broadcast'
  }
]

old_events = Dir.entries('_data/events').select { |f| File.file?("_data/events/#{f}") }.map { |f| f.sub('.json', '') }
events = []

# Scrape events from all sources
urls.each do |source|
  response = HTTParty.get(source[:url])
  payload = JSON.parse(response.body)
  if source[:type] == 'broadcast'
    payload['results'].each do |event|
      events << Event.from_broadcast(event)
    end
  else
    payload.each do |event|
      events << Event.from_events_edge(event)
    end
  end
end

events.sort_by!(&:start_time)

File.open('_data/metadata.json', 'w') do |file|
  file.puts({ updated_at: DateTime.now }.to_json)
end

puts "Scraped #{events.length} events."

# Compare with old events to find new or updated ones
new_events = events.reject { |event| old_events.include?(event.id) }

p "Found #{new_events.length} new events."

updated_events = events.select do |event|
  old_event_id = old_events.find { |oe| oe['id'] == event.id }
  next false if old_event_id.nil?

  old_event = Event.new(JSON.parse(File.read("_data/events/#{old_event_id}.json")))
  event.has_changed(old_event)
end

p "Found #{updated_events.length} updated events."

new_events.concat(updated_events)

if new_events.length < 10
  p "Less than 10 new/updated events, adding #{10 - new_events.length} older events to feed."
  events.last(10 - new_events.length).concat(new_events)
end

new_events.sort_by!(&:start_time)

rss = RSS::Maker.make('atom') do |maker|
  maker.channel.author = 'Kyrre Havik'
  maker.channel.title = 'Oslo Gig Guide'
  link = maker.channel.links.new_link
  link.href = 'https://kyrremann.no/oslogigguide/'
  link.rel = 'alternate'
  link.type = 'text/html'
  link = maker.channel.links.new_link
  link.href = 'https://kyrremann.no/oslogigguide/feed.xml'
  link.type = 'application/atom+xml'
  link.rel = 'self'
  maker.channel.about = 'https://kyrremann.no/plog/feed.xml'
  maker.channel.subtitle = 'Latest gigs and events in Oslo, Norway'
  maker.channel.updated = Time.now.to_s

  new_events.each do |event|
    change = ''

    if event.updated
      change = "<p>#{event.change[0]} changed from "#{event.change[1]}" to "#{event.send(event.change[0])}".</p>"
    end

    maker.items.new_item do |item|
      name = event.updated ? "#{event.name} (updated)" : event.name
      item.id = event.id
      item.title = name + event.start_time.strftime(' (%Y-%m-%d)')
      item.link = "https://kyrremann.no/oslogigguide/##{event.id}"
      item.summary = "#{name} at #{event.venue.name} on #{event.start_time.strftime('%Y-%m-%d %H:%M')}"
      item.content.type = 'html'
      item.content.content = <<~DESC
        #{change}
        <p>
        Venue: #{event.venue.name}<br/>
        Start: #{event.start_time.strftime('%Y-%m-%d %H:%M')}<br/>
        Tags: #{event.tags.join(', ')}
        </p>
        <br/>
        <p>
        #{GitHub::Markup.render('README.markdown', event.description)}
        </p>
        <br/>
        <p>
        Tickets: <a href=\"#{event.ticket_url}\">#{URI.parse(event.ticket_url).host}</a><br/>
        <a href=\"https://kyrremann.no/oslogigguide/assets/calendars/#{event.id}.ics\">Calender event</a>
        </p>
      DESC
      item.updated = event.updated_at
    end
  end
end

File.open('feed.xml', 'w') do |file|
  file.puts rss
end

puts "Generated RSS feed with #{new_events.length} new events."

puts 'Done generating feed. Saving events to files...'

events.each do |event|
  File.open("_data/events/#{event.id}.json", 'w') do |file|
    file.puts event.to_json
  end
end

puts 'Finished saving events to files.'
