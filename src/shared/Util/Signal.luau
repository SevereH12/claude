--!strict
-- Minimal signal for module-to-module events (no BindableEvent needed).

export type Connection = { Disconnect: (self: Connection) -> () }

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local listeners: { (T...) -> () } = {}

	local self = {}

	function self.Connect(_: any, fn: (T...) -> ()): Connection
		table.insert(listeners, fn)
		local connection = {}
		function connection.Disconnect(_: any)
			local index = table.find(listeners, fn)
			if index then
				table.remove(listeners, index)
			end
		end
		return connection :: any
	end

	function self.Fire(_: any, ...: T...)
		-- copy so listeners can disconnect while firing
		for _, fn in table.clone(listeners) do
			task.spawn(fn, ...)
		end
	end

	return self :: any
end

return Signal
