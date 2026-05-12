#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative './models'

require 'date'
require 'icalendar'
require 'icalendar/tzinfo'
require 'json'
require 'ostruct'
require 'tzinfo'

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
      dtstart = Icalendar::Values::DateTime.new(DateTime.parse(event.start_time.to_s), 'tzid' => 'Europe/Oslo')
      dtend_parsed = DateTime.parse(event.end_time.to_s)

      # Cap end time at midnight of the start day (00:00 next day)
      start_date = DateTime.parse(event.start_time.to_s).to_date
      end_date = dtend_parsed.to_date
      if end_date > start_date
        dtend_parsed = DateTime.new(start_date.year, start_date.month, start_date.day, 0, 0, 0) + 1
      end
      dtend = Icalendar::Values::DateTime.new(dtend_parsed, 'tzid' => 'Europe/Oslo')
      e.dtstart = dtstart
      e.dtend = dtend
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
      e.location = event.venue
    end
  end

  File.open("assets/calendars/#{user}.ics", 'w') do |file|
    file.puts cal.to_ical
  end
end

puts 'Finished generating ICS file.'
