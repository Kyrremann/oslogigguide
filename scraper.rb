require 'json'
require 'httparty'
require 'date'
require 'icalendar'

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
  attr_reader :start_time, :name, :id, :tags, :venue

  def initialize(id, name, tags, start_time, venue)
    @id = id
    @name = name
    @tags = tags
    @start_time = start_time
    @venue = venue
  end

  def self.from_broadcast(payload)
    id = payload['objectId']
    name = payload['name']
    tags = payload['tags']
    start_time = payload['start_time']
    venue = Venue.from_broadcast(payload)

    Event.new(id, name, tags, start_time, venue)
  end

  def self.from_events_edge(payload)
    id = payload['id']
    name = payload['name']
    tags = payload['tags']
    start_time = payload['start_time']
    venue = Venue.new(-1, payload['place']['name'])

    Event.new(id, name, tags, start_time, venue)
  end

  def to_json(_options = {})
    {
      id: @id,
      name: @name,
      tags: @tags,
      start_time: @start_time,
      venue: @venue.to_json
    }.to_json
  end
end

events = []

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

Dir.glob('assets/calendars/*.ics').each do |file|
  File.delete(file)
end

events.each do |event|
  if event.id.nil? || event.start_time.nil?
    puts "Skipping event with missing ID or start time: #{event.name}"
    next
  end

  event_start = DateTime.parse(event.start_time)
  cal = Icalendar::Calendar.new
  cal.event do |e|
    e.dtstart = Icalendar::Values::DateTime.new(event_start)
    e.dtend = Icalendar::Values::DateTime.new(event_start + Rational(4, 24)) # Default duration 4 hours
    e.summary = event.name
    e.description = "Tags: #{event.tags.join(', ')}"
    e.location = event.venue.name
  end

  File.open("assets/calendars/#{event.id}.ics", 'w') do |file|
    file.puts cal.to_ical
  end
end

puts "Finished generating ICS files."
