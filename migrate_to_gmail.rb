#!/usr/bin/env ruby

require 'net/imap'


# Source server connection info.
SOURCE_HOST = 'imap.srv.cs.cmu.edu'
SOURCE_PORT = 143
SOURCE_SSL  = false
SOURCE_USER = 'aphanish'
SOURCE_PASS = ''

# Destination server connection info.
DEST_HOST = 'imap.gmail.com'
DEST_PORT = 993
DEST_SSL  = true
DEST_USER = 'foobar@gmail.com'
DEST_PASS = ''


UID_BLOCK_SIZE = 1024 # max number of messages to select at once

# Mapping of source folders to destination folders. The key is the name of the
# folder on the source server, the value is the name on the destination server.
# Any folder not specified here will be ignored. If a destination folder does
# not exist, it will be created.
#FOLDERS = {
#  'INBOX' => 'INBOX',
#  'sourcefolder' => 'gmailfolder'
#}

# Utility methods.
def dd(message)
   puts "[#{DEST_HOST}] #{message}"
end

def ds(message)
   puts "[#{SOURCE_HOST}] #{message}"
end

def uid_fetch_block(server, uids, *args)
  pos = 0
  while pos < uids.size
	server.uid_fetch(uids[pos, UID_BLOCK_SIZE], *args).each { |data| yield data }
	pos += UID_BLOCK_SIZE
  end
end


# Connect and log into both servers.
ds 'connecting...'
source = Net::IMAP.new(SOURCE_HOST, SOURCE_PORT, SOURCE_SSL)


ds 'logging in...'
source.login(SOURCE_USER, SOURCE_PASS)


dd 'connecting...'
dest = Net::IMAP.new(DEST_HOST, DEST_PORT, DEST_SSL)


dd 'logging in...'
dest.login(DEST_USER, DEST_PASS)


EXCLUDE_FOLDERS = {
  'INBOX.Drafts' => true,
  'INBOX.SPAM' => true,
  'INBOX.Sent' => true,
  'INBOX.Trash' => true
}


FOLDERS = Hash.new
OLDLIST = source.list("INBOX", "*")
OLDLIST.each{ |i|
 #puts i.name
  next if EXCLUDE_FOLDERS[i.name]
 $NEWGMAIL_FOLDER = i.name
 $NEWGMAIL_FOLDER = $NEWGMAIL_FOLDER.gsub(/^INBOX./,'')
 $NEWGMAIL_FOLDER = $NEWGMAIL_FOLDER.gsub(/[ ]/,'_')
 $NEWGMAIL_FOLDER = $NEWGMAIL_FOLDER.gsub(/[-]/,'_')
 $NEWGMAIL_FOLDER = $NEWGMAIL_FOLDER.gsub(/[.]/,'/')
 FOLDERS[i.name] = $NEWGMAIL_FOLDER
 puts FOLDERS[i.name]
}

=begin

puts "====="

FOLDERS.each do |source_folder, dest_folder|
  # Open (or create) destination folder in read-write mode.
  begin
	dd "selecting folder '#{dest_folder}'..."
	dest.select(dest_folder)
  rescue => e
	begin
	  dd "folder not found; creating..."
	  dest.create(dest_folder)
	  dest.select(dest_folder)
	  puts "success"
	rescue => ee
	  dd "error: could not create folder: #{e}"
	  puts ""
	  next
	end
  end
  dest.close
end
exit
=end

=begin
FOLDERS.each do |source_folder, dest_folder|
 puts source_folder
 begin
   source.subscribe(source_folder)
 rescue Net::IMAP::NoResponseError => e
   puts "Error. Got exception: #{e.message}."
 end
end
exit
=end

puts "====="

# Loop through folders and copy messages.
FOLDERS.each do |source_folder, dest_folder|
  # Open source folder in read-only mode.
  begin
	ds "selecting folder '#{source_folder}'..."
	source.examine(source_folder)
  rescue => e
	ds "error: select failed: #{e}"
	next
  end
  
  # Open (or create) destination folder in read-write mode.
  begin
	dd "selecting folder '#{dest_folder}'..."
	dest.select(dest_folder)
  rescue => e
	begin
	  dd "folder not found; creating..."
	  dest.create(dest_folder)
	  dest.select(dest_folder)
	  puts "success"
	rescue => ee
	  dd "error: could not create folder: #{e}"
	  puts ""
	  next
	end
  end

  # Build a lookup hash of all message ids present in the destination folder.
  dest_info = {}
  
  dd 'analyzing existing messages...'
  uids = dest.uid_search(['ALL'])
  dd "found #{uids.length} messages"
  if uids.length > 0
	uid_fetch_block(dest, uids, ['ENVELOPE']) do |data|
	  dest_info[data.attr['ENVELOPE'].message_id] = true
	end
  end
  
  # Loop through all messages in the source folder.
  uids = source.uid_search(['ALL'])
  ds "found #{uids.length} messages"
  if uids.length > 0
	uid_fetch_block(source, uids, ['ENVELOPE']) do |data|
	  mid = data.attr['ENVELOPE'].message_id

	  # If this message is already in the destination folder, skip it.
	  next if dest_info[mid]
	
	  # Download the full message body from the source folder.
	  ds "downloading message #{mid}..."
	  msg = source.uid_fetch(data.attr['UID'], ['RFC822', 'FLAGS',
	      'INTERNALDATE']).first
	
	  # Append the message to the destination folder, preserving flags and
	  # internal timestamp.
	  dd "storing message #{mid}..."
 success = false
 #dest.append(dest_folder, msg.attr['RFC822'], msg.attr['FLAGS'], msg.attr['INTERNALDATE'])
 begin
   dest.append(dest_folder, msg.attr['RFC822'], msg.attr['FLAGS'], msg.attr['INTERNALDATE'])
   success = true
 rescue Net::IMAP::NoResponseError => e
   puts "Got exception: #{e.message}. Retrying..."
   sleep 1
 end until success
	end
  end
  
  source.close
  dest.close
end

puts 'done'