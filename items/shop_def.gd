class_name ShopDef
extends Resource
## A shop's name and what it sells. Prices come from the items themselves,
## times this shop's markup. One .tres per shop in res://data/shops/.

@export var id: StringName
@export var display_name := ""
@export var greeting := ""
## Item or block ids, in the order they are listed.
@export var stock: Array[StringName] = []
@export var markup := 1.0


func price_of(item_id: StringName) -> int:
	return maxi(1, roundi(ItemLibrary.base_price(item_id) * markup))
