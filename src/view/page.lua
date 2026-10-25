local b = pencere
return {
	render = function()
		return b.div():size_full():p(20):child(b.text("dockerpen"))
	end,
}
