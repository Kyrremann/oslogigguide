#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative './models'

require 'date'
require 'icalendar'
require 'json'
require 'ostruct'

def get_event(id)
  file_path = "_data/events/#{id}.json"
  return nil unless File.exist?(file_path)

  JSON.parse(File.read(file_path), object_class: OpenStruct)
end

calendars = JSON.load_file('_data/calendars.json')

calendars.keys.each do |user|
  items = calendars[user]

  cal = Icalendar::Calendar.new
  items.each do |item|
    p item
    event = get_event(item['id'])
    if event.nil?
      puts "Cannot find event #{item['name']} (#{item['id']}), skipping..."
      next
    end

    p event

    cal.event do |e|
      e.dtstart = DateTime.parse(event.start_time)
      e.dtend = DateTime.parse(event.end_time)
      e.append_custom_property('X-WR-CALNAME', 'oslogigguide')
      e.append_custom_property('X-WR-TIMEZONE', 'Europe/Oslo')
      e.append_custom_property('X-PUBLISHED-TTL', 'PT24H')
      e.summary = event.name
      e.description = <<~DESC
        Venue: #{event.venue}
        Tags: #{event.tags.join(', ')}

        #{event.description}

        Tickets: #{event.ticket_url.split('?')[0]}
      DESC
      e.location = event.name
    end
  end

  File.open("assets/calendars/#{user}.ics", 'w') do |file|
    file.puts cal.to_ical
  end
end

puts 'Finished generating ICS file.'
