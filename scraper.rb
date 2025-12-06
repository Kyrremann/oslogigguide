require 'json'
require 'httparty'
require 'date'
require 'icalendar'
require 'rss'
require 'date'

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

class Venue
  attr_reader :id, :name

  def initialize(id, name)
    @id = id
    @name = name
  end

  def self.from_broadcast(payload)
    id = payload['venue']['objectId']
    name = payload['venue']['name']

    Venue.new(id, name)
  end

  def to_json(_options = {})
    @name
  end
end

class Event
  attr_reader :id, :tags, :start_time, :end_time, :venue, :updated_at
  attr_accessor :name, :updated

  def initialize(id, name, tags, start_time, end_time, venue, updated_at)
    @id = id
    @name = name
    @tags = tags
    @start_time = DateTime.parse(start_time)
    @end_time = DateTime.parse(end_time || event_start + Rational(4, 24)) # Default duration 4 hours
    @venue = venue
    @updated_at = updated_at
    @updated = false
  end

  def self.from_broadcast(payload)
    id = payload['objectId']
    name = payload['name']
    tags = payload['tags']
    start_time = payload['start_time']
    end_time = payload['custom_fields']['end_time']
    venue = Venue.from_broadcast(payload)
    updated_at = payload['updatedAt']

    Event.new(id, name, tags, start_time, end_time, venue, updated_at)
  end

  def self.from_events_edge(payload)
    id = payload['id']
    name = payload['name']
    tags = payload['tags']
    start_time = payload['start_time']
    end_time = payload['custom_fields']['end_time']
    venue = Venue.new(-1, payload['place']['name'])
    updated_at = payload['updatedAt']

    Event.new(id, name, tags, start_time, end_time, venue, updated_at)
  end

  def has_changed(old_event)
    return false if DateTime.parse(old_event['updated_at']) == DateTime.parse(@updated_at)

    @name != old_event['name'] ||
      @tags.sort != old_event['tags'].sort ||
      @start_time != DateTime.parse(old_event['start_time']) ||
      @end_time != DateTime.parse(old_event['end_time']) ||
      @venue.name != old_event['venue']['name']
  end

  def to_json(_options = {})
    {
      id: @id,
      name: @name,
      tags: @tags,
      start_time: @start_time,
      end_time: @end_time,
      venue: @venue.to_json,
      updated_at: @updated_at
    }.to_json
  end
end

old_events = JSON.parse(File.read('_data/events.json'))['events']

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

File.open('_data/events.json', 'w') do |file|
  file.puts({ updated_at: DateTime.now, events: events }.to_json)
end

puts "Scraped #{events.length} events."

# Generate ICS files
Dir.glob('assets/calendars/*.ics').each do |file|
  File.delete(file)
end

events.each do |event|
  if event.id.nil? || event.start_time.nil?
    puts "Skipping event with missing ID or start time: #{event.name}"
    next
  end

  cal = Icalendar::Calendar.new
  cal.event do |e|
    e.dtstart = Icalendar::Values::DateTime.new(event.start_time)
    e.dtend = Icalendar::Values::DateTime.new(event.end_time)
    e.append_custom_property('X-WR-CALNAME', event.name)
    e.append_custom_property('X-WR-TIMEZONE', 'Europe/Oslo')
    e.append_custom_property('X-PUBLISHED-TTL', 'PT24H')
    e.summary = event.name
    e.description = "Tags: #{event.tags.join(', ')}"
    e.location = event.venue.name
  end

  File.open("assets/calendars/#{event.id}.ics", 'w') do |file|
    file.puts cal.to_ical
  end
end

puts 'Finished generating ICS files.'

# Compare with old events to find new or updated ones
new_events = events.reject do |event|
  old_events.any? { |old_event| old_event['id'] == event.id }
end

p "Found #{new_events.length} new events."

updated_events = events.select do |event|
  old_event = old_events.find { |oe| oe['id'] == event.id }
  next false if old_event.nil?

  event.has_changed(old_event)
end

p "Found #{updated_events.length} updated events."

updated_events.map! do |event|
  event.updated = true
  event
end

new_events.concat(updated_events).sort_by!(&:start_time)

if new_events.empty?
  p 'No new events, using the last 10 events for the feed.'
  new_events = events.last(10)
end

rss = RSS::Maker.make('atom') do |maker|
  maker.channel.author = 'Kyrremann'
  maker.channel.title = 'Oslo Gig Guide'
  maker.channel.link = 'https://kyrremann.no/oslogigguide/'
  maker.channel.about = 'New events scraped from various sources.'
  maker.channel.updated = Time.now.to_s

  new_events.each do |event|
    maker.items.new_item do |item|
      name = event.updated ? "#{event.name} (updated)" : event.name
      item.title = name + event.start_time.strftime(' (%Y-%m-%d)')
      item.link = "https://kyrremann.no/oslogigguide/##{event.id}"
      item.description =
        "#{event.name} at #{event.venue.name} on the #{event.start_time.strftime('%Y-%m-%d %H:%M')}" \
        "\n\nTags: #{event.tags.join(', ')}" \
        "\nICS: https://kyrremann.no/oslogigguide/assets/calendars/#{event.id}.ics"
      item.updated = Time.now.to_s # DateTime.parse(event.start_time).to_time.to_s
    end
  end
end

File.open('feed.xml', 'w') do |file|
  file.puts rss
end

puts "Generated RSS feed with #{new_events.length} new events."
