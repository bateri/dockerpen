local model_state = require("./state")
local S = model_state.S

-- ---- toasts: what happened, said where the person is --------------------------------------------

local toast = {}

-- How long it stays: nine seconds where it is bad news, four and a half where it is not.
local TOAST_SECONDS = 4.5
local TOAST_BAD_SECONDS = 9

-- Tells something for a few seconds. `options.kind` is the role it is in (success, error, warning,
-- info); `options.action = { label =, run = function }` is a verb it offers while it is up (undo).
function toast.say(text, options)
	options = options or {}
	local item = {
		text = text,
		body = options.body,
		kind = options.kind or "info",
		action = options.action,
		show = options.show,
		until_ = S.now + (options.seconds or ((options.kind == "error") and TOAST_BAD_SECONDS or TOAST_SECONDS)),
	}
	S.toasts[#S.toasts + 1] = item
	while #S.toasts > 4 do
		table.remove(S.toasts, 1)
	end
	return item
end

-- Takes away the toasts whose time is up; the time of the next one to go (so that the page is
-- rendered again then), when there is one.
function toast.tidy()
	local keep, next_at = {}, nil
	for _, item in ipairs(S.toasts) do
		if item.until_ > S.now then
			keep[#keep + 1] = item
			next_at = next_at and math.min(next_at, item.until_) or item.until_
		end
	end
	if #keep ~= #S.toasts then
		S.toasts = keep
	end
	return next_at
end

return {
	toast = toast,
}
