--[[----------------------------------------------------------------------------

PanaLuxRewind.lua

Added by PanaLux. Not part of MIDI2LR.

Rewind records the whole editing session, so it needs two things the MIDI2LR protocol
does not carry:

  1. Which photo is on screen, so a trail can be kept per photo.
     Sent as  PanaLuxSelection <count> <photoID> <module>  whenever it changes.

  2. Whole develop settings tables, so a point in the past can be restored exactly —
     masks, crop and all — instead of only the sliders PanaLux happens to know about.
     Asked for with   PanaLuxSnapshot <token>
     answered with    PanaLuxKeyframe <token> <seq> <total> <base64>
     handed back with PanaLuxRestoreBegin / PanaLuxRestoreChunk <base64> / PanaLuxRestoreEnd

The table is opaque to PanaLux: it is serialised here, stored as a string, and given back
here untouched. Whatever `getDevelopSettings()` puts in it survives the round trip, which is
why `PanaLuxProbe` exists — run it once on a photo with a mask and read the dump before
trusting masks to it.

This file is part of PanaLux Bridge. PanaLux Bridge is free software: you can
redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

------------------------------------------------------------------------------]]

local LrApplication     = import 'LrApplication'
local LrApplicationView = import 'LrApplicationView'
local LrDialogs         = import 'LrDialogs'
local LrFileUtils       = import 'LrFileUtils'
local LrPathUtils       = import 'LrPathUtils'
local LrStringUtils     = import 'LrStringUtils'
local LrTasks           = import 'LrTasks'
local serpent           = require 'serpent'

local CHUNK = 800

local lastSelection = nil
local restoreBuffer = {}
local restoring = false

local function send(message)
  if MIDI2LR and MIDI2LR.SERVER and MIDI2LR.SERVER.send then
    MIDI2LR.SERVER:send(message)
  end
end

--[[ Which photo, in a form that stays the same between sessions. The catalog name is in
     there because local identifiers only mean anything inside their own catalog. ]]
local function photoIdentifier(photo)
  if photo == nil then return '-' end
  local ok, id = pcall(function() return photo.localIdentifier end)
  if not ok or id == nil then return '-' end
  local catalog = ''
  local okCat, path = pcall(function() return LrApplication.activeCatalog():getPath() end)
  if okCat and path ~= nil then
    catalog = LrPathUtils.removeExtension(LrPathUtils.leafName(path)) or ''
  end
  local name = (catalog .. ':' .. tostring(id)):gsub('%s', '_')
  return name
end

--[[ Called from Client.lua's idle loops, a few times a second. Only speaks when something
     changed, so it costs nothing while the user is working on one photo. ]]
local function PushSelection(force)
  local ok, message = pcall(function()
      local catalog = LrApplication.activeCatalog()
      local targets = catalog:getTargetPhotos()
      local count = targets and #targets or 0
      local id = photoIdentifier(catalog:getTargetPhoto())
      local moduleName = LrApplicationView.getCurrentModuleName() or '-'
      return string.format('PanaLuxSelection %d %s %s\n', count, id, moduleName)
    end)
  if not ok or message == nil then return end
  if not force and message == lastSelection then return end
  lastSelection = message
  send(message)
  if LrApplicationView.getCurrentModuleName() ~= 'develop' then return end
  local photo = LrApplication.activeCatalog():getTargetPhoto()
  if photo == nil then return end
  local id = photoIdentifier(photo)
  local limits = require 'Limits'
  local database = require 'Database'
  for param in pairs(database.Parameters) do
    -- Report the same bounds used by the numeric protocol, including user limits.
    local ok, low, high = LrTasks.pcall(limits.GetMinMax, param, nil, true)
    if ok and type(low) == 'number' and type(high) == 'number' and high > low then
      send(string.format('PanaLuxRange %s %s %.17g %.17g\n', id, param, low, high))
    end
  end
end

-- A preview is one coherent frame, not hundreds of individual slider callbacks. Keep
-- only the latest pending frame and yield so Lightroom can render between frames.
local pendingPreview = nil
local previewRunning = false
local function Preview(payload)
  local token, photoID, encoded = payload:match('^(%S+) (%S+) (.+)$')
  if not token then return end
  local values = {}
  for name, value in encoded:gmatch('([%w_]+)=([%d%.eE%+%-]+)') do
    local number = tonumber(value)
    if number and number >= 0 and number <= 1 then values[name] = number end
  end
  pendingPreview = {token=token, photoID=photoID, values=values}
  if previewRunning then return end
  previewRunning = true
  LrTasks.startAsyncTask(function()
    while pendingPreview do
      local frame = pendingPreview
      pendingPreview = nil
      local applied = 0
      local ok = LrTasks.pcall(function()
        local photo = LrApplication.activeCatalog():getTargetPhoto()
        if photoIdentifier(photo) ~= frame.photoID or LrApplicationView.getCurrentModuleName() ~= 'develop' then return end
        local develop = import 'LrDevelopController'
        local limits = require 'Limits'
        local database = require 'Database'
        for name, value in pairs(frame.values) do
          if database.Parameters[name] then
            local current = develop.getValue(name)
            local target = limits.MIDIValueToLRValue(name, value)
            if type(current) == 'number' and type(target) == 'number' then
              MIDI2LR.PARAM_OBSERVER[name] = target
              if current ~= target then develop.setValue(name, target, false) end
              applied = applied + 1
            end
          end
        end
      end)
      -- In an async SDK task, this hands the Develop renderer a turn even during a hard spin.
      LrTasks.sleep(0.03)
      send(string.format('PanaLuxPreviewApplied %s %d %s\n', frame.token, applied, ok and 'ok' or 'error'))
    end
    previewRunning = false
  end)
end

--[[ The whole table, serialised and sent in pieces. A settings table with masks in it is far
     longer than one socket line should carry. ]]
local function SendSnapshot(token)
  token = tostring(token or ''):gsub('%s', '')
  if token == '' then return end
  LrTasks.startAsyncTask(function()
      local ok, payload = pcall(function()
          local photo = LrApplication.activeCatalog():getTargetPhoto()
          if photo == nil then return nil end
          local settings = photo:getDevelopSettings()
          if settings == nil then return nil end
          return LrStringUtils.encodeBase64(serpent.dump(settings))
        end)
      if not ok or payload == nil or payload == '' then
        send(string.format('PanaLuxKeyframe %s 0 0 -\n', token))
        return
      end
      local total = math.ceil(#payload / CHUNK)
      for i = 1, total do
        local piece = payload:sub((i - 1) * CHUNK + 1, i * CHUNK)
        send(string.format('PanaLuxKeyframe %s %d %d %s\n', token, i, total, piece))
      end
    end)
end

local function RestoreBegin()
  restoreBuffer = {}
  restoring = true
end

local function RestoreChunk(value)
  if not restoring then RestoreBegin() end
  restoreBuffer[#restoreBuffer + 1] = tostring(value or ''):gsub('%s', '')
end

--[[ Put a whole table back. This is the step that returns masks and crop, which no amount of
     slider values can do. ]]
local function RestoreEnd()
  local payload = table.concat(restoreBuffer)
  restoreBuffer = {}
  restoring = false
  if payload == '' then return end
  LrTasks.startAsyncTask(function()
      local ok, settings = pcall(function()
          local text = LrStringUtils.decodeBase64(payload)
          local loaded, value = serpent.load(text)
          if not loaded then return nil end
          return value
        end)
      if not ok or type(settings) ~= 'table' then return end
      local catalog = LrApplication.activeCatalog()
      if catalog:getTargetPhoto() == nil then return end
      catalog:withWriteAccessDo(
        'PanaLux: Rewind',
        function()
          local photo = LrApplication.activeCatalog():getTargetPhoto()
          if photo ~= nil then
            photo:applyDevelopSettings(settings, 'PanaLux Rewind')
          end
        end,
        { timeout = 6,
          callback = function()
            LrDialogs.showBezel('PanaLux: the catalog was busy, nothing was changed')
          end,
          asynchronous = true
        }
      )
    end)
end

--[[ Run this once, by hand, on a photo that has a mask, and read the file it writes. It is
     the honest answer to "does the settings table round-trip masks?" for the Lightroom
     version in front of you, which no amount of documentation can be. ]]
local function Probe()
  LrTasks.startAsyncTask(function()
      local photo = LrApplication.activeCatalog():getTargetPhoto()
      if photo == nil then
        LrDialogs.message('PanaLux probe', 'Select a photo first.')
        return
      end
      local settings = photo:getDevelopSettings() or {}
      local keys = {}
      for k, v in pairs(settings) do
        keys[#keys + 1] = string.format('%s\t%s', tostring(k), type(v))
      end
      table.sort(keys)
      local dump = serpent.block(settings, { comment = false, nocode = true })
      local path = LrPathUtils.child(LrPathUtils.getStandardFilePath('temp'), 'panalux-develop-settings.txt')
      local file = io.open(path, 'w')
      if file == nil then
        LrDialogs.message('PanaLux probe', 'Could not write ' .. path)
        return
      end
      file:write('getDevelopSettings() keys\n=========================\n')
      file:write(table.concat(keys, '\n'))
      file:write('\n\nWhole table\n===========\n')
      file:write(dump)
      file:close()
      LrDialogs.message('PanaLux probe',
        'Wrote ' .. path .. '\n\n' .. #keys .. ' keys. Look for MaskGroupBasedCorrections or Masks '
        .. 'to see whether masks are in the table on this version of Lightroom.')
    end)
end

return {
  Preview = Preview,
  PushSelection = PushSelection,
  SendSnapshot  = SendSnapshot,
  RestoreBegin  = RestoreBegin,
  RestoreChunk  = RestoreChunk,
  RestoreEnd    = RestoreEnd,
  Probe         = Probe,
}
