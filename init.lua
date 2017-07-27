
local client = client

local awful         = require('awful')
local naughty       = require("naughty")

local function my_debug(s)
    naughty.notify({ preset = naughty.config.presets.critical,
    title = "DEBUG!",
    text = s })
end

--
-- in termgrp,
-- there are group and window
-- group contains windows
--
-- %G : group_name
-- %W : window_name
-- %D : current working directory
--

local tmux = {
    pattern_title = "%[%G:%W%] %D",
    socket_name = "awesome-termgrp",
    config = " \z
    set-option status off \\; \z
    set-option set-titles on \\; \z
    set-option set-titles-string \"[#{session_group}:#{session_name}] #T\" \\; \z
    set-window-option -g aggressive-resize on \\; \z
    "
}

tmux.cmd = {
    spawn = function(group_name, cwd, app) 
        return string.format("tmux -L %s new-session -t %s \\; %s new-window -c '%s' %s", tmux.socket_name, group_name, tmux.config, cwd, app)
    end,
    create = function(dmenu, dmenu_args)
        return string.format("tmux -L %s new-session -t $(tmux -L %s list-sessions -F#{session_group} | sort | uniq | %s %s) \\; %s", tmux.socket_name, tmux.socket_name, dmenu, dmenu_args, tmux.config)
    end,
    list_group = function(dmenu, dmenu_args)
        return string.format("tmux -L %s list-sessions -F#{session_group} | sort | uniq | %s %s", tmux.socket_name, dmenu, dmenu_args)
    end,
    list_window_of_group = function(dmenu, dmenu_args)
        return string.format("tmux -L %s list-sessions -F#{session_name},#{session_group} | grep $(tmux -L %s list-sessions -F#{session_group} | sort | uniq | %s %s) | cut -d, -f1", tmux.socket_name, tmux.socket_name, dmenu, dmenu_args)
    end,
    attach_window = function(window_name)
        return string.format("tmux -L %s attach-session -t %s \\; %s", tmux.socket_name, window_name, tmux.config)
    end,
    kill_window = function(window_name)
        return string.format("tmux -L %s kill-window -t $(tmux -L %s list-window -t %s -F#{window_id},#{window_active} | grep \",1$\" | cut -d, -f1) \\; kill-session -t %s", tmux.socket_name, tmux.socket_name, window_name, window_name)
    end,

    get_pattern_group = function() return tmux.pattern_title:gsub("%%G", "(%%g+)"):gsub("%%[WD]", ".*") end,
    get_pattern_window = function() return tmux.pattern_title:gsub("%%W", "(%%g+)"):gsub("%%[GD]", ".*") end,
    get_pattern_cwd = function () return tmux.pattern_title:gsub("%%D", "(%%g+)"):gsub("%%[GW]", ".*") end,
}


local termgrp = {}
termgrp = {
    terminal = "st",
    dmenu = "rofi -dmenu",
    group_manager_built_in = {
        tmux = tmux,
    },
    action = {},
}

termgrp.group_manager = termgrp.group_manager_built_in.tmux

function termgrp.action.spawn(tapp, targ)
    tapp = tapp or ""
    targ = targ or ""

    local group_name = nil
    if client.focus then
        local pattern = termgrp.group_manager.cmd.get_pattern_group()
        group_name = client.focus.name:match(pattern)
    end

    if group_name == nil then
        awful.spawn(termgrp.terminal .. " " .. targ .. " -e " .. tapp)
    else
        local pattern = termgrp.group_manager.cmd.get_pattern_cwd()
        local cwd = client.focus.name:match(pattern)
        local cmd = termgrp.group_manager.cmd.spawn(group_name, cwd, tapp)
        awful.spawn(termgrp.terminal .. " " .. targ .. " -e " .. cmd)
    end
end

function termgrp.action.create(dmenu_args)
    dmenu_args = dmenu_args or ""

    local cmd = termgrp.group_manager.cmd.create(termgrp.dmenu, dmenu_args)
    awful.spawn.with_shell(termgrp.terminal .. " " .. cmd)
end

function termgrp.action.detach(dmenu_args)
    dmenu_args = dmenu_args or ""

    local cmd = "sh -c '" .. termgrp.group_manager.cmd.list_group(termgrp.dmenu, dmenu_args) .. "'"
    awful.spawn.easy_async(cmd, function(stdout, stderr, reason, exit_code)
        local group_name = stdout:gsub("\n","")
        local pattern = termgrp.group_manager.pattern_title:gsub("%%G", group_name):gsub("%%[WD]", ".*")
        for _, c in ipairs(client.get()) do
            if c.name:match(pattern) then
                c:kill()
            end
        end
    end)
end

function termgrp.action.attach(dmenu_args)
    dmenu_args = dmenu_args or ""

    local cmd = "sh -c '" .. termgrp.group_manager.cmd.list_window_of_group(termgrp.dmenu, dmenu_args) .. "'"
    awful.spawn.easy_async(cmd, function(stdout, stderr, reason, exit_code)
        for tn in stdout:gmatch("%S+") do
            local attach_cmd = termgrp.group_manager.cmd.attach_window(tn)
            awful.spawn(termgrp.terminal .. " -e " .. attach_cmd)
        end
    end)
end

function termgrp.action.kill(c)
    local pattern = termgrp.group_manager.cmd.get_pattern_window()
    local window_name = c.name:match(pattern)
    if window_name ~= nil then
        local cmd = termgrp.group_manager.cmd.kill_window(window_name)
        awful.spawn.with_shell(cmd)
    else
        c:kill()
    end
end

return termgrp
