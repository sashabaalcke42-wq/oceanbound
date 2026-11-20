extends Screen
## A shop counter: buy anything on the shop's list. Boat blocks go into the
## inventory, ready for the workshop.

var shop: ShopDef


func _init(p_shop: ShopDef) -> void:
	shop = p_shop
	title = shop.display_name
	subtitle = shop.greeting


func _fill() -> void:
	for id in shop.stock:
		var price := shop.price_of(id)
		var detail := _description(id)
		detail += ("\n" if detail != "" else "") + "You have %d." % Inventory.count(id)
		var buttons: Array = [["Buy  $%d" % price, buy.bind(id, 1), Economy.can_afford(price)]]
		if price * 10 <= 200:
			buttons.append(["Buy 10  $%d" % (price * 10), buy.bind(id, 10), Economy.can_afford(price * 10)])
		add_row(ItemLibrary.name_of(id), detail, buttons)


## Returns true if the purchase went through.
func buy(id: StringName, count: int) -> bool:
	var cost := shop.price_of(id) * count
	if not Economy.spend(cost, "Bought %d %s" % [count, ItemLibrary.name_of(id)]):
		EventBus.notify.emit("You can't afford that.")
		return false
	Inventory.add(id, count)
	return true


func _description(id: StringName) -> String:
	var item := ItemLibrary.get_item(id)
	if item:
		return item.description
	var block := BlockLibrary.get_block(id)
	return block.description if block else ""
