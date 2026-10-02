extends MenuClickable

signal open_requested

func _ready() -> void:
	super._ready()
	area_2d.set_block_signals(false)
	selection_timer.set_block_signals(false)
	double_click_timer.set_block_signals(false)
	if not GameEvents.folder_clicked.is_connected(on_folder_clicked):
		GameEvents.folder_clicked.connect(on_folder_clicked)

func double_click_action() -> void :
	GameEvents.folder_double_clicked.emit()
	open_requested.emit()
