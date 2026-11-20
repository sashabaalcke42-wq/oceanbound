extends Screen
## The fish market: sell your catch at today's prices. Prices drift over the
## day, and drop as you sell, so spreading sales out pays better.


func _init() -> void:
	title = "Fish Market"
	subtitle = "Prices change through the day, and fall if you sell a lot of one fish."


func _fill() -> void:
	var any := false
	for def in ItemLibrary.items_in(ItemDef.Category.FISH):
		var have := Inventory.count(def.id)
		var price := Economy.fish_price(def.id)
		var trend: String = ["  (low today)", "", "  (high today)"][Economy.fish_trend(def.id) + 1]
		var detail := "$%d each%s. You have %d." % [price, trend, have]
		add_row(def.display_name, detail, [
			["Sell 1", Economy.sell_fish.bind(def.id, 1), have > 0],
			["Sell all", Economy.sell_fish.bind(def.id, have), have > 0],
		])
		any = any or have > 0
	set_subtitle(subtitle if any else "You have no fish to sell. Press F to fish from a dock or a stopped boat.")
