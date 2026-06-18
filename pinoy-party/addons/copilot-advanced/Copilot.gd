@tool
extends Control

@onready var llms = $LLMs
@onready var lmStudioCompletions = $LLMs/LmStudioCompletion
@onready var geminiCompletions = $LLMs/Gemini
@onready var ollamaCompletions = $LLMs/OllamaCompletion
@onready var model_select = $VBoxParent/SettingsCollapsable/SelectModel/Model
@onready var shortcut_modifier_select = $VBoxParent/SettingsCollapsable/ShortcutSetting/HBoxContainer/Modifier
@onready var shortcut_key_select = $VBoxParent/SettingsCollapsable/ShortcutSetting/HBoxContainer/Key
@onready var info: RichTextLabel = $VBoxParent/VBoxContainer/Info
@onready var urlTextInput: LineEdit = get_node("%URL")
@onready var providerInput: OptionButton = get_node("%provider")
@onready var reloadButton: TextureButton = $VBoxParent/SettingsCollapsable/SelectModel/TextureButton
@onready var loadingIndicator: ColorRect = get_node("%Indicator")
@onready var urlContainer: HBoxContainer = get_node("%UrlContainer")
@onready var apiKeyContainer: HBoxContainer = get_node("%ApiKeyContainer")
@onready var apiKeyInput: LineEdit = get_node("%API_KEY")


# Section part
@onready var settingsSection: Control = $VBoxParent/SettingsCollapsable
@onready var chatSection: ScrollContainer = get_node("%ChatSection") 


#Chat element
@onready var sendButton: Button = get_node("%SendChatMessage")
@onready var inputChat: TextEdit = get_node("%InputChat")
@onready var chatContainer: VBoxContainer = get_node("%ChatContainer")

@export var icon_shader : ShaderMaterial
@export var highlight_color : Color

var editor_interface : EditorInterface
var screen = "Script"

var request_code_state = null
var cur_highlight = null
var indicator = null

var models = {}
var openai_api_key
var cur_model
var apiKey
var provider
var cur_shortcut_modifier = "Control" if is_mac() else "Alt"
var cur_shortcut_key = "C"
var allow_multiline = true
var URL


const PREFERENCES_STORAGE_NAME = "user://copilot-advanced.cfg"
const PREFERENCES_PASS = "F4fv2Jxpasp20VS5VSp2Yp2v9aNVJ21aRK"

func _ready():
	#populate_models()
	populate_modifiers()
	load_config()
	pass
	#Initialize dock, load settings

func populate_models():
	#Add all found models to settings
	model_select.clear()
	for llm in llms.get_children():
		var new_models = llm._get_models()
		for model in new_models:
			model_select.add_item(model)
			models[model] = get_path_to(llm)
	model_select.select(0)
	set_model(model_select.get_item_text(0))

func populate_modifiers():
	#Add available shortcut modifiers based on platform
	shortcut_modifier_select.clear()
	var modifiers = ["Alt", "Ctrl", "Shift"]
	if is_mac(): modifiers = ["Cmd", "Option", "Control", "Shift"]
	for modifier in modifiers:
		shortcut_modifier_select.add_item(modifier)
	apply_by_value(shortcut_modifier_select, cur_shortcut_modifier)

func _unhandled_key_input(event):
	#Handle input
	if event is InputEventKey:
		if cur_highlight:
			#If completion is shown, TAB will accept it
			#and the TAB input ignored
			if event.keycode == KEY_TAB:
				undo_input()
				clear_highlights()
			#BACKSPACE will remove it
			elif event.keycode == KEY_BACKSPACE:
				revert_change()
				clear_highlights()
			#Any other key press will plainly accept it
			else:
				clear_highlights()
		#If shortcut modifier and key are pressed, request completion
		if shortcut_key_pressed(event) and shortcut_modifier_pressed(event):
			request_completion()

func is_mac():
	#Platform check
	return OS.get_name() == "macOS"

func shortcut_key_pressed(event):
	#Check if selected shortcut key is pressed
	var key_string = OS.get_keycode_string(event.keycode)
	return key_string == cur_shortcut_key

func shortcut_modifier_pressed(event):
	#Check if selected shortcut modifier is pressed
	match cur_shortcut_modifier:
		"Control":
			return event.ctrl_pressed
		"Ctrl":
			return event.ctrl_pressed
		"Alt":
			return event.alt_pressed
		"Option":
			return event.alt_pressed
		"Shift":
			return event.shift_pressed
		"Cmd":
			return event.meta_pressed
		_:
			return false

func clear_highlights():
	#Clear all currently highlighted lines
	#and reset request status
	request_code_state = null
	cur_highlight = null
	var editor = get_code_editor()
	for line in range(editor.get_line_count()):
		editor.set_line_background_color(line, Color(0, 0, 0, 0))

func undo_input():
	#Undo last input in code editor
	var editor = get_code_editor()
	editor.undo()

func update_loading_indicator(create = false):
	#Make sure loading indicator is placed at caret position
	if screen != "Script": return
	var editor = get_code_editor()
	if !editor: return
	var line_height = editor.get_line_height()
	if !is_instance_valid(indicator):
		if !create: return
		indicator = ColorRect.new()
		indicator.material = icon_shader
		indicator.custom_minimum_size = Vector2(line_height, line_height)
		editor.add_child(indicator)
	var pos = editor.get_caret_draw_pos()
	var pre_post = get_pre_post()
	#Caret position returned from Godot is not reliable
	#Needs to be adjusted for empty lines
	var is_on_empty_line = pre_post[0].right(1) == "\n"
	var offset = line_height/2-1 if is_on_empty_line else line_height-1
	indicator.position = Vector2(pos.x, pos.y - offset)
	editor.editable = false

func remove_loading_indicator():
	#Free loading indicator, and return editor to editable state
	if is_instance_valid(indicator): indicator.queue_free()
	var editor = get_code_editor()
	editor.editable = true

# Write 3 lines here

func insert_completion(content: String, pre, post):
	#Overwrite code editor text to insert received completion
	info.text = content
	var editor = get_code_editor()
	var scroll = editor.scroll_vertical
	
	var caret_text = pre + content
	var lines_from = pre.split("\n")
	var lines_to = caret_text.split("\n")
	
	cur_highlight = [lines_from.size(), lines_to.size()]
	
	editor.set_text(pre + content + post)
	editor.set_caret_line(lines_to.size())
	editor.set_caret_column(lines_to[-1].length())
	editor.scroll_vertical = scroll
	editor.update_code_completion_options(false)

func revert_change():
	#Revert inserted completion
	var code_edit = get_code_editor()
	var scroll = code_edit.scroll_vertical
	var old_text = request_code_state[0] + request_code_state[1]
	var lines_from = request_code_state[0].strip_edges(false, true).split("\n")
	code_edit.set_text(old_text)
	code_edit.set_caret_line(lines_from.size()-1)
	code_edit.set_caret_column(lines_from[-1].length())
	code_edit.scroll_vertical = scroll
	clear_highlights()

func _process(delta):
	#Update visuals and context label
	update_highlights()
	update_loading_indicator()
	update_context()

func update_highlights():
	#Make sure highlighted lines persist until explicitely removed
	#via key input
	if cur_highlight:
		var editor = get_code_editor()
		for line in range(cur_highlight[0]-1, cur_highlight[1]):
			editor.set_line_background_color(line, highlight_color)

func update_context():
	#Show currently edited file in dock
	var script = get_current_script()

func on_main_screen_changed(_screen):
	#Track current editor screen (2D, 3D, Script)
	screen = _screen

func get_current_script():
	#Get currently edited script
	if !editor_interface: return
	var script_editor = editor_interface.get_script_editor()
	return script_editor.get_current_script()

func get_code_editor():
	#Get currently used code editor
	#This does not return the shader editor!
	if !editor_interface: return
	var script_editor = editor_interface.get_script_editor()
	var base_editor = script_editor.get_current_editor()
	if base_editor:
		var code_edit = base_editor.get_base_editor()
		return code_edit
	return null

func request_completion():
	print_rich("[b]request_completion[/b] - Asking to complete the code")
	#Get current code and request completion from active model
	#if request_code_state: return
	#update_loading_indicator(true)
	var pre_post = get_pre_post()
	var llm = get_llm()
	print_rich("[b]request_completion[/b] - LLM found", llm)
	if !llm: return
	llm._send_user_prompt(pre_post[0], pre_post[1])
	request_code_state = pre_post


#Make an add function

func get_pre_post():
	#Split current code based on caret position
	var editor: Control = get_code_editor()
	var text = editor.get_text()
	var pos = Vector2(editor.get_caret_line(), editor.get_caret_column())
	var pre = ""
	var post = ""
	for i in range(pos.x):
		pre += editor.get_line(i) + "\n"
	pre += editor.get_line(pos.x).substr(0,pos.y)
	post += editor.get_line(pos.x).substr(pos.y) + "\n"
	for ii in range(pos.x+1, editor.get_line_count()):
		post += editor.get_line(ii) + "\n"
	return [pre, post]

#Wrinte ad add function

func get_llm():
	#Get currently active llm and set active model
	var llm = lmStudioCompletions
	match providerInput.selected:
		0:
			llm = ollamaCompletions
		1:
			llm = lmStudioCompletions
		2:
			llm = geminiCompletions
	return llm

func matches_request_state(pre, post):
	#Check if code passed for completion request matches current code
	return request_code_state[0] == pre and request_code_state[1] == post

func set_model(model_name):
	#Apply selected model
	print_rich("[b]set_model[/b] - Setted model: ", model_name)
	cur_model = model_name
	var llm = get_llm()
	llm._set_model(model_name)


func set_shortcut_modifier(modifier):
	#Apply selected shortcut modifier
	cur_shortcut_modifier = modifier

func set_shortcut_key(key):
	#Apply selected shortcut key
	cur_shortcut_key = key


func _on_code_completion_received(completion, pre, post):
	#Attempt to insert received code completion
	print_rich("[b]_on_code_completion_received[/b] - Checking parameter: ", completion)
	remove_loading_indicator()
	if matches_request_state(pre, post):
		insert_completion(completion, pre, post)
	else:
		clear_highlights()

func _on_code_completion_error(error):
	#Display error
	remove_loading_indicator()
	clear_highlights()
	push_error(error)



func _on_model_selected(index):
	#Apply setting and store in config file
	set_model(model_select.get_item_text(index))
	store_config()

func _on_shortcut_modifier_selected(index):
	#Apply setting and store in config file
	set_shortcut_modifier(shortcut_modifier_select.get_item_text(index))
	store_config()

func _on_shortcut_key_selected(index):
	#Apply setting and store in config file
	set_shortcut_key(shortcut_key_select.get_item_text(index))
	store_config()

func store_config():
	#Store current setting in config file
	var config = ConfigFile.new()
	config.set_value("preferences", "model", cur_model)
	config.set_value("preferences", "provider", provider)
	config.set_value("preferences", "shortcut_modifier", cur_shortcut_modifier)
	config.set_value("preferences", "shortcut_key", cur_shortcut_key)
	config.set_value("preferences", "apiKey", apiKey)
	config.save_encrypted_pass(PREFERENCES_STORAGE_NAME, PREFERENCES_PASS)

func load_config():
	#Retrieve current settings from config file
	var config = ConfigFile.new()
	var err = config.load_encrypted_pass(PREFERENCES_STORAGE_NAME, PREFERENCES_PASS)
	if err != OK: return
	cur_model = config.get_value("preferences", "model", cur_model)
	provider = config.get_value("preferences", "provider", provider)
	apiKey = config.get_value("preferences", "apiKey", apiKey)
	apiKeyInput.text = apiKey
	providerInput.selected = provider
	apply_by_value(model_select, cur_model)
	set_model(model_select.get_item_text(model_select.selected))
	cur_shortcut_modifier = config.get_value("preferences", "shortcut_modifier", cur_shortcut_modifier)
	apply_by_value(shortcut_modifier_select, cur_shortcut_modifier)
	cur_shortcut_key = config.get_value("preferences", "shortcut_key", cur_shortcut_key)
	apply_by_value(shortcut_key_select, cur_shortcut_key)
	lmStudioCompletions._set_url(urlTextInput.text)
	ollamaCompletions._set_url(urlTextInput.text)
	geminiCompletions._set_api_key(apiKey)
	_on_provider_item_selected(providerInput.selected)
	

func apply_by_value(option_button, value):
	#Select item for option button based on value instead of index
	for i in option_button.item_count:
		if option_button.get_item_text(i) == value:
			option_button.select(i)

func _on_provider_item_selected(index: int) -> void:
	provider = index
	match index:
		0:
			urlContainer.visible = true
			apiKeyContainer.visible = false
			urlTextInput.text = "http://localhost:11434"
			self.updateOllamaModel()
		1:
			urlContainer.visible = true
			apiKeyContainer.visible = false
			urlTextInput.text = "http://127.0.0.1:1234"
			self.updateLmStudioModel()
		2:
			urlContainer.visible = false
			apiKeyContainer.visible = true
			self.updateGeminiModel()
	lmStudioCompletions._set_url(urlTextInput.text)
	ollamaCompletions._set_url(urlTextInput.text)
	store_config()


func updateOllamaModel():
	reloadButton.visible = false
	loadingIndicator.visible = true
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed",self._ollamaModelLoaded)
	var error = http_request.request(urlTextInput.text+"/api/tags")
	if error != OK:
		reloadButton.visible = true
		loadingIndicator.visible = false
		pass
		# handle the error

func _ollamaModelLoaded(result, response_code, headers, body):
	reloadButton.visible = true
	loadingIndicator.visible = false
	if result != HTTPRequest.RESULT_SUCCESS:
		print("Error on ollama model request")
	var test_json_conv = JSON.new()
	test_json_conv.parse(body.get_string_from_utf8())
	var json = test_json_conv.get_data()
	model_select.clear()
	for model in json.models:
		model_select.add_item(model.model)
	model_select.select(0)


func updateLmStudioModel():
	reloadButton.visible = false
	loadingIndicator.visible = true
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed",self._lmStudioModelLoaded)
	var error = http_request.request(urlTextInput.text+"/v1/models/")
	if error != OK:
		reloadButton.visible = true
		loadingIndicator.visible = false
		pass
		# handle the error

func _lmStudioModelLoaded(result, response_code, headers, body):
	reloadButton.visible = true
	loadingIndicator.visible = false
	if result != HTTPRequest.RESULT_SUCCESS:
		print("Error on LmStudio model request")
	var test_json_conv = JSON.new()
	test_json_conv.parse(body.get_string_from_utf8())
	var json = test_json_conv.get_data()
	model_select.clear()
	for model in json.data:
		model_select.add_item(model.id)
	model_select.select(0)

func updateGeminiModel():
	reloadButton.visible = false
	loadingIndicator.visible = true
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed",self._geminiModelLoaded)
	var error = http_request.request("https://generativelanguage.googleapis.com/v1beta/models?pageSize=50&pageToken=&key="+apiKey)
	if error != OK:
		reloadButton.visible = true
		loadingIndicator.visible = false
		pass
		# handle the error


func _geminiModelLoaded(result, response_code, headers, body):
	reloadButton.visible = true
	loadingIndicator.visible = false
	if result != HTTPRequest.RESULT_SUCCESS:
		print("Error on gemini model request")
	var test_json_conv = JSON.new()
	test_json_conv.parse(body.get_string_from_utf8())
	var json = test_json_conv.get_data()
	model_select.clear()
	var i: int = 0
	var selectedModel: int = 0
	for model in json.models:
		i = i+1
		model_select.add_item(model.name)
		if model.name == "models/gemini-2.0-flash":
			selectedModel = i-1;
			geminiCompletions._set_model(model.name)
	model_select.select(selectedModel)

func _on_texture_button_button_down() -> void:
	#Refresh model based on provider
	print_rich("[b]_on_texture_button_button_down[/b] - Loading new model for provider: ",providerInput.selected)
	match providerInput.selected:
		0:
			self.updateOllamaModel()
		1:
			self.updateLmStudioModel()
		2:
			self.updateGeminiModel()
	pass # Replace with function body.


func _on_url_text_changed(new_text: String) -> void:
	print_rich("[b]_on_url_text_changed[/b] - Changing text: ",new_text," for provider: ",providerInput.selected)
	match providerInput.selected:
		0:
			ollamaCompletions._set_url(new_text)
			pass
		1:
			lmStudioCompletions._set_url(new_text)
			pass
		2:
			apiKey = new_text
			geminiCompletions._set_api_key(new_text)
			pass
	store_config()


func _on_check_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		settingsSection.visible = true
	else:
		settingsSection.visible = false





func _on_enable_chat_toggled(toggled_on: bool) -> void:
	if toggled_on:
		chatSection.visible = true
	else:
		chatSection.visible = false



func _botMessage(text:String ) -> void:
	var label: RichTextLabel = RichTextLabel.new()
	var theme = ResourceLoader.load("res://addons/copilot-advanced/asset/BotTheme.tres")
	label.theme = theme
	label.text = text
	label.bbcode_enabled = true
	label.fit_content = true
	label.selection_enabled = true
	chatContainer.add_child(label)
	#Create horizontal separator
	var hseparator: HSeparator = HSeparator.new()
	hseparator.custom_minimum_size = Vector2(0,35)
	chatContainer.add_child(hseparator)
	#Scroll to end
	await get_tree().process_frame 
	chatSection.scroll_vertical = chatSection.get_v_scroll_bar().max_value


func _userMessage(text:String ) -> void:
	var label: RichTextLabel = RichTextLabel.new()
	var theme = ResourceLoader.load("res://addons/copilot-advanced/asset/UserTheme.tres")
	label.theme = theme
	label.text = text
	label.bbcode_enabled = true
	label.fit_content = true
	chatContainer.add_child(label)
	#Create horizontal separator
	var hseparator: HSeparator = HSeparator.new()
	hseparator.custom_minimum_size = Vector2(0,35)
	chatContainer.add_child(hseparator)
	#Scroll to end
	await get_tree().process_frame 
	chatSection.scroll_vertical = chatSection.get_v_scroll_bar().max_value

func _on_send_chat_message_pressed() -> void:
	print_rich("[b]_on_send_chat_message_pressed[/b] - Sending message")
	#Send chat message
	if !inputChat:
		inputChat = get_node("%InputChat")
	var text = inputChat.text
	#Logic to call the API
	_userMessage(text)
	inputChat.text = ""
	get_llm().chat_message(text)


func _on_send_chat_message_2_pressed() -> void:
	get_llm()._clean_chat()
	for c in chatContainer.get_children():
		c.queue_free()


func _on_lm_studio_completion_chat_received(text: Variant) -> void:
	_botMessage(text)
