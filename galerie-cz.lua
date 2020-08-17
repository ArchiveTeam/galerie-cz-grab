dofile("table_show.lua")
dofile("urlcode.lua")
JSON = (loadfile "JSON.lua")()

local item_value = os.getenv('item_value')
local item_type = os.getenv('item_type')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local discovered = {}

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

load_json_file = function(file)
  if file then
    return JSON:decode(file)
  else
    return nil
  end
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl, force)
  if string.match(url, "'+")
    or string.match(url, "[<>\\%*%$;%^%[%],%(%){}\n]")
    or string.match(url, "^https?://gs%.jxs%.cz/jquery/") -- Common UI things
    or url == "http://" .. item_value .. ".galerie.cz/zapomenute-heslo" -- Password reset page
    or url == "http://" .. item_value .. ".galerie.cz/registrace"
    or string.match(url, "^https?://gs%.jxs%.cz/img/") -- Static UI images
    or string.match(url, "^https?://nd%d%d.jxs.cz/%d%d%d/%d%d%d/?$") -- Bare directories
    or not (
      string.match(url, "^https?://[^/]*jxs%.cz/")
      or string.match(url, "^https?://[^/]*galerie%.cz/")
    ) then
    return false
  end

  local tested = {}
  for s in string.gmatch(url, "([^/]+)") do
    if tested[s] == nil then
      tested[s] = 0
    end
    if tested[s] == 6 then
      return false
    end
    tested[s] = tested[s] + 1
  end

  if string.match(url, "^https?://[^/]*jxs%.cz/") then
    if parenturl and string.match(parenturl, "^https?://[^/]*jxs%.cz/") then
      return false
    end
    return true
  end

  local match = string.match(url, "^https?://([^%.]+)%.galerie%.cz/")
  if match and match == item_value then
    return true
  elseif match then
    discovered[match] = true
  end
  
  return false
end

wget.callbacks.lookup_host = function(host)
  if host == item_value:lower() .. ".galerie.cz" then
    return "192.124.249.106"
  end
  
  -- Weird addresses are to get around a wget-lua bug; I'll put in a PR soon.
  -- (Specifically, the point here is to make sure that all the strings this
  -- function ever returns have the same length.)
  if host:lower() == "nd01.jxs.cz" then return "0X2e.234.102.11" end
  if host:lower() == "nd02.jxs.cz" then return "0X2e.234.102.12" end
  if host:lower() == "nd03.jxs.cz" then return "0X2e.234.102.13" end
  if host:lower() == "nd04.jxs.cz" then return "0X2e.234.102.14" end
  if host:lower() == "nd05.jxs.cz" then return "0X2e.234.102.15" end
  if host:lower() == "nd06.jxs.cz" then return "0X2e.234.102.16" end
  
  return nil
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
    local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if (downloaded[url] ~= true and addedtolist[url] ~= true)
    and (allowed(url, parent["url"])) then
    addedtolist[url] = true
    return true
  end
  
  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  
  downloaded[url] = true

  local function check(urla, force)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.gsub(string.match(url, "^(.-)%.?$"), "&amp;", "&")
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
      and allowed(url_, origurl, force) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"), force)
    elseif string.match(newurl, "^https?://") then
      check(newurl, force)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""), force)
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)") .. string.gsub(newurl, "\\", ""), force)
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)") .. newurl, force)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)") .. string.gsub(newurl, "\\", ""), force)
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)") .. newurl, force)
    elseif string.match(newurl, "^%./") then
      checknewurl(string.match(newurl, "^%.(.+)"), force)
    end
  end

  local function checknewshorturl(newurl, force)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)") .. newurl, force)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
      or string.match(newurl, "^[/\\]")
      or string.match(newurl, "^%./")
      or string.match(newurl, "^[jJ]ava[sS]cript:")
      or string.match(newurl, "^[mM]ail[tT]o:")
      or string.match(newurl, "^vine:")
      or string.match(newurl, "^android%-app:")
      or string.match(newurl, "^ios%-app:")
      or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)") .. newurl, force)
    end
  end

  if allowed(url, nil) and status_code == 200
    and not string.match(url, "^https?://[^/]*jxs%.cz/") then
    html = read_file(file)
    if string.match(url, "^https?://[^%.]+%.galerie%.cz/$") then
      check(url .. "robots.txt")
    end
    if string.match(url, "^http://[^/]+%.galerie.cz/[^/]+/%d+$") then
      local id = string.match(url, "(%d+)$")
      check("http://" .. item_value .. ".galerie.cz/.ajax/image/read?info=1&id=" .. id)
    end
    -- Get thumbnails in all sizes
    -- Many will 404, but there's a fairly complex function to reverse-engineer that computes
    -- the right ones, and these 404s are cheap (considering the bottleneck here is the main site)
    local m = string.match(html, "new GJsImages%([^\n]+%);%s*\n")
    if m ~= nil then
      m = string.gsub(m, "^new GJsImages%(", "")
      m = string.gsub(m, "%);%s*\n", "")
      local j = JSON:decode(m)
      for i, v in ipairs(j) do
        check(v["path"] .. "/" .. v["file"] .. "_" .. "u"  .. v["ext"] .. "?" .. v["modified"])
        check(v["path"] .. "/" .. v["file"] .. "_" .. "v1" .. v["ext"] .. "?" .. v["modified"])
        check(v["path"] .. "/" .. v["file"] .. "_" .. "v2" .. v["ext"] .. "?" .. v["modified"])
        check(v["path"] .. "/" .. v["file"] .. "_" .. "p"  .. v["ext"] .. "?" .. v["modified"])
        check(v["path"] .. "/" .. v["file"] .. "_" .. "o2" .. v["ext"] .. "?" .. v["modified"])
      end
    end
    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      checknewurl(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if status_code >= 300 and status_code <= 399 then
    local newloc = string.match(http_stat["newloc"], "^([^#]+)")
    if string.match(newloc, "^//") then
      newloc = string.match(url["url"], "^(https?:)") .. string.match(newloc, "^//(.+)")
    elseif string.match(newloc, "^/") then
      newloc = string.match(url["url"], "^(https?://[^/]+)") .. newloc
    elseif not string.match(newloc, "^https?://") then
      newloc = string.match(url["url"], "^(https?://.+/)") .. newloc
    end
    if downloaded[newloc] == true or addedtolist[newloc] == true or not allowed(newloc, url["url"]) then
      tries = 0
      return wget.actions.EXIT
    end
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end
  
  if status_code >= 500
    or (status_code >= 400 and status_code ~= 404)
    or status_code  == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 10
    if not allowed(url["url"], nil) then
        maxtries = 2
    end
    if tries > maxtries then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"], nil) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.finish = function(start_time, end_time, wall_time, numurls, total_downloaded_bytes, total_download_time)
  local file = io.open(item_dir .. '/' .. warc_file_base .. '_data.txt', 'w')
  for blog, _ in pairs(discovered) do
    file:write("galerie:" .. blog .. "\n")
  end
  file:close()
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
  
end
