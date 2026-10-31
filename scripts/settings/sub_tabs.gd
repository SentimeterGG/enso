extends VBoxContainer

@onready var appearance_button: Button = %AppearanceButton
@onready var controls_button: Button = %ControlsButton
@onready var display_button: Button = %DisplayButton
@onready var audio_button: Button = %AudioButton
@onready var gameplay_button: Button = %GameplayButton

@onready var tab_label: Label = %TabLabel
@onready var label_anim: AnimationPlayer = %LabelAnim

var panels: Array[VBoxContainer] = []

var oldPanel: String = "Appearance"

func _ready() -> void:
	appearance_button.button_pressed = true
	
	panels = [
		%Appearance, %Controls, %Display, %Audio, %Gameplay
	]
	show_panel.bind(panels[0])
	
	appearance_button.pressed.connect(show_panel.bind(panels[0]))
	controls_button.pressed.connect(show_panel.bind(panels[1]))
	display_button.pressed.connect(show_panel.bind(panels[2]))
	audio_button.pressed.connect(show_panel.bind(panels[3]))
	gameplay_button.pressed.connect(show_panel.bind(panels[4]))

func show_panel(panel_to_show: VBoxContainer) -> void:
	panel_to_show.show()
	
	for panel in panels:
		if not panel == panel_to_show:
			panel.hide()
	
	if not panel_to_show.name == oldPanel:
		label_anim.stop()
		label_anim.play("Transition")
	
	oldPanel = panel_to_show.name
	
	match panel_to_show.name:
		"Appearance":
			tab_label.text = "APPEARANCE"
		"Controls":
			tab_label.text = "CONTROLS"
		"Display":
			tab_label.text = "DISPLAY"
		"Audio":
			tab_label.text = "AUDIO"
		"Gameplay":
			tab_label.text = "GAMEPLAY"
			
	
